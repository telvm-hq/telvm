const std = @import("std");

const Manifest = struct {
    filename: []const u8,
    hint: []const u8,
};

const known = [_]Manifest{
    .{ .filename = "mix.exs", .hint = "elixir" },
    .{ .filename = "package.json", .hint = "node" },
    .{ .filename = "Cargo.toml", .hint = "rust" },
    .{ .filename = "requirements.txt", .hint = "python" },
    .{ .filename = "pyproject.toml", .hint = "python" },
    .{ .filename = "go.mod", .hint = "go" },
    .{ .filename = "pom.xml", .hint = "java" },
    .{ .filename = "build.gradle", .hint = "java" },
    .{ .filename = "Makefile", .hint = "make" },
    .{ .filename = "Dockerfile", .hint = "container" },
    .{ .filename = "Gemfile", .hint = "ruby" },
    .{ .filename = "composer.json", .hint = "php" },
    .{ .filename = "build.zig", .hint = "zig" },
    .{ .filename = "CMakeLists.txt", .hint = "cmake" },
    .{ .filename = "flake.nix", .hint = "nix" },
};

pub fn handle(alloc: std.mem.Allocator, req: *std.http.Server.Request, root: []const u8) !void {
    var out: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&out);
    const w = stream.writer();

    var found_names: [known.len]bool = .{false} ** known.len;
    for (known, 0..) |m, i| {
        const path = std.fs.path.join(alloc, &.{ root, m.filename }) catch continue;
        defer alloc.free(path);
        std.fs.accessAbsolute(path, .{}) catch continue;
        found_names[i] = true;
    }

    try w.writeAll("{\"manifests\":[");
    var first_manifest = true;
    for (known, 0..) |m, i| {
        if (!found_names[i]) continue;
        if (!first_manifest) try w.writeAll(",");
        first_manifest = false;
        try w.writeAll("\"");
        try w.writeAll(m.filename);
        try w.writeAll("\"");
    }

    try w.writeAll("],\"hints\":[");
    var first_hint = true;
    for (known, 0..) |m, i| {
        if (!found_names[i]) continue;
        var already = false;
        for (known[0..i], 0..) |prev, j| {
            if (found_names[j] and std.mem.eql(u8, prev.hint, m.hint)) {
                already = true;
                break;
            }
        }
        if (already) continue;
        if (!first_hint) try w.writeAll(",");
        first_hint = false;
        try w.writeAll("\"");
        try w.writeAll(m.hint);
        try w.writeAll("\"");
    }

    try w.writeAll("]}");

    const body = out[0..stream.pos];
    try req.respond(body, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}
