const std = @import("std");

const docker_socket_path = "/var/run/docker.sock";
const max_response_size = 4 * 1024 * 1024; // 4 MiB cap

pub fn proxyGet(alloc: std.mem.Allocator, req: *std.http.Server.Request, engine_path: []const u8) !void {
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

    // Send raw HTTP/1.1 request over the unix socket
    var request_buf: [2048]u8 = undefined;
    const request_line = try std.fmt.bufPrint(&request_buf, "GET {s} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", .{engine_path});

    var write_buf: [4096]u8 = undefined;
    var writer = sock.writer(&write_buf).file_writer;
    _ = try writer.interface.write(request_line);
    try writer.interface.flush();

    // Read the full response
    var response_data = std.ArrayList(u8).init(alloc);
    defer response_data.deinit();

    var read_buf: [8192]u8 = undefined;
    var sock_reader = sock.reader(&read_buf).file_reader;
    while (true) {
        var chunk: [4096]u8 = undefined;
        const n = sock_reader.interface.read(&chunk) catch break;
        if (n == 0) break;
        try response_data.appendSlice(chunk[0..n]);
        if (response_data.items.len > max_response_size) break;
    }

    const raw = response_data.items;

    // Find body after \r\n\r\n header separator
    const body = if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |pos|
        raw[pos + 4 ..]
    else
        raw;

    // Transfer-Encoding: chunked requires decoding
    const is_chunked = std.mem.indexOf(u8, raw, "Transfer-Encoding: chunked") != null;

    if (is_chunked) {
        const decoded = dechunk(alloc, body) catch body;
        defer if (decoded.ptr != body.ptr) alloc.free(decoded);
        try req.respond(decoded, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
    } else {
        try req.respond(body, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
    }
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
        pos = chunk_end + 2; // skip trailing \r\n
    }

    return try result.toOwnedSlice();
}
