const std = @import("std");

const Io = std.Io;
const http = std.http;
const net = std.Io.net;

const max_path_len = 1024;
const max_headers = 20;

const cache_html = "public, max-age=0, must-revalidate";
const cache_immutable = "public, max-age=31536000, immutable";
const cache_no_store = "no-store";

const csp =
    "default-src 'self'; base-uri 'none'; font-src 'self'; img-src 'self' data:; " ++
    "script-src 'self' https://plausible.plosca.ru; style-src 'self'; " ++
    "connect-src 'self' https://plausible.plosca.ru; object-src 'none'; " ++
    "frame-ancestors 'none'; form-action 'self'; manifest-src 'self'; upgrade-insecure-requests";

const Config = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 9327,
    static_root: []const u8 = "static",
    hsts_max_age: ?u64 = null,
};

const AppState = struct {
    static_dir: Io.Dir,
    hsts_max_age: ?u64,
};

const Encoding = enum {
    identity,
    br,
    gzip,

    fn headerValue(self: Encoding) ?[]const u8 {
        return switch (self) {
            .identity => null,
            .br => "br",
            .gzip => "gzip",
        };
    }

    fn suffix(self: Encoding) []const u8 {
        return switch (self) {
            .identity => "",
            .br => ".br",
            .gzip => ".gz",
        };
    }
};

const EncodingPreference = struct {
    br_q: f32 = 0.0,
    gzip_q: f32 = 0.0,
};

const ResolvedFile = struct {
    file: Io.File,
    stat: Io.File.Stat,
    logical_path: []const u8,
    encoding: Encoding,
};

const ResolveScratch = struct {
    html: [max_path_len + 5]u8 = undefined,
    index: [max_path_len + 11]u8 = undefined,
    variant: [max_path_len + 4]u8 = undefined,
};

const HeaderBuilder = struct {
    items: [max_headers]http.Header = undefined,
    len: usize = 0,

    fn add(self: *HeaderBuilder, name: []const u8, value: []const u8) void {
        std.debug.assert(self.len < self.items.len);
        self.items[self.len] = .{ .name = name, .value = value };
        self.len += 1;
    }

    fn slice(self: *const HeaderBuilder) []const http.Header {
        return self.items[0..self.len];
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const config = try parseConfig(args, init.minimal.environ, init.gpa);

    var static_dir = try Io.Dir.cwd().openDir(init.io, config.static_root, .{});
    defer static_dir.close(init.io);

    var address = try net.IpAddress.parse(config.host, config.port);
    var tcp_server = try address.listen(init.io, .{ .reuse_address = true });
    defer tcp_server.deinit(init.io);

    const state: AppState = .{
        .static_dir = static_dir,
        .hsts_max_age = config.hsts_max_age,
    };

    std.log.info("serving {s} at http://{s}:{d}/", .{
        config.static_root,
        config.host,
        config.port,
    });

    var group: Io.Group = .init;
    defer group.cancel(init.io);

    while (true) {
        var stream = tcp_server.accept(init.io) catch |err| switch (err) {
            error.Canceled => return,
            else => |e| {
                std.log.err("accept failed: {s}", .{@errorName(e)});
                continue;
            },
        };

        group.concurrent(init.io, handleConnection, .{ init.io, stream, state }) catch |err| {
            std.log.err("could not start connection task: {s}", .{@errorName(err)});
            stream.close(init.io);
            continue;
        };
    }
}

fn parseConfig(args: []const [:0]const u8, environ: std.process.Environ, allocator: std.mem.Allocator) !Config {
    var config = Config{};
    if (std.process.Environ.getAlloc(environ, allocator, "PORT")) |value| {
        defer allocator.free(value);
        config.port = std.fmt.parseUnsigned(u16, value, 10) catch config.port;
    } else |_| {}

    if (args.len < 2 or !std.mem.eql(u8, args[1], "serve")) {
        usageAndExit();
    }

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--host")) {
            i += 1;
            if (i >= args.len) usageAndExit();
            config.host = args[i];
        } else if (std.mem.eql(u8, arg, "--port")) {
            i += 1;
            if (i >= args.len) usageAndExit();
            config.port = std.fmt.parseUnsigned(u16, args[i], 10) catch usageAndExit();
        } else if (std.mem.eql(u8, arg, "--static-root")) {
            i += 1;
            if (i >= args.len) usageAndExit();
            config.static_root = args[i];
        } else if (std.mem.eql(u8, arg, "--hsts-max-age")) {
            i += 1;
            if (i >= args.len) usageAndExit();
            config.hsts_max_age = std.fmt.parseUnsigned(u64, args[i], 10) catch usageAndExit();
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            usageAndExit();
        } else {
            usageAndExit();
        }
    }

    return config;
}

fn usageAndExit() noreturn {
    std.debug.print(
        \\Usage:
        \\  webapp serve [--host 0.0.0.0] [--port 9327] [--static-root static] [--hsts-max-age seconds]
        \\
    , .{});
    std.process.exit(2);
}

fn handleConnection(io: Io, stream_arg: net.Stream, state: AppState) Io.Cancelable!void {
    var stream = stream_arg;
    defer stream.close(io);

    var recv_buffer: [8192]u8 = undefined;
    var send_buffer: [8192]u8 = undefined;
    var reader = stream.reader(io, &recv_buffer);
    var writer = stream.writer(io, &send_buffer);
    var server: http.Server = .init(&reader.interface, &writer.interface);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => |e| {
                std.log.warn("bad request: {s}", .{@errorName(e)});
                return;
            },
        };
        serveRequest(&request, io, state) catch |err| {
            std.log.warn("request failed: {s}", .{@errorName(err)});
            respondText(&request, state, .internal_server_error, "internal server error", false) catch {};
            return;
        };
    }
}

fn serveRequest(request: *http.Server.Request, io: Io, state: AppState) !void {
    switch (request.head.method) {
        .GET, .HEAD => {},
        else => return respondMethodNotAllowed(request, state),
    }

    var path_buf: [max_path_len]u8 = undefined;
    const normalized = normalizeRequestPath(request.head.target, &path_buf) catch |err| switch (err) {
        error.PathTooLong => return respondText(request, state, .uri_too_long, "uri too long", false),
    };

    const rel_path = normalized orelse return respondNotFound(request, io, state);
    var scratch: ResolveScratch = .{};
    if (try resolveFile(io, state, rel_path, request, &scratch)) |resolved| {
        return respondStaticFile(request, io, state, .ok, resolved);
    }

    return respondNotFound(request, io, state);
}

fn respondNotFound(request: *http.Server.Request, io: Io, state: AppState) !void {
    var scratch: ResolveScratch = .{};
    if (try openBestVariant(io, state, "404.html", request, &scratch.variant)) |resolved| {
        return respondStaticFile(request, io, state, .not_found, resolved);
    }
    return respondText(request, state, .not_found, "not found", false);
}

fn respondStaticFile(
    request: *http.Server.Request,
    io: Io,
    state: AppState,
    status: http.Status,
    resolved: ResolvedFile,
) !void {
    var file = resolved.file;
    defer file.close(io);

    const cache_control = if (status == .not_found) cache_no_store else cacheControlFor(resolved.logical_path);
    var etag_buf: [34]u8 = undefined;
    const etag = makeEtag(resolved.logical_path, resolved.encoding, resolved.stat.size, resolved.stat.mtime.nanoseconds, &etag_buf);

    var last_modified_buf: [29]u8 = undefined;
    const mtime_seconds = timestampSeconds(resolved.stat.mtime);
    const last_modified = formatHttpDate(mtime_seconds, &last_modified_buf) catch "Thu, 01 Jan 1970 00:00:00 GMT";

    if (status == .ok and requestIsFresh(request, etag, mtime_seconds)) {
        return respondNotModified(request, state, cache_control, etag, last_modified, resolved.encoding);
    }

    var headers: HeaderBuilder = .{};
    var hsts_buf: [64]u8 = undefined;
    headers.add("content-type", contentTypeFor(resolved.logical_path));
    headers.add("cache-control", cache_control);
    headers.add("etag", etag);
    headers.add("last-modified", last_modified);
    if (resolved.encoding.headerValue()) |encoding| {
        headers.add("content-encoding", encoding);
        headers.add("vary", "Accept-Encoding");
    }
    try addSecurityHeaders(&headers, state.hsts_max_age, &hsts_buf);

    if (request.head.method == .HEAD) {
        var content_length_buf: [32]u8 = undefined;
        headers.add("content-length", try std.fmt.bufPrint(&content_length_buf, "{d}", .{resolved.stat.size}));
        return request.respond("", .{
            .status = status,
            .keep_alive = false,
            .transfer_encoding = .none,
            .extra_headers = headers.slice(),
        });
    }

    var stream_buffer: [8192]u8 = undefined;
    var body = try request.respondStreaming(&stream_buffer, .{
        .content_length = resolved.stat.size,
        .respond_options = .{
            .status = status,
            .extra_headers = headers.slice(),
        },
    });

    var file_reader: Io.File.Reader = .initSize(file, io, &.{}, resolved.stat.size);
    _ = try body.writer.sendFileAll(&file_reader, .limited64(resolved.stat.size));
    try body.end();
}

fn respondNotModified(
    request: *http.Server.Request,
    state: AppState,
    cache_control: []const u8,
    etag: []const u8,
    last_modified: []const u8,
    encoding: Encoding,
) !void {
    var headers: HeaderBuilder = .{};
    var hsts_buf: [64]u8 = undefined;
    headers.add("cache-control", cache_control);
    headers.add("etag", etag);
    headers.add("last-modified", last_modified);
    if (encoding.headerValue()) |encoding_value| {
        headers.add("content-encoding", encoding_value);
        headers.add("vary", "Accept-Encoding");
    }
    try addSecurityHeaders(&headers, state.hsts_max_age, &hsts_buf);
    try request.respond("", .{
        .status = .not_modified,
        .extra_headers = headers.slice(),
    });
}

fn respondText(request: *http.Server.Request, state: AppState, status: http.Status, body: []const u8, close: bool) !void {
    var headers: HeaderBuilder = .{};
    var hsts_buf: [64]u8 = undefined;
    headers.add("content-type", "text/plain; charset=utf-8");
    headers.add("cache-control", cache_no_store);
    try addSecurityHeaders(&headers, state.hsts_max_age, &hsts_buf);
    try request.respond(body, .{
        .status = status,
        .keep_alive = !close,
        .extra_headers = headers.slice(),
    });
}

fn respondMethodNotAllowed(request: *http.Server.Request, state: AppState) !void {
    var headers: HeaderBuilder = .{};
    var hsts_buf: [64]u8 = undefined;
    headers.add("content-type", "text/plain; charset=utf-8");
    headers.add("allow", "GET, HEAD");
    headers.add("cache-control", cache_no_store);
    try addSecurityHeaders(&headers, state.hsts_max_age, &hsts_buf);
    try request.respond("method not allowed", .{
        .status = .method_not_allowed,
        .keep_alive = false,
        .extra_headers = headers.slice(),
    });
}

fn addSecurityHeaders(headers: *HeaderBuilder, hsts_max_age: ?u64, hsts_buf: *[64]u8) !void {
    headers.add("content-security-policy", csp);
    headers.add("x-frame-options", "DENY");
    headers.add("x-content-type-options", "nosniff");
    headers.add("referrer-policy", "strict-origin-when-cross-origin");
    headers.add("permissions-policy", "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()");
    headers.add("cross-origin-resource-policy", "same-origin");
    if (hsts_max_age) |max_age| {
        headers.add("strict-transport-security", try std.fmt.bufPrint(hsts_buf, "max-age={d}; includeSubDomains", .{max_age}));
    }
}

fn resolveFile(
    io: Io,
    state: AppState,
    rel_path: []const u8,
    request: *const http.Server.Request,
    scratch: *ResolveScratch,
) !?ResolvedFile {
    if (try openBestVariant(io, state, rel_path, request, &scratch.variant)) |resolved| return resolved;

    const basename = std.fs.path.basename(rel_path);
    if (std.mem.indexOfScalar(u8, basename, '.') != null) return null;

    const html_candidate = std.fmt.bufPrint(&scratch.html, "{s}.html", .{rel_path}) catch return null;
    if (try openBestVariant(io, state, html_candidate, request, &scratch.variant)) |resolved| return resolved;

    const index_candidate = std.fmt.bufPrint(&scratch.index, "{s}/index.html", .{rel_path}) catch return null;
    if (try openBestVariant(io, state, index_candidate, request, &scratch.variant)) |resolved| return resolved;

    return null;
}

fn openBestVariant(
    io: Io,
    state: AppState,
    logical_path: []const u8,
    request: *const http.Server.Request,
    variant_buf: *[max_path_len + 4]u8,
) !?ResolvedFile {
    const pref = preferredEncoding(request);

    if (pref.br_q >= pref.gzip_q) {
        if (pref.br_q > 0) if (openVariant(io, state, logical_path, .br, variant_buf)) |resolved| return resolved;
        if (pref.gzip_q > 0) if (openVariant(io, state, logical_path, .gzip, variant_buf)) |resolved| return resolved;
    } else {
        if (pref.gzip_q > 0) if (openVariant(io, state, logical_path, .gzip, variant_buf)) |resolved| return resolved;
        if (pref.br_q > 0) if (openVariant(io, state, logical_path, .br, variant_buf)) |resolved| return resolved;
    }

    return openVariant(io, state, logical_path, .identity, variant_buf);
}

fn openVariant(
    io: Io,
    state: AppState,
    logical_path: []const u8,
    encoding: Encoding,
    variant_buf: *[max_path_len + 4]u8,
) ?ResolvedFile {
    const open_path = if (encoding == .identity)
        logical_path
    else
        std.fmt.bufPrint(variant_buf, "{s}{s}", .{ logical_path, encoding.suffix() }) catch return null;

    var file = state.static_dir.openFile(io, open_path, .{ .allow_directory = false }) catch return null;

    const stat = file.stat(io) catch {
        file.close(io);
        return null;
    };
    if (stat.kind != .file) {
        file.close(io);
        return null;
    }

    return .{
        .file = file,
        .stat = stat,
        .logical_path = logical_path,
        .encoding = encoding,
    };
}

const NormalizeError = error{PathTooLong};

fn normalizeRequestPath(target: []const u8, out: *[max_path_len]u8) NormalizeError!?[]const u8 {
    const path_only = stripQueryAndFragment(target);
    const stripped = std.mem.trimStart(u8, path_only, "/");

    var len: usize = 0;
    var parts = std.mem.splitScalar(u8, stripped, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) return null;
        if (std.mem.indexOfScalar(u8, part, '\\') != null) return null;

        if (len != 0) {
            if (len >= out.len) return error.PathTooLong;
            out[len] = '/';
            len += 1;
        }
        if (part.len > out.len - len) return error.PathTooLong;
        @memcpy(out[len..][0..part.len], part);
        len += part.len;
    }

    if (len == 0) {
        const index = "index.html";
        @memcpy(out[0..index.len], index);
        len = index.len;
    }

    return out[0..len];
}

fn stripQueryAndFragment(target: []const u8) []const u8 {
    var end = target.len;
    if (std.mem.indexOfScalar(u8, target, '?')) |index| end = @min(end, index);
    if (std.mem.indexOfScalar(u8, target, '#')) |index| end = @min(end, index);
    return target[0..end];
}

fn contentTypeFor(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".html")) return "text/html; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".css")) return "text/css; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".js")) return "application/javascript; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".json")) return "application/json; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".webmanifest")) return "application/manifest+json; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".xml")) return "application/xml; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".txt")) return "text/plain; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".pdf")) return "application/pdf";
    if (std.ascii.eqlIgnoreCase(ext, ".png")) return "image/png";
    if (std.ascii.eqlIgnoreCase(ext, ".jpg") or std.ascii.eqlIgnoreCase(ext, ".jpeg")) return "image/jpeg";
    if (std.ascii.eqlIgnoreCase(ext, ".gif")) return "image/gif";
    if (std.ascii.eqlIgnoreCase(ext, ".svg")) return "image/svg+xml; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(ext, ".ico")) return "image/x-icon";
    if (std.ascii.eqlIgnoreCase(ext, ".woff")) return "font/woff";
    if (std.ascii.eqlIgnoreCase(ext, ".woff2")) return "font/woff2";
    return "application/octet-stream";
}

fn cacheControlFor(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".html")) return cache_html;
    if (std.ascii.eqlIgnoreCase(ext, ".css")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".webmanifest")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".pdf")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".png")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".jpg") or std.ascii.eqlIgnoreCase(ext, ".jpeg")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".gif")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".svg")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".ico")) return cache_immutable;
    if (std.ascii.eqlIgnoreCase(ext, ".woff") or std.ascii.eqlIgnoreCase(ext, ".woff2")) return cache_immutable;
    return cache_html;
}

fn requestHeader(request: *const http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return header.value;
    }
    return null;
}

fn preferredEncoding(request: *const http.Server.Request) EncodingPreference {
    const raw = requestHeader(request, "accept-encoding") orelse return .{};
    return parseAcceptEncoding(raw);
}

fn parseAcceptEncoding(raw: []const u8) EncodingPreference {
    var pref = EncodingPreference{};
    var br_seen = false;
    var gzip_seen = false;
    var wildcard: ?f32 = null;

    var items = std.mem.splitScalar(u8, raw, ',');
    while (items.next()) |item_raw| {
        const item = std.mem.trim(u8, item_raw, " \t");
        if (item.len == 0) continue;
        var parts = std.mem.splitScalar(u8, item, ';');
        const coding = std.mem.trim(u8, parts.next().?, " \t");
        var q: f32 = 1.0;

        while (parts.next()) |param_raw| {
            const param = std.mem.trim(u8, param_raw, " \t");
            if (param.len >= 2 and std.ascii.eqlIgnoreCase(param[0..2], "q=")) {
                q = std.fmt.parseFloat(f32, param[2..]) catch 0.0;
            }
        }

        if (std.ascii.eqlIgnoreCase(coding, "br")) {
            pref.br_q = q;
            br_seen = true;
        } else if (std.ascii.eqlIgnoreCase(coding, "gzip")) {
            pref.gzip_q = q;
            gzip_seen = true;
        } else if (std.mem.eql(u8, coding, "*")) {
            wildcard = q;
        }
    }

    if (!br_seen) pref.br_q = wildcard orelse 0.0;
    if (!gzip_seen) pref.gzip_q = wildcard orelse 0.0;
    return pref;
}

fn requestIsFresh(request: *const http.Server.Request, etag: []const u8, mtime_seconds: u64) bool {
    if (requestHeader(request, "if-none-match")) |value| {
        return matchesIfNoneMatch(value, etag);
    }
    if (requestHeader(request, "if-modified-since")) |value| {
        if (parseHttpDate(value)) |since| {
            return mtime_seconds <= since;
        }
    }
    return false;
}

fn matchesIfNoneMatch(value: []const u8, etag: []const u8) bool {
    var items = std.mem.splitScalar(u8, value, ',');
    while (items.next()) |item| {
        const candidate = std.mem.trim(u8, item, " \t");
        if (std.mem.eql(u8, candidate, "*") or std.mem.eql(u8, candidate, etag)) return true;
    }
    return false;
}

fn makeEtag(path: []const u8, encoding: Encoding, size: u64, mtime_ns: i96, out: *[34]u8) []const u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(path);
    hash.update(encoding.suffix());
    hash.update(std.mem.asBytes(&size));
    hash.update(std.mem.asBytes(&mtime_ns));
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);

    const hex = "0123456789abcdef";
    out[0] = '"';
    for (digest[0..16], 0..) |byte, index| {
        out[1 + index * 2] = hex[byte >> 4];
        out[2 + index * 2] = hex[byte & 0x0f];
    }
    out[33] = '"';
    return out[0..34];
}

fn timestampSeconds(timestamp: Io.Timestamp) u64 {
    if (timestamp.nanoseconds <= 0) return 0;
    return @intCast(@divTrunc(timestamp.nanoseconds, @as(i96, std.time.ns_per_s)));
}

fn formatHttpDate(seconds: u64, out: *[29]u8) ![]const u8 {
    const weekdays = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const weekday_index: usize = @intCast((epoch_day.day + 4) % 7);
    const month_index: usize = @intFromEnum(month_day.month) - 1;

    return std.fmt.bufPrint(out, "{s}, {d:0>2} {s} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2} GMT", .{
        weekdays[weekday_index],
        month_day.day_index + 1,
        months[month_index],
        year_day.year,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

fn parseHttpDate(value_raw: []const u8) ?u64 {
    const value = std.mem.trim(u8, value_raw, " \t");
    if (value.len != 29) return null;
    if (value[3] != ',' or value[4] != ' ' or value[7] != ' ' or value[11] != ' ' or value[16] != ' ' or value[19] != ':' or value[22] != ':' or value[25] != ' ') return null;
    if (!std.mem.eql(u8, value[26..29], "GMT")) return null;

    const day = std.fmt.parseUnsigned(u8, value[5..7], 10) catch return null;
    const month = monthNumber(value[8..11]) orelse return null;
    const year = std.fmt.parseUnsigned(u16, value[12..16], 10) catch return null;
    const hour = std.fmt.parseUnsigned(u8, value[17..19], 10) catch return null;
    const minute = std.fmt.parseUnsigned(u8, value[20..22], 10) catch return null;
    const second = std.fmt.parseUnsigned(u8, value[23..25], 10) catch return null;
    if (day == 0 or day > 31 or hour > 23 or minute > 59 or second > 59) return null;

    return dateToSeconds(.{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    });
}

const HttpDate = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

fn dateToSeconds(date: HttpDate) u64 {
    var seconds: u64 = 0;
    var year: u16 = std.time.epoch.epoch_year;
    while (year < date.year) : (year += 1) {
        seconds += @as(u64, std.time.epoch.getDaysInYear(year)) * std.time.epoch.secs_per_day;
    }
    var month: u4 = 1;
    while (month < date.month) : (month += 1) {
        seconds += @as(u64, std.time.epoch.getDaysInMonth(date.year, @enumFromInt(month))) * std.time.epoch.secs_per_day;
    }
    seconds += @as(u64, date.day - 1) * std.time.epoch.secs_per_day;
    seconds += @as(u64, date.hour) * 60 * 60;
    seconds += @as(u64, date.minute) * 60;
    seconds += date.second;
    return seconds;
}

fn monthNumber(month: []const u8) ?u8 {
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    for (months, 1..) |candidate, index| {
        if (std.mem.eql(u8, month, candidate)) return @intCast(index);
    }
    return null;
}

test "normalize root, extensionless path, and query stripping" {
    var buf: [max_path_len]u8 = undefined;
    try std.testing.expectEqualStrings("index.html", (try normalizeRequestPath("/", &buf)).?);
    try std.testing.expectEqualStrings("about", (try normalizeRequestPath("/about?x=1", &buf)).?);
}

test "normalize rejects traversal and overly long paths" {
    var buf: [max_path_len]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), try normalizeRequestPath("/../etc/passwd", &buf));
    try std.testing.expectEqual(@as(?[]const u8, null), try normalizeRequestPath("/foo/../bar", &buf));

    var long_target: [max_path_len + 2]u8 = undefined;
    @memset(&long_target, 'a');
    long_target[0] = '/';
    try std.testing.expectError(error.PathTooLong, normalizeRequestPath(&long_target, &buf));
}

test "content type and cache policy mapping" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", contentTypeFor("index.html"));
    try std.testing.expectEqualStrings("font/woff2", contentTypeFor("font.woff2"));
    try std.testing.expectEqualStrings("application/octet-stream", contentTypeFor("file.bin"));
    try std.testing.expectEqualStrings(cache_html, cacheControlFor("index.html"));
    try std.testing.expectEqualStrings(cache_immutable, cacheControlFor("style.css"));
    try std.testing.expectEqualStrings(cache_immutable, cacheControlFor("resume.pdf"));
}

test "accept encoding selection" {
    try std.testing.expectEqual(@as(f32, 1.0), parseAcceptEncoding("gzip, br").br_q);
    try std.testing.expectEqual(@as(f32, 0.5), parseAcceptEncoding("br;q=0.5, gzip;q=1").br_q);
    try std.testing.expectEqual(@as(f32, 0.7), parseAcceptEncoding("*;q=0.7").gzip_q);
    try std.testing.expectEqual(@as(f32, 0.0), parseAcceptEncoding("br;q=0, gzip;q=1").br_q);
}

test "conditional request helpers" {
    var etag_buf: [34]u8 = undefined;
    const etag = makeEtag("style.css", .identity, 123, 456, &etag_buf);
    var if_none_match_buf: [128]u8 = undefined;
    const if_none_match = try std.fmt.bufPrint(&if_none_match_buf, "\"nope\", \"not-it\", {s}", .{etag});
    try std.testing.expect(matchesIfNoneMatch(if_none_match, etag));
    try std.testing.expect(matchesIfNoneMatch("*", etag));

    var date_buf: [29]u8 = undefined;
    const formatted = try formatHttpDate(0, &date_buf);
    try std.testing.expectEqualStrings("Thu, 01 Jan 1970 00:00:00 GMT", formatted);
    try std.testing.expectEqual(@as(?u64, 0), parseHttpDate(formatted));
}

test "known local route references resolve to static files" {
    const routes = [_][]const u8{
        "/",
        "/about",
        "/hello_world",
        "/prose",
        "/style.css",
        "/PH1InQe0rvp_yN3TzIuyyQ.woff2",
        "/6xKtdSZaM9iE8KbpRA_hK1QN.woff2",
        "/site.webmanifest",
        "/resume.pdf",
        "/apple-touch-icon.png",
        "/favicon-32x32.png",
        "/favicon-16x16.png",
    };

    for (routes) |route| {
        try std.testing.expect(try routeExistsForTest(route));
    }
}

fn routeExistsForTest(route: []const u8) !bool {
    var normalized_buf: [max_path_len]u8 = undefined;
    const normalized = (try normalizeRequestPath(route, &normalized_buf)) orelse return false;
    if (try staticFileExistsForTest(normalized)) return true;

    const basename = std.fs.path.basename(normalized);
    if (std.mem.indexOfScalar(u8, basename, '.') != null) return false;

    var html_buf: [max_path_len + 5]u8 = undefined;
    const html_candidate = try std.fmt.bufPrint(&html_buf, "{s}.html", .{normalized});
    if (try staticFileExistsForTest(html_candidate)) return true;

    var index_buf: [max_path_len + 11]u8 = undefined;
    const index_candidate = try std.fmt.bufPrint(&index_buf, "{s}/index.html", .{normalized});
    return staticFileExistsForTest(index_candidate);
}

fn staticFileExistsForTest(rel_path: []const u8) !bool {
    var full_path_buf: [max_path_len + 7]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "static/{s}", .{rel_path});
    var file = Io.Dir.cwd().openFile(std.testing.io, full_path, .{ .allow_directory = false }) catch return false;
    file.close(std.testing.io);
    return true;
}
