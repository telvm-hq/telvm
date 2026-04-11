const std = @import("std");
const health = @import("health.zig");
const workspace = @import("workspace.zig");
const fs_handlers = @import("fs_handlers.zig");

pub const Context = struct {
    root: []const u8,
    max_body: usize,
};

pub fn route(alloc: std.mem.Allocator, req: *std.http.Server.Request, ctx: Context) !void {
    const path = req.head.target;
    const method = req.head.method;

    // GET routes
    if (method == .GET) {
        if (std.mem.eql(u8, path, "/health")) {
            return health.handle(req, ctx.root);
        }
        if (std.mem.eql(u8, path, "/v1/workspace")) {
            return workspace.handle(alloc, req, ctx.root);
        }
    }

    // POST routes — read body first, bounded by max_body.
    if (method == .POST) {
        const body_bytes = readBody(alloc, req, ctx.max_body) catch {
            return respondError(req, .payload_too_large, "body_too_large", "request body exceeds max-body limit");
        };
        defer alloc.free(body_bytes);

        if (std.mem.eql(u8, path, "/v1/stat")) {
            return fs_handlers.handleStat(alloc, req, ctx.root, body_bytes);
        }
        if (std.mem.eql(u8, path, "/v1/read")) {
            return fs_handlers.handleRead(alloc, req, ctx.root, body_bytes, ctx.max_body);
        }
        if (std.mem.eql(u8, path, "/v1/write")) {
            return fs_handlers.handleWrite(alloc, req, ctx.root, body_bytes, ctx.max_body);
        }
        if (std.mem.eql(u8, path, "/v1/list")) {
            return fs_handlers.handleList(alloc, req, ctx.root, body_bytes);
        }
    }

    // Fallback: 404
    try req.respond("{\"error\":\"not_found\",\"detail\":\"unknown route\"}\n", .{
        .status = .not_found,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

fn readBody(alloc: std.mem.Allocator, req: *std.http.Server.Request, max_body: usize) ![]const u8 {
    var reader = try req.reader();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = reader.read(&chunk) catch return error.ReadError;
        if (n == 0) break;
        if (buf.items.len + n > max_body) {
            buf.deinit();
            return error.BodyTooLarge;
        }
        try buf.appendSlice(chunk[0..n]);
    }

    return try buf.toOwnedSlice();
}

fn respondError(req: *std.http.Server.Request, status: std.http.Status, err_code: []const u8, detail: []const u8) !void {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const w = stream.writer();
    w.writeAll("{\"error\":\"") catch return;
    w.writeAll(err_code) catch return;
    w.writeAll("\",\"detail\":\"") catch return;
    w.writeAll(detail) catch return;
    w.writeAll("\"}") catch return;

    req.respond(buf[0..stream.pos], .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    }) catch {};
}
