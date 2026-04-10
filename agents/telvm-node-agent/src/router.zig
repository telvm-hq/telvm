const std = @import("std");
const health = @import("health.zig");
const network = @import("network.zig");
const docker_proxy = @import("docker_proxy.zig");

pub fn route(alloc: std.mem.Allocator, req: *std.http.Server.Request) !void {
    const path = req.head.target;
    const method = req.head.method;

    if (std.mem.eql(u8, path, "/health")) {
        try health.handle(req);
        return;
    }

    if (std.mem.eql(u8, path, "/network")) {
        try network.handle(req);
        return;
    }

    // --- GET-only routes ---

    if (method == .GET) {
        if (std.mem.eql(u8, path, "/docker/version")) {
            try docker_proxy.proxyGet(alloc, req, "/version");
            return;
        }

        if (std.mem.eql(u8, path, "/docker/containers") or std.mem.eql(u8, path, "/docker/containers?all=true")) {
            const engine_path = if (std.mem.indexOf(u8, path, "?all=true") != null)
                "/containers/json?all=true"
            else
                "/containers/json";
            try docker_proxy.proxyGet(alloc, req, engine_path);
            return;
        }

        if (routeContainerSuffix(path, "/json")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/json", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyGet(alloc, req, engine_path);
            return;
        }

        if (routeContainerSuffix(path, "/stats")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/stats?stream=false", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyGet(alloc, req, engine_path);
            return;
        }

        if (routeContainerSuffix(path, "/logs")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/logs?stdout=1&stderr=1&tail=500", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyGet(alloc, req, engine_path);
            return;
        }

        // GET /docker/exec/:id/json
        if (routeExecSuffix(path, "/json")) |exec_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/exec/{s}/json", .{exec_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyGet(alloc, req, engine_path);
            return;
        }
    }

    // --- POST routes (lifecycle + exec) ---

    if (method == .POST) {
        if (routeContainerSuffix(path, "/start")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/start", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyPost(alloc, req, engine_path);
            return;
        }

        if (routeContainerSuffix(path, "/stop")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/stop", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyPost(alloc, req, engine_path);
            return;
        }

        if (routeContainerSuffix(path, "/restart")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/restart", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyPost(alloc, req, engine_path);
            return;
        }

        if (routeContainerSuffix(path, "/pause")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/pause", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyPost(alloc, req, engine_path);
            return;
        }

        if (routeContainerSuffix(path, "/unpause")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/unpause", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyPost(alloc, req, engine_path);
            return;
        }

        // POST /docker/containers/:id/exec (body: JSON exec config)
        if (routeContainerSuffix(path, "/exec")) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}/exec", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyPost(alloc, req, engine_path);
            return;
        }

        // POST /docker/exec/:id/start (body: JSON)
        if (routeExecSuffix(path, "/start")) |exec_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/exec/{s}/start", .{exec_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyPost(alloc, req, engine_path);
            return;
        }
    }

    // --- DELETE routes ---

    if (method == .DELETE) {
        // DELETE /docker/containers/:id → DELETE /containers/:id?force=true&v=1
        if (routeContainerId(path)) |container_id| {
            const engine_path = try std.fmt.allocPrint(alloc, "/containers/{s}?force=true&v=1", .{container_id});
            defer alloc.free(engine_path);
            try docker_proxy.proxyDelete(alloc, req, engine_path);
            return;
        }
    }

    try req.respond("404 Not Found\n", .{ .status = .not_found });
}

/// Matches /docker/containers/:id/:suffix and returns the container ID.
/// suffix must include the leading slash, e.g. "/json", "/start", "/logs".
/// Example: routeContainerSuffix("/docker/containers/abc123/json", "/json") returns "abc123"
fn routeContainerSuffix(path: []const u8, suffix: []const u8) ?[]const u8 {
    const prefix = "/docker/containers/";
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    if (!std.mem.endsWith(u8, path, suffix)) return null;

    const after_prefix = path[prefix.len..];
    const id_end = after_prefix.len - suffix.len;
    if (id_end == 0) return null;

    return after_prefix[0..id_end];
}

/// Matches /docker/exec/:id/:suffix and returns the exec ID.
fn routeExecSuffix(path: []const u8, suffix: []const u8) ?[]const u8 {
    const prefix = "/docker/exec/";
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    if (!std.mem.endsWith(u8, path, suffix)) return null;

    const after_prefix = path[prefix.len..];
    const id_end = after_prefix.len - suffix.len;
    if (id_end == 0) return null;

    return after_prefix[0..id_end];
}

/// Matches exactly /docker/containers/:id (no trailing suffix) for DELETE.
fn routeContainerId(path: []const u8) ?[]const u8 {
    const prefix = "/docker/containers/";
    if (!std.mem.startsWith(u8, path, prefix)) return null;

    const after_prefix = path[prefix.len..];
    if (after_prefix.len == 0) return null;
    // Must not contain any slashes (no sub-path)
    if (std.mem.indexOf(u8, after_prefix, "/") != null) return null;

    return after_prefix;
}
