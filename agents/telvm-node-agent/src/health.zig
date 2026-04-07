const std = @import("std");
const main_mod = @import("main.zig");

pub fn handle(req: *std.http.Server.Request) !void {
    var hostname_buf: [256]u8 = undefined;
    const hostname = getHostname(&hostname_buf) catch "unknown";

    const uptime_s = getUptimeSeconds() catch 0;
    const docker_ok = checkDockerSocket();

    var buf: [1024]u8 = undefined;
    const body = try std.fmt.bufPrint(&buf,
        \\{{"hostname":"{s}","uptime_s":{d},"agent_version":"{s}","docker_reachable":{s}}}
    , .{ hostname, uptime_s, main_mod.version, if (docker_ok) "true" else "false" });

    try req.respond(body, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

fn getHostname(buf: []u8) ![]const u8 {
    const file = std.fs.openFileAbsolute("/etc/hostname", .{}) catch return error.NoHostname;
    defer file.close();
    const n = try file.reader(&.{}).file_reader.interface.read(buf);
    return std.mem.trimRight(u8, buf[0..n], "\n\r ");
}

fn getUptimeSeconds() !u64 {
    const file = std.fs.openFileAbsolute("/proc/uptime", .{}) catch return error.NoUptime;
    defer file.close();
    var buf: [128]u8 = undefined;
    const n = try file.reader(&.{}).file_reader.interface.read(&buf);
    const content = buf[0..n];
    const space = std.mem.indexOf(u8, content, " ") orelse return error.ParseError;
    const uptime_str = content[0..space];
    const dot = std.mem.indexOf(u8, uptime_str, ".");
    const integer_part = if (dot) |d| uptime_str[0..d] else uptime_str;
    return std.fmt.parseInt(u64, integer_part, 10) catch error.ParseError;
}

fn checkDockerSocket() bool {
    const sock = std.net.connectUnixSocket("/var/run/docker.sock") catch return false;
    sock.close();
    return true;
}
