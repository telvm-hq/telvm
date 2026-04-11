const std = @import("std");
const router = @import("router.zig");

pub const version = "0.1.0";
pub const default_max_body: usize = 4 * 1024 * 1024; // 4 MiB

pub const Config = struct {
    port: u16,
    token: []const u8,
    root: []const u8,
    max_body: usize,
};

fn parseArgs(alloc: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();

    var port: u16 = 9200;
    var token: []const u8 = "";
    var root: []const u8 = "";
    var max_body: usize = default_max_body;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--port")) {
            if (args.next()) |v| {
                port = std.fmt.parseInt(u16, v, 10) catch 9200;
            }
        } else if (std.mem.eql(u8, arg, "--token")) {
            if (args.next()) |v| {
                token = v;
            }
        } else if (std.mem.eql(u8, arg, "--root")) {
            if (args.next()) |v| {
                root = v;
            }
        } else if (std.mem.eql(u8, arg, "--max-body")) {
            if (args.next()) |v| {
                max_body = std.fmt.parseInt(usize, v, 10) catch default_max_body;
            }
        } else if (std.mem.eql(u8, arg, "--version")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("retardeel {s}\n", .{version});
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--help")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print(
                \\retardeel — dead-simple filesystem agent for telvm workspaces
                \\
                \\Usage: retardeel [OPTIONS]
                \\
                \\Options:
                \\  --port <PORT>        Listen port (default: 9200)
                \\  --token <TOKEN>      Bearer token for auth (required)
                \\  --root <ABS_PATH>    Workspace root to jail into (required)
                \\  --max-body <BYTES>   Max request/response body (default: 4194304)
                \\  --version            Print version and exit
                \\  --help               Show this help
                \\
            , .{});
            std.process.exit(0);
        }
    }

    return .{ .port = port, .token = token, .root = root, .max_body = max_body };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const config = try parseArgs(alloc);
    const stderr = std.io.getStdErr().writer();

    if (config.token.len == 0) {
        try stderr.print("error: --token is required\n", .{});
        std.process.exit(1);
    }

    if (config.root.len == 0) {
        try stderr.print("error: --root is required\n", .{});
        std.process.exit(1);
    }

    // Resolve root to its canonical absolute path at startup.
    const resolved_root = std.fs.cwd().realpathAlloc(alloc, config.root) catch |err| {
        try stderr.print("error: cannot resolve --root '{s}': {}\n", .{ config.root, err });
        std.process.exit(1);
    };

    const ctx = router.Context{
        .root = resolved_root,
        .max_body = config.max_body,
    };

    try stderr.print("retardeel {s} listening on :{d} root={s}\n", .{ version, config.port, resolved_root });

    const address = std.net.Address.parseIp("0.0.0.0", config.port) catch unreachable;
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const conn = server.accept() catch |err| {
            stderr.print("accept error: {}\n", .{err}) catch {};
            continue;
        };

        handleConnection(alloc, conn, config.token, ctx) catch |err| {
            stderr.print("request error: {}\n", .{err}) catch {};
        };
        conn.stream.close();
    }
}

fn handleConnection(alloc: std.mem.Allocator, conn: std.net.Server.Connection, token: []const u8, ctx: router.Context) !void {
    var read_buf: [8192]u8 = undefined;
    var http_server = std.http.Server.init(conn, &read_buf);

    var req = try http_server.receiveHead();

    if (!checkAuth(&req, token)) {
        try req.respond("{\"error\":\"unauthorized\"}\n", .{
            .status = .unauthorized,
            .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }},
        });
        return;
    }

    try router.route(alloc, &req, ctx);
}

fn checkAuth(req: *std.http.Server.Request, expected_token: []const u8) bool {
    if (expected_token.len == 0) return true;

    var it = req.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
            const value = header.value;
            const prefix = "Bearer ";
            if (!std.mem.startsWith(u8, value, prefix)) return false;
            const provided = value[prefix.len..];
            return std.mem.eql(u8, provided, expected_token);
        }
    }
    return false;
}
