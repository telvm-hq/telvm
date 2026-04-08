const std = @import("std");

const docker_socket_path = "/var/run/docker.sock";
const max_response_size = 4 * 1024 * 1024; // 4 MiB cap
const max_request_body = 1 * 1024 * 1024; // 1 MiB cap for client POST bodies

pub fn proxyGet(alloc: std.mem.Allocator, req: *std.http.Server.Request, engine_path: []const u8) !void {
    try proxyRequest(alloc, req, "GET", engine_path, null);
}

pub fn proxyPost(alloc: std.mem.Allocator, req: *std.http.Server.Request, engine_path: []const u8) !void {
    const body = readRequestBody(alloc, req) catch null;
    defer if (body) |b| alloc.free(b);
    try proxyRequest(alloc, req, "POST", engine_path, body);
}

pub fn proxyDelete(alloc: std.mem.Allocator, req: *std.http.Server.Request, engine_path: []const u8) !void {
    try proxyRequest(alloc, req, "DELETE", engine_path, null);
}

fn readRequestBody(alloc: std.mem.Allocator, req: *std.http.Server.Request) ![]const u8 {
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    var rdr = try req.reader();
    while (true) {
        var chunk: [4096]u8 = undefined;
        const n = rdr.read(&chunk) catch break;
        if (n == 0) break;
        try buf.appendSlice(chunk[0..n]);
        if (buf.items.len > max_request_body) break;
    }

    if (buf.items.len == 0) {
        buf.deinit();
        return error.EmptyBody;
    }

    return try buf.toOwnedSlice();
}

fn proxyRequest(
    alloc: std.mem.Allocator,
    req: *std.http.Server.Request,
    method: []const u8,
    engine_path: []const u8,
    body: ?[]const u8,
) !void {
    const sock = std.net.connectUnixSocket(docker_socket_path) catch {
        try req.respond("{\"error\":\"docker socket unreachable\"}\n", .{
            .status = .service_unavailable,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        return;
    };
    defer sock.close();

    const writer = sock.writer();

    if (body) |b| {
        var cl_buf: [20]u8 = undefined;
        const content_len = std.fmt.bufPrint(&cl_buf, "{d}", .{b.len}) catch "0";

        var header_buf: [4096]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "{s} {s} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {s}\r\n\r\n", .{ method, engine_path, content_len }) catch {
            try req.respond("{\"error\":\"header too large\"}\n", .{ .status = .internal_server_error });
            return;
        };
        try writer.writeAll(header);
        try writer.writeAll(b);
    } else {
        var header_buf: [2048]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "{s} {s} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", .{ method, engine_path }) catch {
            try req.respond("{\"error\":\"header too large\"}\n", .{ .status = .internal_server_error });
            return;
        };
        try writer.writeAll(header);
    }

    var response_data = std.ArrayList(u8).init(alloc);
    defer response_data.deinit();

    const reader = sock.reader();
    while (true) {
        var chunk: [4096]u8 = undefined;
        const n = reader.read(&chunk) catch break;
        if (n == 0) break;
        try response_data.appendSlice(chunk[0..n]);
        if (response_data.items.len > max_response_size) break;
    }

    const raw = response_data.items;

    const header_end = std.mem.indexOf(u8, raw, "\r\n\r\n");
    const header_section = if (header_end) |pos| raw[0..pos] else raw[0..0];
    const response_body = if (header_end) |pos| raw[pos + 4 ..] else raw;

    const status = extractHttpStatus(header_section);
    const is_chunked = std.mem.indexOf(u8, header_section, "Transfer-Encoding: chunked") != null;

    const response_status = statusToEnum(status);

    if (is_chunked) {
        const decoded = dechunk(alloc, response_body) catch response_body;
        defer if (decoded.ptr != response_body.ptr) alloc.free(decoded);
        try req.respond(decoded, .{
            .status = response_status,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/octet-stream" },
            },
        });
    } else {
        try req.respond(response_body, .{
            .status = response_status,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/octet-stream" },
            },
        });
    }
}

fn extractHttpStatus(header: []const u8) u16 {
    // Parse "HTTP/1.1 200 OK" → 200
    const first_line_end = std.mem.indexOf(u8, header, "\r\n") orelse header.len;
    const first_line = header[0..first_line_end];
    const space1 = std.mem.indexOf(u8, first_line, " ") orelse return 200;
    const after_space = first_line[space1 + 1 ..];
    const space2 = std.mem.indexOf(u8, after_space, " ") orelse after_space.len;
    return std.fmt.parseInt(u16, after_space[0..space2], 10) catch 200;
}

fn statusToEnum(code: u16) std.http.Status {
    return @enumFromInt(code);
}

fn dechunk(alloc: std.mem.Allocator, data: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();
    var pos: usize = 0;

    while (pos < data.len) {
        const line_end = std.mem.indexOfPos(u8, data, pos, "\r\n") orelse break;
        const size_str = std.mem.trimRight(u8, data[pos..line_end], " ");
        const chunk_size = std.fmt.parseInt(usize, size_str, 16) catch break;
        if (chunk_size == 0) break;

        const chunk_start = line_end + 2;
        const chunk_end = chunk_start + chunk_size;
        if (chunk_end > data.len) break;

        try result.appendSlice(data[chunk_start..chunk_end]);
        pos = chunk_end + 2;
    }

    return try result.toOwnedSlice();
}
