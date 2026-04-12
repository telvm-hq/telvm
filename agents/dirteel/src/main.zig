//! dirteel — static CONNECT egress probe + closed-image manifest helper for telvm.
const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const version = "0.1.0";

const usage_main =
    \\dirteel — closed-agent egress probe + image profile manifest (telvm)
    \\
    \\Usage:
    \\  dirteel egress-probe [OPTIONS]
    \\  dirteel manifest <profiles.json> [--quiet-sha-only]
    \\  dirteel --version
    \\  dirteel --help
    \\
;

const usage_egress =
    \\dirteel egress-probe — raw HTTP CONNECT through a telvm egress listener (same contract as curl --proxy).
    \\
    \\Options:
    \\  --proxy-host <HOST>       Default: companion
    \\  --proxy-port <PORT>       Required (e.g. 4001 for Claude workload)
    \\  --https-url <URL>         Vendor HTTPS URL (host + optional :port; default port 443)
    \\  --connect-timeout-ms <N>  TCP connect + first byte timeout (default: 45000)
    \\
    \\Exit 0 only if proxy returns HTTP/1.1 200 Connection Established.
    \\JSON result is printed to stdout; one human line to stderr.
    \\
;

const Profile = struct {
    compose_service: []const u8,
    proxy_port: u16,
    vendor_url: []const u8,
    product: []const u8,
    ghcr_package: ?[]const u8 = null,
};

fn printUsageMain() !void {
    try std.io.getStdErr().writeAll(usage_main);
}

fn printUsageEgress() !void {
    try std.io.getStdErr().writeAll(usage_egress);
}

fn die(comptime fmt: []const u8, args: anytype) noreturn {
    std.io.getStdErr().writer().print(fmt ++ "\n", args) catch {};
    std.process.exit(2);
}

fn parseU16(s: []const u8) u16 {
    return std.fmt.parseInt(u16, s, 10) catch die("error: invalid u16: {s}", .{s});
}

fn parseU32(s: []const u8) u32 {
    return std.fmt.parseInt(u32, s, 10) catch die("error: invalid u32: {s}", .{s});
}

/// Authority after scheme: host or host:port, no path.
fn parseVendorUrl(url: []const u8) struct { host: []const u8, port: u16 } {
    var rest = url;
    if (std.mem.startsWith(u8, rest, "https://")) {
        rest = rest["https://".len..];
    } else if (std.mem.startsWith(u8, rest, "http://")) {
        rest = rest["http://".len..];
    } else {
        die("error: --https-url must start with https:// or http://", .{});
    }

    const end_authority = for (rest, 0..) |c, i| {
        if (c == '/' or c == '?' or c == '#') break i;
    } else rest.len;

    const authority = rest[0..end_authority];
    if (authority.len == 0)
        die("error: empty host in URL", .{});

    if (std.mem.lastIndexOfScalar(u8, authority, ':')) |colon| {
        // IPv6 [::1]:443 — bracketed host
        if (authority[0] == '[') {
            const close = std.mem.indexOfScalar(u8, authority, ']') orelse
                die("error: malformed IPv6 in URL", .{});
            if (colon < close)
                die("error: unexpected ':' inside IPv6 bracket", .{});
            if (colon + 1 >= authority.len)
                die("error: missing port after ':'", .{});
            const host = authority[0 .. close + 1];
            const port_s = authority[colon + 1 ..];
            return .{ .host = host, .port = parseU16(port_s) };
        }
        const host = authority[0..colon];
        const port_s = authority[colon + 1..];
        if (host.len == 0 or port_s.len == 0)
            die("error: malformed host:port in URL", .{});
        return .{ .host = host, .port = parseU16(port_s) };
    }

    return .{ .host = authority, .port = 443 };
}

fn setRecvTimeout(fd: posix.fd_t, timeout_ms: u32) !void {
    if (builtin.os.tag != .linux) return;
    const sec: isize = @intCast(timeout_ms / 1000);
    const usec: isize = @intCast((timeout_ms % 1000) * 1000);
    const tv = posix.timeval{ .tv_sec = sec, .tv_usec = usec };
    try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&tv));
}

fn setSendTimeout(fd: posix.fd_t, timeout_ms: u32) !void {
    if (builtin.os.tag != .linux) return;
    const sec: isize = @intCast(timeout_ms / 1000);
    const usec: isize = @intCast((timeout_ms % 1000) * 1000);
    const tv = posix.timeval{ .tv_sec = sec, .tv_usec = usec };
    try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.SNDTIMEO, std.mem.asBytes(&tv));
}

const ProbeOut = struct {
    ok: bool,
    status_line: ?[]const u8 = null,
    body_preview: ?[]const u8 = null,
    err: ?[]const u8 = null,
};

fn runEgressProbe(alloc: std.mem.Allocator, argv: *std.process.ArgIterator) !u8 {
    var proxy_host: []const u8 = "companion";
    var proxy_port: ?u16 = null;
    var https_url: ?[]const u8 = null;
    var timeout_ms: u32 = 45_000;

    while (argv.next()) |arg| {
        if (std.mem.eql(u8, arg, "--proxy-host")) {
            proxy_host = argv.next() orelse die("error: --proxy-host needs a value", .{});
        } else if (std.mem.eql(u8, arg, "--proxy-port")) {
            const v = argv.next() orelse die("error: --proxy-port needs a value", .{});
            proxy_port = parseU16(v);
        } else if (std.mem.eql(u8, arg, "--https-url")) {
            https_url = argv.next() orelse die("error: --https-url needs a value", .{});
        } else if (std.mem.eql(u8, arg, "--connect-timeout-ms")) {
            const v = argv.next() orelse die("error: --connect-timeout-ms needs a value", .{});
            timeout_ms = parseU32(v);
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printUsageEgress();
            return 0;
        } else {
            die("error: unknown flag: {s}", .{arg});
        }
    }

    const port = proxy_port orelse die("error: --proxy-port is required", .{});
    const vurl = https_url orelse die("error: --https-url is required", .{});

    const hp = parseVendorUrl(vurl);
    const host = hp.host;
    const target_port = hp.port;

    const list = try std.net.getAddressList(alloc, proxy_host, port);
    defer list.deinit();

    const stream = try std.net.tcpConnectToAddress(list.addrs[0]);
    defer stream.close();

    try setSendTimeout(stream.handle, timeout_ms);
    try setRecvTimeout(stream.handle, timeout_ms);

    var req_buf: [512]u8 = undefined;
    // Bracket IPv6 host in CONNECT target without double brackets
    const target = try std.fmt.bufPrint(
        &req_buf,
        "{s}:{d}",
        .{ host, target_port },
    );

    var hdr_buf: [1024]u8 = undefined;
    const request = try std.fmt.bufPrint(
        &hdr_buf,
        "CONNECT {s} HTTP/1.1\r\nHost: {s}\r\nProxy-Connection: keep-alive\r\n\r\n",
        .{ target, target },
    );

    try stream.writeAll(request);

    var read_buf: std.ArrayListUnmanaged(u8) = .{};
    defer read_buf.deinit(alloc);
    try read_buf.ensureTotalCapacity(alloc, 4096);

    const max_total: usize = 64 * 1024;
    while (read_buf.items.len < max_total) {
        var chunk: [4096]u8 = undefined;
        const n = stream.read(&chunk) catch |e| {
            var ebuf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&ebuf, "read error: {s}", .{@errorName(e)}) catch "read error";
            const out = ProbeOut{ .ok = false, .err = msg };
            try std.json.stringify(out, .{}, std.io.getStdOut().writer());
            try std.io.getStdOut().writeAll("\n");
            try std.io.getStdErr().writeAll(msg);
            try std.io.getStdErr().writeAll("\n");
            return 1;
        };
        if (n == 0) break;
        try read_buf.appendSlice(alloc, chunk[0..n]);
        if (std.mem.indexOf(u8, read_buf.items, "\r\n\r\n")) |_| break;
        if (std.mem.indexOf(u8, read_buf.items, "\n\n")) |_| break;
    }

    const response = read_buf.items;
    const first_line_end = std.mem.indexOfScalar(u8, response, '\n') orelse response.len;
    const status_line = std.mem.trimRight(u8, response[0..first_line_end], "\r");

    var body_preview: ?[]const u8 = null;
    if (std.mem.indexOf(u8, response, "\r\n\r\n")) |idx| {
        const body_start = idx + 4;
        if (body_start < response.len) {
            const slice = response[body_start..];
            const maxp = @min(slice.len, 256);
            body_preview = slice[0..maxp];
        }
    }

    const ok = std.mem.startsWith(u8, status_line, "HTTP/1.1 200") or
        std.mem.startsWith(u8, status_line, "HTTP/1.0 200");

    const out = ProbeOut{
        .ok = ok,
        .status_line = status_line,
        .body_preview = body_preview,
        .err = if (ok) null else "CONNECT did not return 200",
    };

    var json_buf: std.ArrayListUnmanaged(u8) = .{};
    defer json_buf.deinit(alloc);
    try std.json.stringify(out, .{ .whitespace = .minified }, json_buf.writer(alloc));
    try json_buf.append(alloc, '\n');
    try std.io.getStdOut().writeAll(json_buf.items);

    if (ok) {
        try std.io.getStdErr().writer().print("dirteel: CONNECT ok ({s})\n", .{status_line});
        return 0;
    } else {
        try std.io.getStdErr().writer().print("dirteel: CONNECT failed ({s})\n", .{status_line});
        return 1;
    }
}

fn profileLess(_: void, a: Profile, b: Profile) bool {
    return std.mem.order(u8, a.compose_service, b.compose_service) == .lt;
}

fn runManifest(alloc: std.mem.Allocator, path: []const u8, quiet_sha_only: bool) !u8 {
    const raw = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 20);
    defer alloc.free(raw);

    const parsed = try std.json.parseFromSlice([]Profile, alloc, raw, .{});
    defer parsed.deinit();

    if (parsed.value.len == 0)
        die("error: profiles array is empty", .{});

    std.mem.sort(Profile, parsed.value, {}, profileLess);

    var canon = std.ArrayListUnmanaged(u8){};
    defer canon.deinit(alloc);
    try std.json.stringify(parsed.value, .{ .whitespace = .minified }, canon.writer(alloc));

    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(canon.items, &digest, .{});
    var hex_buf: [Sha256.digest_length * 2]u8 = undefined;
    _ = try std.fmt.bufPrint(&hex_buf, "{s}", .{std.fmt.fmtSliceHexLower(&digest)});
    const hex = hex_buf[0..];

    if (quiet_sha_only) {
        try std.io.getStdOut().writeAll(hex);
        try std.io.getStdOut().writeAll("\n");
        return 0;
    }

    const label_line = try std.fmt.allocPrint(
        alloc,
        "LABEL telvm.dirteel.profile_sha256=\"{s}\"",
        .{hex},
    );
    defer alloc.free(label_line);

    const ManifestOut = struct {
        profile_bundle_sha256: []const u8,
        profile_count: usize,
        suggested_label: []const u8,
        profiles_json_minified_len: usize,
    };

    const mo = ManifestOut{
        .profile_bundle_sha256 = hex,
        .profile_count = parsed.value.len,
        .suggested_label = label_line,
        .profiles_json_minified_len = canon.items.len,
    };

    try std.json.stringify(mo, .{ .whitespace = .minified }, std.io.getStdOut().writer());
    try std.io.getStdOut().writeAll("\n");
    return 0;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next() orelse return;

    const sub = args.next() orelse {
        try printUsageMain();
        std.process.exit(0);
    };

    if (std.mem.eql(u8, sub, "--version")) {
        try std.io.getStdOut().writer().print("dirteel {s}\n", .{version});
        return;
    }
    if (std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) {
        try printUsageMain();
        try printUsageEgress();
        return;
    }

    if (std.mem.eql(u8, sub, "egress-probe")) {
        const code = try runEgressProbe(alloc, &args);
        std.process.exit(code);
    }

    if (std.mem.eql(u8, sub, "manifest")) {
        const path = args.next() orelse {
            try std.io.getStdErr().writeAll("error: manifest requires <profiles.json>\n");
            std.process.exit(2);
        };
        var quiet = false;
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--quiet-sha-only")) {
                quiet = true;
            } else {
                die("error: unknown manifest flag: {s}", .{a});
            }
        }
        const code = try runManifest(alloc, path, quiet);
        std.process.exit(code);
    }

    try std.io.getStdErr().writer().print("error: unknown subcommand: {s}\n", .{sub});
    try printUsageMain();
    std.process.exit(2);
}
