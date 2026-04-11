const std = @import("std");

pub const JailError = error{
    AbsolutePathRejected,
    PathEscape,
    NullByteInPath,
    EmptyPath,
    ParentNotFound,
};

/// Resolve `rel_path` under `root`, following symlinks, and verify the result
/// stays inside the jail. Returns a heap-allocated absolute path (caller frees).
/// For files that don't exist yet, set `allow_missing` to resolve the parent
/// directory instead and append the filename.
pub fn resolve(alloc: std.mem.Allocator, root: []const u8, rel_path: []const u8, allow_missing: bool) (JailError || std.mem.Allocator.Error || std.fs.Dir.OpenError || std.posix.RealPathError)![]const u8 {
    if (rel_path.len == 0) return JailError.EmptyPath;
    if (rel_path[0] == '/') return JailError.AbsolutePathRejected;
    if (std.mem.indexOfScalar(u8, rel_path, 0) != null) return JailError.NullByteInPath;

    const joined = try std.fs.path.join(alloc, &.{ root, rel_path });
    defer alloc.free(joined);

    if (std.fs.cwd().realpathAlloc(alloc, joined)) |resolved| {
        if (!std.mem.startsWith(u8, resolved, root)) {
            alloc.free(resolved);
            return JailError.PathEscape;
        }
        // Ensure the resolved path is either exactly root or continues with '/'
        if (resolved.len > root.len and resolved[root.len] != '/') {
            alloc.free(resolved);
            return JailError.PathEscape;
        }
        return resolved;
    } else |_| {
        if (!allow_missing) return JailError.ParentNotFound;

        // File does not exist yet — resolve parent directory instead.
        const dir_part = std.fs.path.dirname(joined) orelse root;
        const base_part = std.fs.path.basename(joined);

        const resolved_parent = std.fs.cwd().realpathAlloc(alloc, dir_part) catch {
            return JailError.ParentNotFound;
        };

        if (!std.mem.startsWith(u8, resolved_parent, root)) {
            alloc.free(resolved_parent);
            return JailError.PathEscape;
        }
        if (resolved_parent.len > root.len and resolved_parent[root.len] != '/') {
            alloc.free(resolved_parent);
            return JailError.PathEscape;
        }

        defer alloc.free(resolved_parent);
        return std.fs.path.join(alloc, &.{ resolved_parent, base_part });
    }
}

/// Return a human-readable error name for JSON error envelopes.
pub fn errorName(err: anyerror) []const u8 {
    return switch (err) {
        JailError.AbsolutePathRejected => "absolute_path_rejected",
        JailError.PathEscape => "path_escape",
        JailError.NullByteInPath => "null_byte_in_path",
        JailError.EmptyPath => "empty_path",
        JailError.ParentNotFound => "parent_not_found",
        else => "jail_error",
    };
}
