const std = @import("std");
const jail = @import("jail.zig");

// ---- handleStat ----

pub fn handleStat(alloc: std.mem.Allocator, req: *std.http.Server.Request, root: []const u8, body_bytes: []const u8) !void {
    const parsed = std.json.parseFromSlice(struct { path: []const u8 }, alloc, body_bytes, .{ .ignore_unknown_fields = true }) catch {
        return respondError(req, .bad_request, "bad_request", "invalid JSON or missing field: path");
    };
    defer parsed.deinit();
    const rel = parsed.value.path;

    const resolved = jail.resolve(alloc, root, rel, true) catch |err| {
        return respondJailError(req, err, rel);
    };
    defer alloc.free(resolved);

    // Try opening as file first, then as directory.
    const stat_result = blk: {
        if (std.fs.cwd().openFile(resolved, .{})) |f| {
            defer f.close();
            break :blk f.stat() catch {
                return respondJson(req, "{\"exists\":false}");
            };
        } else |_| {
            var d = std.fs.cwd().openDir(resolved, .{}) catch {
                return respondJson(req, "{\"exists\":false}");
            };
            defer d.close();
            break :blk d.stat() catch {
                return respondJson(req, "{\"exists\":false}");
            };
        }
    };

    var buf: [512]u8 = undefined;
    const is_dir = stat_result.kind == .directory;
    const mtime_ns: i128 = stat_result.mtime;
    const mtime_s: i64 = @intCast(@divFloor(mtime_ns, 1_000_000_000));
    const body = std.fmt.bufPrint(&buf,
        \\{{"exists":true,"size":{d},"is_dir":{s},"modified_unix":{d}}}
    , .{ stat_result.size, if (is_dir) "true" else "false", mtime_s }) catch {
        return respondError(req, .internal_server_error, "internal", "stat format error");
    };
    return respondJson(req, body);
}

// ---- handleRead ----

pub fn handleRead(alloc: std.mem.Allocator, req: *std.http.Server.Request, root: []const u8, body_bytes: []const u8, max_body: usize) !void {
    const parsed = std.json.parseFromSlice(struct {
        path: []const u8,
        offset: ?u64 = null,
        limit: ?u64 = null,
    }, alloc, body_bytes, .{ .ignore_unknown_fields = true }) catch {
        return respondError(req, .bad_request, "bad_request", "invalid JSON or missing field: path");
    };
    defer parsed.deinit();

    const rel = parsed.value.path;
    const offset: u64 = parsed.value.offset orelse 0;
    const limit: usize = @intCast(@min(parsed.value.limit orelse max_body, max_body));

    const resolved = jail.resolve(alloc, root, rel, false) catch |err| {
        return respondJailError(req, err, rel);
    };
    defer alloc.free(resolved);

    const file = std.fs.cwd().openFile(resolved, .{}) catch {
        return respondError(req, .not_found, "not_found", rel);
    };
    defer file.close();

    const stat = file.stat() catch {
        return respondError(req, .internal_server_error, "internal", "stat failed");
    };
    const file_size = stat.size;

    if (offset > 0) {
        file.seekTo(offset) catch {
            return respondError(req, .bad_request, "bad_request", "seek failed");
        };
    }

    const read_buf = alloc.alloc(u8, limit) catch {
        return respondError(req, .internal_server_error, "internal", "alloc failed");
    };
    defer alloc.free(read_buf);

    const n = file.readAll(read_buf) catch {
        return respondError(req, .internal_server_error, "internal", "read failed");
    };
    const content = read_buf[0..n];
    const truncated = file_size > offset + n;

    const is_utf8 = std.unicode.utf8ValidateSlice(content);

    // Build response: header + content + footer.
    // For simplicity, use a dynamic ArrayList.
    var resp = std.ArrayList(u8).init(alloc);
    defer resp.deinit();
    const w = resp.writer();

    if (is_utf8) {
        try w.writeAll("{\"encoding\":\"utf8\",\"size\":");
        try std.fmt.formatInt(file_size, 10, .lower, .{}, w);
        try w.writeAll(",\"truncated\":");
        try w.writeAll(if (truncated) "true" else "false");
        try w.writeAll(",\"text\":");
        try std.json.stringify(content, .{}, w);
        try w.writeAll("}");
    } else {
        const b64_encoder = std.base64.standard.Encoder;
        const b64_len = b64_encoder.calcSize(content.len);
        const b64_buf = alloc.alloc(u8, b64_len) catch {
            return respondError(req, .internal_server_error, "internal", "alloc b64 failed");
        };
        defer alloc.free(b64_buf);
        const encoded = b64_encoder.encode(b64_buf, content);

        try w.writeAll("{\"encoding\":\"b64\",\"size\":");
        try std.fmt.formatInt(file_size, 10, .lower, .{}, w);
        try w.writeAll(",\"truncated\":");
        try w.writeAll(if (truncated) "true" else "false");
        try w.writeAll(",\"content_b64\":\"");
        try w.writeAll(encoded);
        try w.writeAll("\"}");
    }

    try req.respond(resp.items, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

// ---- handleWrite ----

pub fn handleWrite(alloc: std.mem.Allocator, req: *std.http.Server.Request, root: []const u8, body_bytes: []const u8, max_body: usize) !void {
    const parsed = std.json.parseFromSlice(struct {
        path: []const u8,
        text: ?[]const u8 = null,
        content_b64: ?[]const u8 = null,
        mode: ?[]const u8 = null,
    }, alloc, body_bytes, .{ .ignore_unknown_fields = true }) catch {
        return respondError(req, .bad_request, "bad_request", "invalid JSON or missing field: path");
    };
    defer parsed.deinit();

    const rel = parsed.value.path;
    const mode_str = parsed.value.mode orelse "replace";
    const is_create = std.mem.eql(u8, mode_str, "create");

    // Decode content
    var content: []const u8 = undefined;
    var content_owned = false;
    if (parsed.value.text) |t| {
        content = t;
    } else if (parsed.value.content_b64) |b64| {
        const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(b64) catch {
            return respondError(req, .bad_request, "bad_request", "invalid base64");
        };
        const decoded = alloc.alloc(u8, decoded_size) catch {
            return respondError(req, .internal_server_error, "internal", "alloc failed");
        };
        _ = std.base64.standard.Decoder.decode(decoded, b64) catch {
            alloc.free(decoded);
            return respondError(req, .bad_request, "bad_request", "invalid base64");
        };
        content = decoded;
        content_owned = true;
    } else {
        return respondError(req, .bad_request, "bad_request", "provide 'text' or 'content_b64'");
    }
    defer if (content_owned) alloc.free(content);

    if (content.len > max_body) {
        return respondError(req, .payload_too_large, "body_too_large", "content exceeds max-body limit");
    }

    const resolved = jail.resolve(alloc, root, rel, is_create) catch |err| {
        return respondJailError(req, err, rel);
    };
    defer alloc.free(resolved);

    // "create" mode: file must not already exist.
    if (is_create) {
        if (std.fs.cwd().openFile(resolved, .{})) |f| {
            f.close();
            return respondError(req, .conflict, "already_exists", rel);
        } else |err| {
            if (err != error.FileNotFound) {
                return respondError(req, .internal_server_error, "internal", "access check failed");
            }
        }
    }

    return writeAtomically(alloc, req, resolved, content);
}

fn writeAtomically(alloc: std.mem.Allocator, req: *std.http.Server.Request, resolved: []const u8, content: []const u8) !void {
    const dir_path = std.fs.path.dirname(resolved) orelse "/";
    var dir = std.fs.cwd().openDir(dir_path, .{}) catch {
        return respondError(req, .internal_server_error, "internal", "cannot open parent dir");
    };
    defer dir.close();

    // Create temp file in same directory for atomic rename.
    const basename = std.fs.path.basename(resolved);
    var tmp_name_buf: [280]u8 = undefined;
    const tmp_name = std.fmt.bufPrint(&tmp_name_buf, ".retardeel-{s}.tmp", .{basename}) catch {
        return respondError(req, .internal_server_error, "internal", "tmp name too long");
    };

    const tmp_file = dir.createFile(tmp_name, .{ .truncate = true }) catch {
        return respondError(req, .internal_server_error, "internal", "cannot create temp file");
    };

    tmp_file.writeAll(content) catch {
        tmp_file.close();
        dir.deleteFile(tmp_name) catch {};
        return respondError(req, .internal_server_error, "internal", "write failed");
    };
    tmp_file.close();

    // Compute SHA-256.
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(content, &hash, .{});
    var hex: [64]u8 = undefined;
    const hex_str = std.fmt.bufPrint(&hex, "{}", .{std.fmt.fmtSliceHexLower(&hash)}) catch "?";

    // Atomic rename.
    dir.rename(tmp_name, basename) catch {
        dir.deleteFile(tmp_name) catch {};
        return respondError(req, .internal_server_error, "internal", "rename failed");
    };

    var buf: [256]u8 = undefined;
    const body = std.fmt.bufPrint(&buf,
        \\{{"ok":true,"sha256":"{s}","size":{d}}}
    , .{ hex_str, content.len }) catch {
        return respondError(req, .internal_server_error, "internal", "format error");
    };

    _ = alloc;
    return respondJson(req, body);
}

// ---- handleList ----

pub fn handleList(alloc: std.mem.Allocator, req: *std.http.Server.Request, root: []const u8, body_bytes: []const u8) !void {
    const parsed = std.json.parseFromSlice(struct {
        path: ?[]const u8 = null,
        max_entries: ?u32 = null,
    }, alloc, body_bytes, .{ .ignore_unknown_fields = true }) catch {
        return respondError(req, .bad_request, "bad_request", "invalid JSON");
    };
    defer parsed.deinit();

    const rel = parsed.value.path orelse ".";
    const max_entries: u32 = @min(parsed.value.max_entries orelse 200, 1000);

    const resolved = jail.resolve(alloc, root, rel, false) catch |err| {
        return respondJailError(req, err, rel);
    };
    defer alloc.free(resolved);

    var dir = std.fs.cwd().openDir(resolved, .{ .iterate = true }) catch {
        return respondError(req, .not_found, "not_found", rel);
    };
    defer dir.close();

    var resp = std.ArrayList(u8).init(alloc);
    defer resp.deinit();
    const w = resp.writer();

    try w.writeAll("{\"entries\":[");
    var count: u32 = 0;
    var truncated = false;
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (count >= max_entries) {
            truncated = true;
            break;
        }
        if (count > 0) try w.writeAll(",");

        const is_dir = entry.kind == .directory;
        try w.writeAll("{\"name\":");
        try std.json.stringify(entry.name, .{}, w);
        try w.writeAll(",\"is_dir\":");
        try w.writeAll(if (is_dir) "true" else "false");

        // Try to get size for files (skip for dirs).
        if (!is_dir) {
            const stat = dir.statFile(entry.name) catch null;
            if (stat) |s| {
                try w.writeAll(",\"size\":");
                try std.fmt.formatInt(s.size, 10, .lower, .{}, w);
            }
        }

        try w.writeAll("}");
        count += 1;
    }

    try w.writeAll("],\"truncated\":");
    try w.writeAll(if (truncated) "true" else "false");
    try w.writeAll("}");

    try req.respond(resp.items, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

// ---- Helpers ----

fn respondJson(req: *std.http.Server.Request, body: []const u8) !void {
    try req.respond(body, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

fn respondError(req: *std.http.Server.Request, status: std.http.Status, err_code: []const u8, detail: []const u8) !void {
    var buf: [1024]u8 = undefined;
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

fn respondJailError(req: *std.http.Server.Request, err: anyerror, rel: []const u8) !void {
    const code = jail.errorName(err);

    // ParentNotFound or missing file -> 404, otherwise 403.
    const status: std.http.Status = switch (err) {
        jail.JailError.ParentNotFound => .not_found,
        else => .forbidden,
    };

    return respondError(req, status, code, rel);
}
