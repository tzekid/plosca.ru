const std = @import("std");
const assets = @import("assets.zig");
const manifest = @import("manifest");
const render = @import("render.zig");

const Io = std.Io;
const max_file_size = 32 * 1024 * 1024;

pub fn source(io: Io, allocator: std.mem.Allocator, pages: []const manifest.Page) !void {
    var failures: usize = 0;
    for (pages, 0..) |page, index| {
        if (page.route.len == 0 or page.route[0] != '/' or page.file.len == 0 or std.fs.path.basename(page.file).len != page.file.len) {
            std.debug.print("manifest page {s}: invalid route or file\n", .{page.slug});
            failures += 1;
        }
        for (pages[0..index]) |previous| {
            if (std.mem.eql(u8, page.slug, previous.slug) or std.mem.eql(u8, page.route, previous.route) or std.mem.eql(u8, page.file, previous.file)) {
                std.debug.print("manifest page {s}: duplicate slug, route, or file\n", .{page.slug});
                failures += 1;
            }
        }
        for (page.related) |route| {
            if (manifest.byRoute(pages, route) == null and !std.mem.eql(u8, route, "/resume.pdf")) {
                std.debug.print("manifest page {s}: unknown related route {s}\n", .{ page.slug, route });
                failures += 1;
            }
        }

        const path = try std.fmt.allocPrint(allocator, "content/pages/{s}", .{page.file});
        defer allocator.free(path);
        const html = readFile(io, allocator, path) catch |err| {
            std.debug.print("{s}: cannot read authored page ({s})\n", .{ path, @errorName(err) });
            failures += 1;
            continue;
        };
        defer allocator.free(html);
        failures += checkDocument(page, html, path, true);
    }

    for (assets.copies) |entry| {
        if (!try fileExists(io, entry.source)) {
            std.debug.print("{s}: missing source asset\n", .{entry.source});
            failures += 1;
        }
    }
    if (!try fileExists(io, "content/link-context.json")) {
        std.debug.print("content/link-context.json: missing link metadata\n", .{});
        failures += 1;
    }
    if (failures != 0) return error.SiteValidationFailed;
}

pub fn dist(
    io: Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    pages: []const manifest.Page,
    expected_previews: usize,
) !void {
    var failures: usize = 0;
    for (pages) |page| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, page.file });
        defer allocator.free(path);
        const html = readFile(io, allocator, path) catch |err| {
            std.debug.print("{s}: cannot read generated page ({s})\n", .{ path, @errorName(err) });
            failures += 1;
            continue;
        };
        defer allocator.free(html);
        failures += checkDocument(page, html, path, false);
        failures += try checkHtmlReferences(io, allocator, root, path, html, pages);
    }

    for (assets.copies) |entry| {
        const output = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, entry.output });
        defer allocator.free(output);
        failures += try compareFiles(io, allocator, entry.source, output);
    }

    failures += try checkGeneratedDirectory(io, allocator, root, "assets/archive", "archive", pages, null);
    failures += try checkGeneratedDirectory(io, allocator, root, null, "previews", pages, expected_previews);
    failures += try checkPreviewReferences(io, allocator, root, pages);
    failures += try checkCssReferences(io, allocator, root, pages);
    failures += try checkForbiddenArtifacts(io, allocator, root);

    if (failures != 0) return error.SiteValidationFailed;
}

fn checkDocument(page: manifest.Page, html: []const u8, path: []const u8, authored: bool) usize {
    var failures: usize = 0;
    if (!std.mem.startsWith(u8, std.mem.trimStart(u8, html, " \t\r\n"), "<!doctype html>") or
        std.mem.indexOf(u8, html, "<html") == null or
        std.mem.indexOf(u8, html, "</html>") == null)
    {
        std.debug.print("{s}: not a complete HTML document\n", .{path});
        failures += 1;
    }

    var title_buf: [512]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "<title>{s}</title>", .{page.title}) catch "";
    if (std.mem.count(u8, html, title) != 1) {
        std.debug.print("{s}: title does not match manifest\n", .{path});
        failures += 1;
    }
    if (!hasMetaDescription(html)) {
        std.debug.print("{s}: missing or empty meta description\n", .{path});
        failures += 1;
    }

    const start_count = std.mem.count(u8, html, "<!-- generated:connections:start -->");
    const end_count = std.mem.count(u8, html, "<!-- generated:connections:end -->");
    const needs_connections = page.kind == .article or page.kind == .prose;
    if ((needs_connections and (start_count != 1 or end_count != 1)) or (!needs_connections and (start_count != 0 or end_count != 0))) {
        std.debug.print("{s}: invalid generated-connections markers\n", .{path});
        failures += 1;
    }
    if (!authored and needs_connections and std.mem.count(u8, html, "<div class=\"generated-connections\">") != 1) {
        std.debug.print("{s}: generated connections are missing\n", .{path});
        failures += 1;
    }

    const forbidden = [_][]const u8{ "hx-", "data-hx-", "htmx", "/metadata/", "preview-controller.js", "/vendor/" };
    for (forbidden) |needle| {
        if (std.mem.indexOf(u8, html, needle) != null) {
            std.debug.print("{s}: forbidden legacy construct {s}\n", .{ path, needle });
            failures += 1;
        }
    }
    if (authored) {
        if (std.mem.indexOf(u8, html, "{{asset:style.css}}") == null or
            std.mem.indexOf(u8, html, "{{asset:theme.js}}") == null or
            std.mem.indexOf(u8, html, "{{asset:preview.js}}") == null)
        {
            std.debug.print("{s}: missing explicit asset marker\n", .{path});
            failures += 1;
        }
    } else if (std.mem.indexOf(u8, html, "{{asset:") != null) {
        std.debug.print("{s}: unresolved asset marker\n", .{path});
        failures += 1;
    }

    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "data-previewable")) |position| {
        const tag_start = std.mem.lastIndexOfScalar(u8, html[0..position], '<') orelse position;
        const tag_end = std.mem.indexOfScalarPos(u8, html, position, '>') orelse html.len;
        const tag = html[tag_start..tag_end];
        const href = attributeValue(tag, "href");
        const preview_source = attributeValue(tag, "data-preview-src");
        if (href == null or preview_source == null or !std.mem.startsWith(u8, preview_source.?, "/previews/")) {
            std.debug.print("{s}: previewable link lacks a static preview source\n", .{path});
            failures += 1;
        } else {
            const key = render.shortHash(href.?);
            var expected_buf: [64]u8 = undefined;
            const expected = std.fmt.bufPrint(&expected_buf, "/previews/{s}.html", .{&key}) catch "";
            if (!std.mem.eql(u8, preview_source.?, expected)) {
                std.debug.print("{s}: preview source for {s} has the wrong content hash\n", .{ path, href.? });
                failures += 1;
            }
        }
        search_pos = tag_end;
    }
    return failures;
}

fn hasMetaDescription(html: []const u8) bool {
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<meta")) |start| {
        const end = std.mem.indexOfScalarPos(u8, html, start, '>') orelse return false;
        const tag = html[start..end];
        if (attributeValue(tag, "name")) |name| {
            if (std.mem.eql(u8, name, "description")) {
                const value = attributeValue(tag, "content") orelse return false;
                return std.mem.trim(u8, value, " \t\r\n").len != 0;
            }
        }
        search_pos = end + 1;
    }
    return false;
}

fn checkGeneratedDirectory(
    io: Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    source_dir: ?[]const u8,
    output_name: []const u8,
    pages: []const manifest.Page,
    expected_count: ?usize,
) !usize {
    const output_dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, output_name });
    defer allocator.free(output_dir_path);
    var output_dir = Io.Dir.cwd().openDir(io, output_dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("{s}: missing generated directory ({s})\n", .{ output_dir_path, @errorName(err) });
        return 1;
    };
    defer output_dir.close(io);
    var count: usize = 0;
    var failures: usize = 0;
    var iterator = output_dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".html")) {
            std.debug.print("{s}/{s}: unexpected generated entry\n", .{ output_dir_path, entry.name });
            failures += 1;
            continue;
        }
        count += 1;
        const output_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_dir_path, entry.name });
        defer allocator.free(output_path);
        const html = try readFile(io, allocator, output_path);
        defer allocator.free(html);
        if (std.mem.indexOf(u8, html, "{{asset:") != null or std.mem.indexOf(u8, html, "htmx") != null or std.mem.indexOf(u8, html, "hx-") != null) {
            std.debug.print("{s}: unresolved or legacy markup\n", .{output_path});
            failures += 1;
        }
        if (source_dir != null and
            (!std.mem.startsWith(u8, std.mem.trimStart(u8, html, " \t\r\n"), "<!doctype html>") or
                std.mem.indexOf(u8, html, "<html") == null or
                std.mem.indexOf(u8, html, "</html>") == null))
        {
            std.debug.print("{s}: archive output is not a complete HTML document\n", .{output_path});
            failures += 1;
        }
        if (source_dir == null and
            (std.mem.count(u8, html, "<aside id=\"link-preview\"") != 1 or
                std.mem.count(u8, html, "data-preview-href=") != 1))
        {
            std.debug.print("{s}: invalid preview fragment shape\n", .{output_path});
            failures += 1;
        }
        failures += try checkHtmlReferences(io, allocator, root, output_path, html, pages);
        if (source_dir) |source_root| {
            const source_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ source_root, entry.name });
            defer allocator.free(source_path);
            if (!try fileExists(io, source_path)) {
                std.debug.print("{s}: archive source is missing\n", .{source_path});
                failures += 1;
            }
        }
    }
    if (expected_count) |expected| {
        if (count != expected) {
            std.debug.print("{s}: expected {d} HTML files, found {d}\n", .{ output_dir_path, expected, count });
            failures += 1;
        }
    } else if (source_dir) |source_root| {
        const source_count = try htmlFileCount(io, source_root);
        if (source_count != count) {
            std.debug.print("{s}: expected {d} archive pages, found {d}\n", .{ output_dir_path, source_count, count });
            failures += 1;
        }
    }
    return failures;
}

fn checkPreviewReferences(io: Io, allocator: std.mem.Allocator, root: []const u8, pages: []const manifest.Page) !usize {
    var failures: usize = 0;
    for (pages) |page| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, page.file });
        defer allocator.free(path);
        const html = try readFile(io, allocator, path);
        defer allocator.free(html);
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, html, search_pos, "data-preview-src=")) |position| {
            const value = attributeValueAt(html, position, "data-preview-src") orelse {
                failures += 1;
                break;
            };
            if (try localReferenceProblem(io, allocator, root, value, pages)) |problem| {
                std.debug.print("{s}: preview source {s}: {s}\n", .{ path, value, problem });
                failures += 1;
            }
            search_pos = position + "data-preview-src=".len;
        }
    }
    return failures;
}

fn checkHtmlReferences(io: Io, allocator: std.mem.Allocator, root: []const u8, path: []const u8, html: []const u8, pages: []const manifest.Page) !usize {
    var failures: usize = 0;
    const attributes = [_][]const u8{ "href", "src" };
    for (attributes) |attribute| {
        var needle_buf: [16]u8 = undefined;
        const needle = try std.fmt.bufPrint(&needle_buf, "{s}=", .{attribute});
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, html, search_pos, needle)) |position| {
            const value = attributeValueAt(html, position, attribute) orelse {
                search_pos = position + needle.len;
                continue;
            };
            if (try localReferenceProblem(io, allocator, root, value, pages)) |problem| {
                std.debug.print("{s}: {s} {s}: {s}\n", .{ path, attribute, value, problem });
                failures += 1;
            }
            search_pos = position + needle.len;
        }
    }
    return failures;
}

fn checkCssReferences(io: Io, allocator: std.mem.Allocator, root: []const u8, pages: []const manifest.Page) !usize {
    const path = try std.fmt.allocPrint(allocator, "{s}/style.css", .{root});
    defer allocator.free(path);
    const css = try readFile(io, allocator, path);
    defer allocator.free(css);
    var failures: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, css, search_pos, "url(")) |start| {
        const close = std.mem.indexOfScalarPos(u8, css, start + 4, ')') orelse break;
        const raw = std.mem.trim(u8, css[start + 4 .. close], " \t\r\n\"'");
        if (try localReferenceProblem(io, allocator, root, raw, pages)) |problem| {
            std.debug.print("{s}: url {s}: {s}\n", .{ path, raw, problem });
            failures += 1;
        }
        search_pos = close + 1;
    }
    return failures;
}

fn localReferenceProblem(io: Io, allocator: std.mem.Allocator, root: []const u8, raw: []const u8, pages: []const manifest.Page) !?[]const u8 {
    if (raw.len == 0 or raw[0] == '#' or std.mem.startsWith(u8, raw, "http://") or std.mem.startsWith(u8, raw, "https://") or std.mem.startsWith(u8, raw, "mailto:") or std.mem.startsWith(u8, raw, "data:")) return null;
    if (raw[0] != '/') return "relative reference is not allowed";
    var end = raw.len;
    if (std.mem.indexOfAny(u8, raw, "?#")) |position| end = position;
    const route = raw[0..end];
    if (manifest.byRoute(pages, route) != null) return null;
    if (std.mem.eql(u8, route, "/archive")) {
        const archive_index = try std.fmt.allocPrint(allocator, "{s}/archive/index.html", .{root});
        defer allocator.free(archive_index);
        return if (try fileExists(io, archive_index)) null else "archive index is missing";
    }
    const relative = route[1..];
    if (relative.len == 0) return null;
    const output = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, relative });
    defer allocator.free(output);
    return if (try fileExists(io, output)) null else "target does not exist";
}

fn checkForbiddenArtifacts(io: Io, allocator: std.mem.Allocator, root: []const u8) !usize {
    return checkForbiddenDirectory(io, allocator, root);
}

fn checkForbiddenDirectory(io: Io, allocator: std.mem.Allocator, path: []const u8) !usize {
    var dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var failures: usize = 0;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".br") or std.mem.endsWith(u8, entry.name, ".gz") or std.mem.eql(u8, entry.name, "vendor") or std.mem.eql(u8, entry.name, "metadata")) {
            std.debug.print("{s}/{s}: forbidden generated or legacy artifact\n", .{ path, entry.name });
            failures += 1;
        }
        if (entry.kind == .directory) {
            const child = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name });
            defer allocator.free(child);
            failures += try checkForbiddenDirectory(io, allocator, child);
        }
    }
    return failures;
}

fn compareFiles(io: Io, allocator: std.mem.Allocator, source_path: []const u8, output_path: []const u8) !usize {
    const source_data = readFile(io, allocator, source_path) catch |err| {
        std.debug.print("{s}: cannot read ({s})\n", .{ source_path, @errorName(err) });
        return 1;
    };
    defer allocator.free(source_data);
    const output_data = readFile(io, allocator, output_path) catch |err| {
        std.debug.print("{s}: cannot read ({s})\n", .{ output_path, @errorName(err) });
        return 1;
    };
    defer allocator.free(output_data);
    if (!std.mem.eql(u8, source_data, output_data)) {
        std.debug.print("{s}: output differs from {s}\n", .{ output_path, source_path });
        return 1;
    }
    return 0;
}

fn htmlFileCount(io: Io, path: []const u8) !usize {
    var dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var count: usize = 0;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".html")) count += 1;
    }
    return count;
}

fn attributeValueAt(html: []const u8, position: usize, name: []const u8) ?[]const u8 {
    const after_name = position + name.len;
    if (after_name >= html.len or html[after_name] != '=') return null;
    const quote_pos = after_name + 1;
    if (quote_pos >= html.len or (html[quote_pos] != '"' and html[quote_pos] != '\'')) return null;
    const start = quote_pos + 1;
    const end = std.mem.indexOfScalarPos(u8, html, start, html[quote_pos]) orelse return null;
    return html[start..end];
}

fn attributeValue(tag: []const u8, name: []const u8) ?[]const u8 {
    var needle_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buf, "{s}=", .{name}) catch return null;
    const position = std.mem.indexOf(u8, tag, needle) orelse return null;
    return attributeValueAt(tag, position, name);
}

fn readFile(io: Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_file_size));
}

fn fileExists(io: Io, path: []const u8) !bool {
    var file = Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    file.close(io);
    return true;
}
