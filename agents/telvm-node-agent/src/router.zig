const std = @import("std");
const health = @import("health.zig");
const docker_proxy = @import("docker_proxy.zig");

pub fn route(alloc: std.mem.Allocator, req: *std.http.Server.Request) !void {
    const path = req.head.target;

    if (std.mem.eql(u8, path, "/health")) {
        try health.handle(req);
    } else if (std.mem.eql(u8, path, "/docker/version")) {
        try docker_proxy.proxyGet(alloc, req, "/version");
    } else if (std.mem.eql(u8, path, "/docker/containers") or std.mem.eql(u8, path, "/docker/containers?all=true")) {
        const engine_path = if (std.mem.indexOf(u8, path, "?all=true") != null)
            "/containers/json?all=true"
        else
            "/containers/json";
        try docker_proxy.proxyGet(alloc, req, engine_path);
    } else if (std.mem.startsWith(u8, path, "/docker/containers/") and std.mem.endsWith(u8, path, "/stats")) {
        const after_prefix = path["/docker/containers/".len..];
        const id_end = std.mem.indexOf(u8, after_prefix, "/") orelse {
            try req.respond("404 Not Found\n", .{ .status = .not_found });
            return;
        };
        const container_id = after_prefix[0..id_end];
        const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/stats?stream=false", .{container_id});
        defer alloc.free(engine_path);
        try docker_proxy.proxyGet(alloc, req, engine_path);
    } else {
        try req.respond("404 Not Found\n", .{ .status = .not_found });
    }
}
