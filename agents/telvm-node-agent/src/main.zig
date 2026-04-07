const std = @import("std");
const router = @import("router.zig");

pub const version = "0.1.0";

const Config = struct {
    port: u16,
    token: []const u8,
};

fn parseArgs(alloc: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next(); // skip binary name

    var port: u16 = 9100;
    var token: []const u8 = "";

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--port")) {
            if (args.next()) |v| {
                port = std.fmt.parseInt(u16, v, 10) catch 9100;
            }
        } else if (std.mem.eql(u8, arg, "--token")) {
            if (args.next()) |v| {
                token = v;
            }
        } else if (std.mem.eql(u8, arg, "--version")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("telvm-node-agent {s}\n", .{version});
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--help")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print(
                \\telvm-node-agent — minimal HTTP agent for telvm cluster
                \\
                \\Usage: telvm-node-agent [OPTIONS]
                \\
                \\Options:
                \\  --port <PORT>    Listen port (default: 9100)
                \\  --token <TOKEN>  Bearer token for auth (required)
                \\  --version        Print version and exit
                \\  --help           Show this help
                \\
            , .{});
            std.process.exit(0);
        }
    }

    return .{ .port = port, .token = token };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const config = try parseArgs(alloc);

    if (config.token.len == 0) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("error: --token is required\n", .{});
        std.process.exit(1);
    }

    {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("telvm-node-agent {s} listening on :{d}\n", .{ version, config.port });
    }

    const address = std.net.Address.parseIp("0.0.0.0", config.port) catch unreachable;
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const conn = server.accept() catch |err| {
            const stderr = std.io.getStdErr().writer();
            stderr.print("accept error: {}\n", .{err}) catch {};
            continue;
        };

        handleConnection(alloc, conn, config.token) catch |err| {
            const stderr = std.io.getStdErr().writer();
            stderr.print("request error: {}\n", .{err}) catch {};
        };
        conn.stream.close();
    }
}

fn handleConnection(alloc: std.mem.Allocator, conn: std.net.Server.Connection, token: []const u8) !void {
    var read_buf: [8192]u8 = undefined;
    var http_server = std.http.Server.init(conn, &read_buf);

    var req = try http_server.receiveHead();

    if (!checkAuth(&req, token)) {
        try req.respond("401 Unauthorized\n", .{ .status = .unauthorized });
        return;
    }

    try router.route(alloc, &req);
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
