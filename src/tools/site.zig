const std = @import("std");

const Io = std.Io;

const source_css_path = "src/styles/site.css";
const generated_css_path = "static/style.css";
const static_dir_path = "static";
const metadata_dir_path = "static/metadata";
const pages_json_path = "static/metadata/pages.json";
const max_file_size = 16 * 1024 * 1024;

const CheckError = error{SiteCheckFailed};

const PageKind = enum {
    home,
    article,
    profile,
    prose,
    error_page,
};

const PageMeta = struct {
    slug: []const u8,
    route: []const u8,
    file: []const u8,
    title: []const u8,
    description: []const u8,
    date: ?[]const u8 = null,
    updated: ?[]const u8 = null,
    tags: []const []const u8,
    related: []const []const u8,
    kind: PageKind,
};

const home_tags = [_][]const u8{ "personal", "index", "writing" };
const home_related = [_][]const u8{ "/hello_world", "/about", "/prose" };
const about_tags = [_][]const u8{ "profile", "resume", "work" };
const about_related = [_][]const u8{ "/", "/resume.pdf" };
const hello_tags = [_][]const u8{ "website", "static-site", "pandoc", "bash" };
const hello_related = [_][]const u8{ "/prose", "/about" };
const prose_tags = [_][]const u8{ "prose", "poetry", "writing" };
const prose_related = [_][]const u8{ "/hello_world", "/" };
const error_tags = [_][]const u8{"recovery"};
const error_related = [_][]const u8{ "/", "/about", "/hello_world", "/prose" };

const pages = [_]PageMeta{
    .{
        .slug = "home",
        .route = "/",
        .file = "index.html",
        .title = "Ilie Ploscaru",
        .description = "Personal site of Ilie Ploscaru, interested in psychology and tech.",
        .date = "2019-01-01",
        .updated = "2026-06-14",
        .tags = home_tags[0..],
        .related = home_related[0..],
        .kind = .home,
    },
    .{
        .slug = "about",
        .route = "/about",
        .file = "about.html",
        .title = "About",
        .description = "About Ilie Ploscaru: full-stack developer and data engineer focused on data platforms, BI, and automation.",
        .updated = "2026-06-14",
        .tags = about_tags[0..],
        .related = about_related[0..],
        .kind = .profile,
    },
    .{
        .slug = "hello_world",
        .route = "/hello_world",
        .file = "hello_world.html",
        .title = "Hello World",
        .description = "Hello World: first post by Ilie Ploscaru introducing the site and its themes.",
        .date = "2019-01-01",
        .updated = "2026-06-14",
        .tags = hello_tags[0..],
        .related = hello_related[0..],
        .kind = .article,
    },
    .{
        .slug = "prose",
        .route = "/prose",
        .file = "prose.html",
        .title = "Prose",
        .description = "Prose by Ilie Ploscaru: old poems, essays, thoughts, and writing samples.",
        .updated = "2026-06-14",
        .tags = prose_tags[0..],
        .related = prose_related[0..],
        .kind = .prose,
    },
    .{
        .slug = "404",
        .route = "/404",
        .file = "404.html",
        .title = "Page not found | Ilie Ploscaru",
        .description = "The requested page was not found. Return to the main pages on plosca.ru.",
        .updated = "2026-06-14",
        .tags = error_tags[0..],
        .related = error_related[0..],
        .kind = .error_page,
    },
};

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
    try writeGeneratedMetadata(io, gpa);
    const enhanced = try syncHtmlEnhancements(io, gpa);

    const version = styleVersion(css);
    const updated = try syncHtmlStyleRefs(io, gpa, version, true);
    std.debug.print("style.css version {s}; updated {d} stylesheet ref(s), enhanced {d} HTML file(s), generated page metadata\n", .{ version[0..], updated, enhanced });
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
    failures += try checkGeneratedMetadata(io, gpa);
    failures += try auditReferences(io, gpa, generated_css);
    failures += try auditContent(io, gpa);

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

fn writeGeneratedMetadata(io: Io, gpa: std.mem.Allocator) !void {
    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, metadata_dir_path);

    const json = try renderPagesJson(gpa);
    defer gpa.free(json);
    try cwd.writeFile(io, .{ .sub_path = pages_json_path, .data = json });
}

fn checkGeneratedMetadata(io: Io, gpa: std.mem.Allocator) !usize {
    const expected = try renderPagesJson(gpa);
    defer gpa.free(expected);

    const actual = Io.Dir.cwd().readFileAlloc(io, pages_json_path, gpa, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("{s} is missing; run `zig build css`\n", .{pages_json_path});
            return 1;
        },
        else => |e| return e,
    };
    defer gpa.free(actual);

    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("{s} is not synchronized with the site manifest; run `zig build css`\n", .{pages_json_path});
        return 1;
    }
    return 0;
}

fn renderPagesJson(gpa: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    try out.appendSlice(gpa, "{\n  \"pages\": [\n");
    for (pages, 0..) |page, index| {
        if (index != 0) try out.appendSlice(gpa, ",\n");
        try out.appendSlice(gpa, "    {\n");
        try appendJsonField(gpa, &out, "slug", page.slug, true);
        try appendJsonField(gpa, &out, "route", page.route, true);
        try appendJsonField(gpa, &out, "file", page.file, true);
        try appendJsonField(gpa, &out, "title", page.title, true);
        try appendJsonField(gpa, &out, "description", page.description, true);
        if (page.date) |date| {
            try appendJsonField(gpa, &out, "date", date, true);
        } else {
            try appendJsonNullField(gpa, &out, "date", true);
        }
        if (page.updated) |updated| {
            try appendJsonField(gpa, &out, "updated", updated, true);
        } else {
            try appendJsonNullField(gpa, &out, "updated", true);
        }
        try appendJsonField(gpa, &out, "kind", pageKindName(page.kind), true);
        try appendJsonArrayField(gpa, &out, "tags", page.tags, true);
        try appendJsonArrayField(gpa, &out, "related", page.related, false);
        try out.appendSlice(gpa, "    }");
    }
    try out.appendSlice(gpa, "\n  ]\n}\n");
    return try out.toOwnedSlice(gpa);
}

fn pageKindName(kind: PageKind) []const u8 {
    return switch (kind) {
        .home => "home",
        .article => "article",
        .profile => "profile",
        .prose => "prose",
        .error_page => "error",
    };
}

fn appendJsonField(gpa: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: []const u8, comma: bool) !void {
    try out.appendSlice(gpa, "      ");
    try appendJsonString(gpa, out, key);
    try out.appendSlice(gpa, ": ");
    try appendJsonString(gpa, out, value);
    if (comma) try out.appendSlice(gpa, ",");
    try out.appendSlice(gpa, "\n");
}

fn appendJsonNullField(gpa: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, comma: bool) !void {
    try out.appendSlice(gpa, "      ");
    try appendJsonString(gpa, out, key);
    try out.appendSlice(gpa, ": null");
    if (comma) try out.appendSlice(gpa, ",");
    try out.appendSlice(gpa, "\n");
}

fn appendJsonArrayField(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    key: []const u8,
    values: []const []const u8,
    comma: bool,
) !void {
    try out.appendSlice(gpa, "      ");
    try appendJsonString(gpa, out, key);
    try out.appendSlice(gpa, ": [");
    for (values, 0..) |value, index| {
        if (index != 0) try out.appendSlice(gpa, ", ");
        try appendJsonString(gpa, out, value);
    }
    try out.appendSlice(gpa, "]");
    if (comma) try out.appendSlice(gpa, ",");
    try out.appendSlice(gpa, "\n");
}

fn appendJsonString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(gpa, '"');
    for (value) |char| {
        switch (char) {
            '\\' => try out.appendSlice(gpa, "\\\\"),
            '"' => try out.appendSlice(gpa, "\\\""),
            '\n' => try out.appendSlice(gpa, "\\n"),
            '\r' => try out.appendSlice(gpa, "\\r"),
            '\t' => try out.appendSlice(gpa, "\\t"),
            0...8, 11...12, 14...0x1f => try out.print(gpa, "\\u{x:0>4}", .{char}),
            else => try out.append(gpa, char),
        }
    }
    try out.append(gpa, '"');
}

fn syncHtmlEnhancements(io: Io, gpa: std.mem.Allocator) !usize {
    var static_dir = try Io.Dir.cwd().openDir(io, static_dir_path, .{ .iterate = true });
    defer static_dir.close(io);

    var updated: usize = 0;
    var it = static_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".html")) continue;

        const html = try static_dir.readFileAlloc(io, entry.name, gpa, .limited(max_file_size));
        defer gpa.free(html);

        const with_toc_labels = try rewriteTocLabels(gpa, html);
        defer gpa.free(with_toc_labels);
        const enhanced = try rewriteHeadingAnchors(gpa, with_toc_labels);
        defer gpa.free(enhanced);

        if (!std.mem.eql(u8, html, enhanced)) {
            try static_dir.writeFile(io, .{ .sub_path = entry.name, .data = enhanced });
            updated += 1;
        }
    }

    return updated;
}

fn rewriteTocLabels(gpa: std.mem.Allocator, html: []const u8) ![]u8 {
    const old = "<nav id=\"TOC\" role=\"doc-toc\">";
    const new = "<nav id=\"TOC\" role=\"doc-toc\" aria-label=\"Contents\">";
    if (std.mem.indexOf(u8, html, new) != null) return try gpa.dupe(u8, html);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var cursor: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, old)) |match_pos| {
        try out.appendSlice(gpa, html[cursor..match_pos]);
        try out.appendSlice(gpa, new);
        cursor = match_pos + old.len;
        search_pos = cursor;
    }
    try out.appendSlice(gpa, html[cursor..]);
    return try out.toOwnedSlice(gpa);
}

fn rewriteHeadingAnchors(gpa: std.mem.Allocator, html: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var cursor: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<h")) |heading_start| {
        if (heading_start + 3 >= html.len) break;
        const level = html[heading_start + 2];
        if ((level != '2' and level != '3') or !std.ascii.isWhitespace(html[heading_start + 3])) {
            search_pos = heading_start + 2;
            continue;
        }

        const tag_end = std.mem.indexOfScalarPos(u8, html, heading_start, '>') orelse break;
        const close_tag = if (level == '2') "</h2>" else "</h3>";
        const close_start = std.mem.indexOfPos(u8, html, tag_end + 1, close_tag) orelse break;
        const close_end = close_start + close_tag.len;
        const heading = html[heading_start..close_end];
        const tag = html[heading_start..tag_end];
        const id = attributeValue(tag, "id") orelse {
            search_pos = close_end;
            continue;
        };
        if (std.mem.indexOf(u8, heading, "heading-anchor") != null) {
            search_pos = close_end;
            continue;
        }

        try out.appendSlice(gpa, html[cursor..close_start]);
        try out.print(
            gpa,
            "<a class=\"heading-anchor\" href=\"#{s}\" aria-label=\"Link to this section\">&lt;{{ # }}&gt;</a>",
            .{id},
        );
        cursor = close_start;
        search_pos = close_end;
    }

    try out.appendSlice(gpa, html[cursor..]);
    return try out.toOwnedSlice(gpa);
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

fn auditContent(io: Io, gpa: std.mem.Allocator) !usize {
    var failures: usize = 0;
    for (pages) |page| {
        failures += try auditManifestPageReferences(io, gpa, page);

        const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ static_dir_path, page.file });
        defer gpa.free(path);

        const html = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_size)) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("{s}: manifest page file is missing\n", .{path});
                failures += 1;
                continue;
            },
            else => |e| return e,
        };
        defer gpa.free(html);

        failures += auditPageMetadata(page, html);
        failures += try auditPageIdsAndFragments(gpa, page, html);
        failures += auditHeadingAnchors(page, html);
        failures += auditAnchorText(page, html);
    }
    return failures;
}

fn auditManifestPageReferences(io: Io, gpa: std.mem.Allocator, page: PageMeta) !usize {
    var failures: usize = 0;
    if (try checkLocalReference(io, gpa, page.route)) |problem| {
        std.debug.print("manifest page {s}: broken route {s}: {s}\n", .{ page.slug, page.route, problem });
        failures += 1;
    }
    for (page.related) |related| {
        if (try checkLocalReference(io, gpa, related)) |problem| {
            std.debug.print("manifest page {s}: broken related link {s}: {s}\n", .{ page.slug, related, problem });
            failures += 1;
        }
    }
    return failures;
}

fn auditPageMetadata(page: PageMeta, html: []const u8) usize {
    var failures: usize = 0;

    const title = findElementContent(html, "title") orelse {
        std.debug.print("static/{s}: missing <title>\n", .{page.file});
        return failures + 1;
    };
    const trimmed_title = std.mem.trim(u8, title, " \t\r\n");
    if (trimmed_title.len == 0) {
        std.debug.print("static/{s}: empty <title>\n", .{page.file});
        failures += 1;
    } else if (trimmed_title.len > 80) {
        std.debug.print("static/{s}: <title> is longer than 80 bytes\n", .{page.file});
        failures += 1;
    }
    if (!std.mem.eql(u8, trimmed_title, page.title)) {
        std.debug.print("static/{s}: <title> does not match manifest title \"{s}\"\n", .{ page.file, page.title });
        failures += 1;
    }

    const description = findMetaContent(html, "description") orelse {
        std.debug.print("static/{s}: missing meta description\n", .{page.file});
        return failures + 1;
    };
    const trimmed_description = std.mem.trim(u8, description, " \t\r\n");
    if (trimmed_description.len == 0) {
        std.debug.print("static/{s}: empty meta description\n", .{page.file});
        failures += 1;
    } else if (trimmed_description.len > 180) {
        std.debug.print("static/{s}: meta description is longer than 180 bytes\n", .{page.file});
        failures += 1;
    }

    return failures;
}

fn auditPageIdsAndFragments(gpa: std.mem.Allocator, page: PageMeta, html: []const u8) !usize {
    var ids: std.ArrayList([]const u8) = .empty;
    defer ids.deinit(gpa);

    var failures = try collectIds(gpa, page, html, &ids);

    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "href=")) |href_pos| {
        const quote_pos = href_pos + "href=".len;
        if (quote_pos >= html.len) break;
        const quote = html[quote_pos];
        if (quote != '"' and quote != '\'') {
            search_pos = quote_pos + 1;
            continue;
        }

        const value_start = quote_pos + 1;
        const value_end = std.mem.indexOfScalarPos(u8, html, value_start, quote) orelse return error.InvalidHtml;
        const raw = html[value_start..value_end];
        if (fragmentForCurrentPage(page, raw)) |fragment| {
            if (fragment.len == 0 or !idExists(ids.items, fragment)) {
                std.debug.print("static/{s}: broken fragment link {s}\n", .{ page.file, raw });
                failures += 1;
            }
        }
        search_pos = value_end + 1;
    }

    return failures;
}

fn collectIds(
    gpa: std.mem.Allocator,
    page: PageMeta,
    html: []const u8,
    ids: *std.ArrayList([]const u8),
) !usize {
    var failures: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "id=")) |id_pos| {
        const quote_pos = id_pos + "id=".len;
        if (quote_pos >= html.len) break;
        const quote = html[quote_pos];
        if (quote != '"' and quote != '\'') {
            search_pos = quote_pos + 1;
            continue;
        }

        const value_start = quote_pos + 1;
        const value_end = std.mem.indexOfScalarPos(u8, html, value_start, quote) orelse return error.InvalidHtml;
        const id = html[value_start..value_end];
        if (id.len == 0) {
            std.debug.print("static/{s}: empty id attribute\n", .{page.file});
            failures += 1;
        } else if (idExists(ids.items, id)) {
            std.debug.print("static/{s}: duplicate id \"{s}\"\n", .{ page.file, id });
            failures += 1;
        } else {
            try ids.append(gpa, id);
        }
        search_pos = value_end + 1;
    }
    return failures;
}

fn fragmentForCurrentPage(page: PageMeta, raw: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, raw, "#")) return raw[1..];
    if (std.mem.startsWith(u8, raw, "http://") or
        std.mem.startsWith(u8, raw, "https://") or
        std.mem.startsWith(u8, raw, "mailto:") or
        std.mem.startsWith(u8, raw, "data:"))
    {
        return null;
    }

    const hash_pos = std.mem.indexOfScalar(u8, raw, '#') orelse return null;
    const path = raw[0..hash_pos];
    const fragment = raw[hash_pos + 1 ..];
    if (path.len == 0) return fragment;
    if (std.mem.eql(u8, path, page.route)) return fragment;
    if (std.mem.eql(u8, page.route, "/") and std.mem.eql(u8, path, "/")) return fragment;
    return null;
}

fn idExists(ids: []const []const u8, id: []const u8) bool {
    for (ids) |candidate| {
        if (std.mem.eql(u8, candidate, id)) return true;
    }
    return false;
}

fn auditHeadingAnchors(page: PageMeta, html: []const u8) usize {
    if (page.kind != .article and page.kind != .prose) return 0;

    var failures: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<h")) |heading_start| {
        if (heading_start + 3 >= html.len) break;
        const level = html[heading_start + 2];
        if ((level != '2' and level != '3') or !std.ascii.isWhitespace(html[heading_start + 3])) {
            search_pos = heading_start + 2;
            continue;
        }

        const tag_end = std.mem.indexOfScalarPos(u8, html, heading_start, '>') orelse break;
        const close_tag = if (level == '2') "</h2>" else "</h3>";
        const close_start = std.mem.indexOfPos(u8, html, tag_end + 1, close_tag) orelse break;
        const close_end = close_start + close_tag.len;
        const tag = html[heading_start..tag_end];
        if (attributeValue(tag, "id") != null and std.mem.indexOf(u8, html[heading_start..close_end], "heading-anchor") == null) {
            std.debug.print("static/{s}: h{c} near byte {d} is missing a heading self-link\n", .{ page.file, level, heading_start });
            failures += 1;
        }
        search_pos = close_end;
    }
    return failures;
}

fn auditAnchorText(page: PageMeta, html: []const u8) usize {
    var failures: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<a")) |anchor_start| {
        if (isInsideHtmlComment(html, anchor_start)) {
            search_pos = anchor_start + "<a".len;
            continue;
        }
        const tag_end = std.mem.indexOfScalarPos(u8, html, anchor_start, '>') orelse break;
        const close = std.mem.indexOfPos(u8, html, tag_end + 1, "</a>") orelse break;
        const tag = html[anchor_start..tag_end];
        const inner = html[tag_end + 1 .. close];
        if (!anchorHasReadableContent(inner) and !std.mem.containsAtLeast(u8, tag, 1, "href=\"#cb")) {
            std.debug.print("static/{s}: anchor has no readable text near byte {d}\n", .{ page.file, anchor_start });
            failures += 1;
        }
        search_pos = close + "</a>".len;
    }
    return failures;
}

fn isInsideHtmlComment(html: []const u8, pos: usize) bool {
    const last_open = std.mem.lastIndexOf(u8, html[0..pos], "<!--") orelse return false;
    const last_close = std.mem.lastIndexOf(u8, html[0..pos], "-->") orelse return true;
    return last_open > last_close;
}

fn anchorHasReadableContent(inner: []const u8) bool {
    if (std.mem.indexOf(u8, inner, "<img") != null) return true;

    var in_tag = false;
    for (inner) |char| {
        if (char == '<') {
            in_tag = true;
            continue;
        }
        if (char == '>') {
            in_tag = false;
            continue;
        }
        if (!in_tag and !std.ascii.isWhitespace(char)) return true;
    }
    return false;
}

fn findElementContent(html: []const u8, tag_name: []const u8) ?[]const u8 {
    const open = std.fmt.allocPrint(std.heap.page_allocator, "<{s}", .{tag_name}) catch return null;
    defer std.heap.page_allocator.free(open);
    const close = std.fmt.allocPrint(std.heap.page_allocator, "</{s}>", .{tag_name}) catch return null;
    defer std.heap.page_allocator.free(close);

    const open_start = std.mem.indexOf(u8, html, open) orelse return null;
    const open_end = std.mem.indexOfScalarPos(u8, html, open_start, '>') orelse return null;
    const close_start = std.mem.indexOfPos(u8, html, open_end + 1, close) orelse return null;
    return html[open_end + 1 .. close_start];
}

fn findMetaContent(html: []const u8, name: []const u8) ?[]const u8 {
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<meta")) |meta_start| {
        const tag_end = std.mem.indexOfScalarPos(u8, html, meta_start, '>') orelse return null;
        const tag = html[meta_start..tag_end];
        if (attributeEquals(tag, "name", name)) {
            return attributeValue(tag, "content");
        }
        search_pos = tag_end + 1;
    }
    return null;
}

fn attributeEquals(tag: []const u8, attr_name: []const u8, expected: []const u8) bool {
    const value = attributeValue(tag, attr_name) orelse return false;
    return std.ascii.eqlIgnoreCase(std.mem.trim(u8, value, " \t\r\n"), expected);
}

fn attributeValue(tag: []const u8, attr_name: []const u8) ?[]const u8 {
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, tag, search_pos, attr_name)) |attr_pos| {
        if (attr_pos != 0 and isNameChar(tag[attr_pos - 1])) {
            search_pos = attr_pos + attr_name.len;
            continue;
        }
        const eq_pos = attr_pos + attr_name.len;
        if (eq_pos >= tag.len or tag[eq_pos] != '=') {
            search_pos = attr_pos + attr_name.len;
            continue;
        }
        const quote_pos = eq_pos + 1;
        if (quote_pos >= tag.len) return null;
        const quote = tag[quote_pos];
        if (quote != '"' and quote != '\'') return null;
        const value_start = quote_pos + 1;
        const value_end = std.mem.indexOfScalarPos(u8, tag, value_start, quote) orelse return null;
        return tag[value_start..value_end];
    }
    return null;
}

fn isNameChar(char: u8) bool {
    return std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == ':';
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
