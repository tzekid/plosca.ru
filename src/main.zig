const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const http = std.http;
const net = std.Io.net;

const max_file_size = 64 * 1024 * 1024;

const Config = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 9327,
    static_root: []const u8 = "static",
};

const FilePayload = struct {
    path: []u8,
    body: []u8,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(arena);
    const config = try parseConfig(args, init.minimal.environ, gpa);

    var address = try net.IpAddress.parse(config.host, config.port);
    var tcp_server = try address.listen(init.io, .{ .reuse_address = true });
    defer tcp_server.deinit(init.io);

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

        group.concurrent(init.io, handleConnection, .{
            init.io,
            stream,
            config.static_root,
            gpa,
        }) catch |err| {
            std.log.err("could not start connection task: {s}", .{@errorName(err)});
            stream.close(init.io);
            continue;
        };
    }
}

fn parseConfig(args: []const [:0]const u8, environ: std.process.Environ, allocator: Allocator) !Config {
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
        \\  webapp serve [--host 0.0.0.0] [--port 9327] [--static-root static]
        \\
    , .{});
    std.process.exit(2);
}

fn handleConnection(io: Io, stream_arg: net.Stream, static_root: []const u8, allocator: Allocator) Io.Cancelable!void {
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
        serveRequest(&request, io, static_root, allocator) catch |err| {
            std.log.warn("request failed: {s}", .{@errorName(err)});
            respondText(&request, .internal_server_error, "internal server error") catch {};
            return;
        };
    }
}

fn serveRequest(request: *http.Server.Request, io: Io, static_root: []const u8, allocator: Allocator) !void {
    switch (request.head.method) {
        .GET, .HEAD => {},
        else => return respondMethodNotAllowed(request),
    }

    const normalized = try normalizeRequestPath(allocator, request.head.target);
    defer if (normalized) |path| allocator.free(path);

    const rel_path = normalized orelse return respondNotFound(request, io, static_root, allocator);
    if (try readResolvedFile(io, static_root, rel_path, allocator)) |payload| {
        defer allocator.free(payload.path);
        defer allocator.free(payload.body);
        return respondFile(request, .ok, payload.path, payload.body);
    }

    return respondNotFound(request, io, static_root, allocator);
}

fn respondNotFound(request: *http.Server.Request, io: Io, static_root: []const u8, allocator: Allocator) !void {
    if (try readOneFile(io, static_root, "404.html", allocator)) |payload| {
        defer allocator.free(payload.path);
        defer allocator.free(payload.body);
        return respondFile(request, .not_found, payload.path, payload.body);
    }
    return respondText(request, .not_found, "not found");
}

fn respondFile(request: *http.Server.Request, status: http.Status, path: []const u8, body: []const u8) !void {
    const headers = [_]http.Header{
        .{ .name = "content-type", .value = contentTypeFor(path) },
        .{ .name = "cache-control", .value = "public, max-age=0, must-revalidate" },
        .{ .name = "x-content-type-options", .value = "nosniff" },
    };
    try request.respond(body, .{
        .status = status,
        .extra_headers = &headers,
    });
}

fn respondText(request: *http.Server.Request, status: http.Status, body: []const u8) !void {
    const headers = [_]http.Header{
        .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
        .{ .name = "cache-control", .value = "no-store" },
        .{ .name = "x-content-type-options", .value = "nosniff" },
    };
    try request.respond(body, .{
        .status = status,
        .extra_headers = &headers,
    });
}

fn respondMethodNotAllowed(request: *http.Server.Request) !void {
    const headers = [_]http.Header{
        .{ .name = "content-type", .value = "text/plain; charset=utf-8" },
        .{ .name = "allow", .value = "GET, HEAD" },
        .{ .name = "cache-control", .value = "no-store" },
        .{ .name = "x-content-type-options", .value = "nosniff" },
    };
    try request.respond("method not allowed", .{
        .status = .method_not_allowed,
        .keep_alive = false,
        .extra_headers = &headers,
    });
}

fn readResolvedFile(io: Io, static_root: []const u8, rel_path: []const u8, allocator: Allocator) !?FilePayload {
    if (try readOneFile(io, static_root, rel_path, allocator)) |payload| return payload;

    const basename = std.fs.path.basename(rel_path);
    if (std.mem.indexOfScalar(u8, basename, '.') != null) return null;

    const html_candidate = try std.fmt.allocPrint(allocator, "{s}.html", .{rel_path});
    defer allocator.free(html_candidate);
    if (try readOneFile(io, static_root, html_candidate, allocator)) |payload| return payload;

    const index_candidate = try std.fs.path.join(allocator, &.{ rel_path, "index.html" });
    defer allocator.free(index_candidate);
    if (try readOneFile(io, static_root, index_candidate, allocator)) |payload| return payload;

    return null;
}

fn readOneFile(io: Io, static_root: []const u8, rel_path: []const u8, allocator: Allocator) !?FilePayload {
    const disk_path = try std.fs.path.join(allocator, &.{ static_root, rel_path });
    errdefer allocator.free(disk_path);

    const body = Io.Dir.cwd().readFileAlloc(
        io,
        disk_path,
        allocator,
        .limited(max_file_size),
    ) catch {
        allocator.free(disk_path);
        return null;
    };

    return .{
        .path = disk_path,
        .body = body,
    };
}

fn normalizeRequestPath(allocator: Allocator, target: []const u8) !?[]u8 {
    const path_only = stripQueryAndFragment(target);
    const stripped = std.mem.trimStart(u8, path_only, "/");

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var parts = std.mem.splitScalar(u8, stripped, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            out.deinit(allocator);
            return null;
        }
        if (std.mem.indexOfScalar(u8, part, '\\') != null) {
            out.deinit(allocator);
            return null;
        }

        if (out.items.len != 0) try out.append(allocator, '/');
        try out.appendSlice(allocator, part);
    }

    if (out.items.len == 0) try out.appendSlice(allocator, "index.html");
    return try out.toOwnedSlice(allocator);
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

test "normalize root and extensionless path" {
    const allocator = std.testing.allocator;
    const root = (try normalizeRequestPath(allocator, "/")).?;
    defer allocator.free(root);
    try std.testing.expectEqualStrings("index.html", root);

    const about = (try normalizeRequestPath(allocator, "/about?x=1")).?;
    defer allocator.free(about);
    try std.testing.expectEqualStrings("about", about);
}

test "normalize rejects traversal" {
    try std.testing.expectEqual(@as(?[]u8, null), try normalizeRequestPath(std.testing.allocator, "/../etc/passwd"));
    try std.testing.expectEqual(@as(?[]u8, null), try normalizeRequestPath(std.testing.allocator, "/foo/../bar"));
}

test "content type mapping" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", contentTypeFor("index.html"));
    try std.testing.expectEqualStrings("font/woff2", contentTypeFor("font.woff2"));
    try std.testing.expectEqualStrings("application/octet-stream", contentTypeFor("file.bin"));
}
