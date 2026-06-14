const std = @import("std");

const Io = std.Io;

const source_css_path = "src/styles/site.css";
const generated_css_path = "static/style.css";
const static_dir_path = "static";
const max_file_size = 16 * 1024 * 1024;

const CheckError = error{SiteCheckFailed};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 2) usageAndExit();

    if (std.mem.eql(u8, args[1], "write")) {
        try writeSite(init.io, init.gpa);
    } else if (std.mem.eql(u8, args[1], "check")) {
        try checkSite(init.io, init.gpa);
    } else {
        usageAndExit();
    }
}

fn usageAndExit() noreturn {
    std.debug.print(
        \\Usage:
        \\  site-tool write
        \\  site-tool check
        \\
    , .{});
    std.process.exit(2);
}

fn writeSite(io: Io, gpa: std.mem.Allocator) !void {
    const cwd = Io.Dir.cwd();
    const css = try cwd.readFileAlloc(io, source_css_path, gpa, .limited(max_file_size));
    defer gpa.free(css);

    try cwd.writeFile(io, .{ .sub_path = generated_css_path, .data = css });

    const version = styleVersion(css);
    const updated = try syncHtmlStyleRefs(io, gpa, version, true);
    std.debug.print("style.css version {s}; updated {d} HTML file(s)\n", .{ version[0..], updated });
}

fn checkSite(io: Io, gpa: std.mem.Allocator) !void {
    const cwd = Io.Dir.cwd();
    const source_css = try cwd.readFileAlloc(io, source_css_path, gpa, .limited(max_file_size));
    defer gpa.free(source_css);
    const generated_css = try cwd.readFileAlloc(io, generated_css_path, gpa, .limited(max_file_size));
    defer gpa.free(generated_css);

    var failures: usize = 0;
    if (!std.mem.eql(u8, source_css, generated_css)) {
        std.debug.print("{s} is not synchronized with {s}; run `zig build css`\n", .{
            generated_css_path,
            source_css_path,
        });
        failures += 1;
    }

    const version = styleVersion(generated_css);
    failures += try syncHtmlStyleRefs(io, gpa, version, false);
    failures += try auditReferences(io, gpa, generated_css);

    if (failures != 0) return CheckError.SiteCheckFailed;
    std.debug.print("site check passed; style.css version {s}\n", .{version[0..]});
}

fn styleVersion(css: []const u8) [16]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(css);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);

    const hex = "0123456789abcdef";
    var out: [16]u8 = undefined;
    for (digest[0..8], 0..) |byte, index| {
        out[index * 2] = hex[byte >> 4];
        out[index * 2 + 1] = hex[byte & 0x0f];
    }
    return out;
}

fn syncHtmlStyleRefs(io: Io, gpa: std.mem.Allocator, version: [16]u8, write: bool) !usize {
    var static_dir = try Io.Dir.cwd().openDir(io, static_dir_path, .{ .iterate = true });
    defer static_dir.close(io);

    var updated_or_failed: usize = 0;
    var it = static_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".html")) continue;

        const html = try static_dir.readFileAlloc(io, entry.name, gpa, .limited(max_file_size));
        defer gpa.free(html);

        const result = try rewriteStyleRefs(gpa, html, version);
        defer gpa.free(result.html);

        if (write) {
            if (!std.mem.eql(u8, html, result.html)) {
                try static_dir.writeFile(io, .{ .sub_path = entry.name, .data = result.html });
                updated_or_failed += 1;
            }
        } else {
            if (result.refs == 0) {
                std.debug.print("static/{s}: no stylesheet href found\n", .{entry.name});
                updated_or_failed += 1;
            }
            if (result.mismatches != 0) {
                std.debug.print("static/{s}: stylesheet href is not /style.css?v={s}\n", .{ entry.name, version[0..] });
                updated_or_failed += result.mismatches;
            }
        }
    }

    return updated_or_failed;
}

const RewriteResult = struct {
    html: []u8,
    refs: usize,
    mismatches: usize,
};

fn rewriteStyleRefs(gpa: std.mem.Allocator, html: []const u8, version: [16]u8) !RewriteResult {
    const prefix = "href=";
    const stylesheet = try std.fmt.allocPrint(gpa, "/style.css?v={s}", .{version[0..]});
    defer gpa.free(stylesheet);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var cursor: usize = 0;
    var search_pos: usize = 0;
    var refs: usize = 0;
    var mismatches: usize = 0;

    while (std.mem.indexOfPos(u8, html, search_pos, prefix)) |href_pos| {
        const quote_pos = href_pos + prefix.len;
        if (quote_pos >= html.len) break;
        const quote = html[quote_pos];
        if (quote != '"' and quote != '\'') {
            search_pos = quote_pos + 1;
            continue;
        }

        const value_start = quote_pos + 1;
        if (!std.mem.startsWith(u8, html[value_start..], "/style.css")) {
            search_pos = value_start;
            continue;
        }

        const value_end = std.mem.indexOfScalarPos(u8, html, value_start, quote) orelse return error.InvalidHtml;
        refs += 1;
        if (!std.mem.eql(u8, html[value_start..value_end], stylesheet)) mismatches += 1;

        try out.appendSlice(gpa, html[cursor..value_start]);
        try out.appendSlice(gpa, stylesheet);
        cursor = value_end;
        search_pos = value_end + 1;
    }

    try out.appendSlice(gpa, html[cursor..]);
    return .{
        .html = try out.toOwnedSlice(gpa),
        .refs = refs,
        .mismatches = mismatches,
    };
}

fn auditReferences(io: Io, gpa: std.mem.Allocator, css: []const u8) !usize {
    var failures: usize = 0;
    var static_dir = try Io.Dir.cwd().openDir(io, static_dir_path, .{ .iterate = true });
    defer static_dir.close(io);

    var it = static_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".html")) continue;
        const html = try static_dir.readFileAlloc(io, entry.name, gpa, .limited(max_file_size));
        defer gpa.free(html);
        failures += try auditHtmlAttributes(io, gpa, entry.name, html);
    }

    failures += try auditCssUrls(io, gpa, css);
    failures += try auditManifest(io, gpa);
    return failures;
}

fn auditHtmlAttributes(io: Io, gpa: std.mem.Allocator, file_name: []const u8, html: []const u8) !usize {
    var failures: usize = 0;
    failures += try auditAttribute(io, gpa, file_name, html, "href=");
    failures += try auditAttribute(io, gpa, file_name, html, "src=");
    return failures;
}

fn auditAttribute(
    io: Io,
    gpa: std.mem.Allocator,
    file_name: []const u8,
    html: []const u8,
    attr: []const u8,
) !usize {
    var failures: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, attr)) |attr_pos| {
        const quote_pos = attr_pos + attr.len;
        if (quote_pos >= html.len) break;
        const quote = html[quote_pos];
        if (quote != '"' and quote != '\'') {
            search_pos = quote_pos + 1;
            continue;
        }

        const value_start = quote_pos + 1;
        const value_end = std.mem.indexOfScalarPos(u8, html, value_start, quote) orelse return error.InvalidHtml;
        const raw = html[value_start..value_end];
        if (try checkLocalReference(io, gpa, raw)) |problem| {
            std.debug.print("static/{s}: broken {s}{c}{s}{c}: {s}\n", .{
                file_name,
                attr,
                quote,
                raw,
                quote,
                problem,
            });
            failures += 1;
        }
        search_pos = value_end + 1;
    }
    return failures;
}

fn auditCssUrls(io: Io, gpa: std.mem.Allocator, css: []const u8) !usize {
    var failures: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, css, search_pos, "url(")) |url_pos| {
        var value_start = url_pos + "url(".len;
        while (value_start < css.len and std.ascii.isWhitespace(css[value_start])) value_start += 1;
        if (value_start >= css.len) break;

        const quote: ?u8 = if (css[value_start] == '"' or css[value_start] == '\'') css[value_start] else null;
        if (quote) |_| value_start += 1;

        var value_end = value_start;
        while (value_end < css.len) : (value_end += 1) {
            if (quote) |q| {
                if (css[value_end] == q) break;
            } else if (css[value_end] == ')') {
                break;
            }
        }
        if (value_end >= css.len) return error.InvalidCss;

        const raw = std.mem.trim(u8, css[value_start..value_end], " \t\r\n");
        if (try checkLocalReference(io, gpa, raw)) |problem| {
            std.debug.print("{s}: broken url({s}): {s}\n", .{ generated_css_path, raw, problem });
            failures += 1;
        }
        search_pos = value_end + 1;
    }
    return failures;
}

fn auditManifest(io: Io, gpa: std.mem.Allocator) !usize {
    const manifest = Io.Dir.cwd().readFileAlloc(io, "static/site.webmanifest", gpa, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => |e| return e,
    };
    defer gpa.free(manifest);

    var failures: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfScalarPos(u8, manifest, search_pos, '"')) |start_quote| {
        const value_start = start_quote + 1;
        const value_end = std.mem.indexOfScalarPos(u8, manifest, value_start, '"') orelse return error.InvalidJson;
        const raw = manifest[value_start..value_end];
        if (!std.mem.startsWith(u8, raw, "/")) {
            search_pos = value_end + 1;
            continue;
        }
        if (try checkLocalReference(io, gpa, raw)) |problem| {
            std.debug.print("static/site.webmanifest: broken reference {s}: {s}\n", .{ raw, problem });
            failures += 1;
        }
        search_pos = value_end + 1;
    }
    return failures;
}

fn checkLocalReference(io: Io, gpa: std.mem.Allocator, raw: []const u8) !?[]const u8 {
    if (raw.len == 0) return null;
    if (raw[0] == '#') return null;
    if (std.mem.startsWith(u8, raw, "http://") or
        std.mem.startsWith(u8, raw, "https://") or
        std.mem.startsWith(u8, raw, "mailto:") or
        std.mem.startsWith(u8, raw, "data:"))
    {
        return null;
    }

    var normalized = raw;
    if (std.mem.indexOfAny(u8, normalized, "?#")) |index| normalized = normalized[0..index];
    if (normalized.len == 0) return null;
    if (std.mem.indexOf(u8, normalized, "..") != null) return "contains traversal";

    const rel = if (normalized[0] == '/') normalized[1..] else normalized;
    if (rel.len == 0) {
        if (try staticExists(io, gpa, "index.html")) return null;
        return "missing index.html";
    }

    if (std.mem.indexOfScalar(u8, std.fs.path.basename(rel), '.') != null) {
        if (try staticExists(io, gpa, rel)) return null;
        return "missing static asset";
    }

    if (try staticExists(io, gpa, rel)) return null;
    const html_candidate = try std.fmt.allocPrint(gpa, "{s}.html", .{rel});
    defer gpa.free(html_candidate);
    if (try staticExists(io, gpa, html_candidate)) return null;
    const index_candidate = try std.fmt.allocPrint(gpa, "{s}/index.html", .{rel});
    defer gpa.free(index_candidate);
    if (try staticExists(io, gpa, index_candidate)) return null;

    return "missing route target";
}

fn staticExists(io: Io, gpa: std.mem.Allocator, rel: []const u8) !bool {
    const path = try std.fmt.allocPrint(gpa, "static/{s}", .{rel});
    defer gpa.free(path);

    var file = Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    file.close(io);
    return true;
}
