const std = @import("std");

pub fn handle(req: *std.http.Server.Request) !void {
    var buf: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    var out: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&out);
    const w = stream.writer();

    try w.writeAll("{\"interfaces\":[");

    var dir = std.fs.openDirAbsolute("/sys/class/net", .{ .iterate = true }) catch {
        try w.writeAll("],\"error\":\"cannot open /sys/class/net\"}");
        const body = out[0..stream.pos];
        try req.respond(body, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        });
        return;
    };
    defer dir.close();

    var first = true;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const name = entry.name;
        if (std.mem.eql(u8, name, "lo")) continue;

        if (!first) try w.writeAll(",");
        first = false;

        try w.writeAll("{\"name\":\"");
        try w.writeAll(name);
        try w.writeAll("\"");

        // operstate
        const operstate = readSysFile(alloc, "/sys/class/net", name, "operstate") catch "unknown";
        try w.writeAll(",\"operstate\":\"");
        try w.writeAll(operstate);
        try w.writeAll("\"");

        // address (MAC)
        const mac = readSysFile(alloc, "/sys/class/net", name, "address") catch "unknown";
        try w.writeAll(",\"mac\":\"");
        try w.writeAll(mac);
        try w.writeAll("\"");

        // is virtual?
        var link_buf: [512]u8 = undefined;
        const is_virtual = blk: {
            const link_path = std.fmt.bufPrint(&link_buf, "/sys/class/net/{s}", .{name}) catch break :blk false;
            var real_buf: [1024]u8 = undefined;
            const real = std.fs.readLinkAbsolute(link_path, &real_buf) catch break :blk false;
            break :blk std.mem.indexOf(u8, real, "/virtual/") != null;
        };
        try w.writeAll(if (is_virtual) ",\"virtual\":true" else ",\"virtual\":false");

        // IPv4 from /proc/net/fib_trie is complex; read /sys/class/net/<if>/address
        // is already done. For IPv4 we parse /proc/net/if_inet6 later or skip.
        // Simple approach: not available from sysfs alone without ip command.
        try w.writeAll("}");
    }

    try w.writeAll("],\"ipv4\":");

    // Parse /proc/net/fib_trie is complex; let's read /proc/net/route for default gw.
    const default_gw = readDefaultGateway() catch null;
    if (default_gw) |gw| {
        try std.fmt.format(w, "{{\"default_gateway\":\"{d}.{d}.{d}.{d}\"}}", .{
            gw[0], gw[1], gw[2], gw[3],
        });
    } else {
        try w.writeAll("{\"default_gateway\":null}");
    }

    try w.writeAll("}");

    const body = out[0..stream.pos];
    try req.respond(body, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

fn readSysFile(alloc: std.mem.Allocator, base: []const u8, iface: []const u8, attr: []const u8) ![]const u8 {
    var path_buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}/{s}", .{ base, iface, attr });
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var read_buf: [256]u8 = undefined;
    const n = try file.read(&read_buf);
    const raw = read_buf[0..n];
    const trimmed = std.mem.trimRight(u8, raw, "\n\r ");
    return alloc.dupe(u8, trimmed);
}

fn readDefaultGateway() ![4]u8 {
    const file = std.fs.openFileAbsolute("/proc/net/route", .{}) catch return error.NoRoute;
    defer file.close();

    var line_buf: [512]u8 = undefined;
    var reader = std.io.bufferedReader(file.reader());
    var rd = reader.reader();

    // Skip header line
    _ = rd.readUntilDelimiter(&line_buf, '\n') catch return error.NoRoute;

    while (rd.readUntilDelimiter(&line_buf, '\n')) |line| {
        // Fields: Iface Destination Gateway Flags RefCnt Use Metric Mask MTU Window IRTT
        var col: usize = 0;
        var dest: []const u8 = "";
        var gateway: []const u8 = "";
        var tok_it = std.mem.tokenizeScalar(u8, line, '\t');
        while (tok_it.next()) |field| {
            if (col == 1) dest = field;
            if (col == 2) gateway = field;
            col += 1;
            if (col > 2) break;
        }
        // Default route: destination = 00000000
        if (std.mem.eql(u8, dest, "00000000") and gateway.len == 8) {
            const gw_int = std.fmt.parseInt(u32, gateway, 16) catch continue;
            return .{
                @truncate(gw_int),
                @truncate(gw_int >> 8),
                @truncate(gw_int >> 16),
                @truncate(gw_int >> 24),
            };
        }
    } else |_| {}

    return error.NoRoute;
}
