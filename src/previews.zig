const std = @import("std");
const manifest = @import("manifest");
const graph = @import("graph.zig");
const render = @import("render.zig");

const Io = std.Io;
const max_file_size = 16 * 1024 * 1024;
const preview_html_limit = 1800;

const Preview = struct {
    href: []const u8,
    title: []const u8,
    content_html: []const u8,
    class_name: ?[]const u8 = null,
    site_name: ?[]const u8 = null,
    date: ?[]const u8 = null,
    archive: ?[]const u8 = null,
    image: ?[]const u8 = null,
    image_width: ?usize = null,
    image_height: ?usize = null,
    file_size: ?usize = null,
    pdf: bool = false,
};

pub fn writeAll(
    io: Io,
    allocator: std.mem.Allocator,
    output_root: []const u8,
    pages: []const manifest.Page,
    site: manifest.Site,
    sources: []const graph.Source,
) !usize {
    const cwd = Io.Dir.cwd();
    const output_dir = try std.fmt.allocPrint(allocator, "{s}/previews", .{output_root});
    defer allocator.free(output_dir);
    try cwd.createDirPath(io, output_dir);

    var seen = std.AutoHashMap([16]u8, []const u8).init(allocator);
    defer seen.deinit();
    var count: usize = 0;

    for (pages) |page| {
        if (page.kind == .error_page) continue;
        const source = sourceFor(sources, page.slug) orelse return error.MissingPageSource;
        const content = try internalPreviewContent(allocator, source.html, page.description);
        defer allocator.free(content);
        try writeOne(io, allocator, output_root, &seen, .{
            .href = page.route,
            .title = page.title,
            .content_html = content,
            .class_name = "link-preview--article",
            .site_name = "plosca.ru",
            .date = page.date,
        });
        count += 1;
    }

    count += try writeExternal(io, allocator, output_root, &seen);

    var resume_file = try cwd.openFile(io, "assets/resume.pdf", .{});
    defer resume_file.close(io);
    const resume_stat = try resume_file.stat(io);
    const resume_content = try paragraph(allocator, site.resume_preview.summary);
    defer allocator.free(resume_content);
    try writeOne(io, allocator, output_root, &seen, .{
        .href = site.resume_preview.href,
        .title = site.resume_preview.title,
        .content_html = resume_content,
        .class_name = "link-preview--pdf",
        .site_name = "plosca.ru",
        .image = site.resume_preview.image,
        .image_width = site.resume_preview.width,
        .image_height = site.resume_preview.height,
        .file_size = @intCast(resume_stat.size),
        .pdf = true,
    });
    return count + 1;
}

fn writeExternal(
    io: Io,
    allocator: std.mem.Allocator,
    output_root: []const u8,
    seen: *std.AutoHashMap([16]u8, []const u8),
) !usize {
    const data = try Io.Dir.cwd().readFileAlloc(io, "content/link-context.json", allocator, .limited(max_file_size));
    defer allocator.free(data);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidLinkContext;
    const links = parsed.value.object.get("links") orelse return error.InvalidLinkContext;
    if (links != .object) return error.InvalidLinkContext;

    var count: usize = 0;
    var iterator = links.object.iterator();
    while (iterator.next()) |entry| {
        const href = entry.key_ptr.*;
        const context = entry.value_ptr.*;
        if (context != .object) return error.InvalidLinkContext;
        const status = jsonString(context, "status") orelse return error.InvalidLinkContext;
        if (!std.mem.eql(u8, status, "ok") and !std.mem.eql(u8, status, "manual")) continue;
        const title = jsonString(context, "title") orelse return error.InvalidLinkContext;
        const summary = jsonString(context, "summary") orelse return error.InvalidLinkContext;
        const kind = jsonString(context, "kind") orelse "generic";
        const site_name = jsonString(context, "site_name") orelse displayHost(href) orelse href;
        const content = if (std.mem.eql(u8, kind, "wikipedia"))
            try wikipediaContent(allocator, summary)
        else
            try paragraph(allocator, summary);
        defer allocator.free(content);
        const archive_hash = render.shortHash(href);
        const archive = try std.fmt.allocPrint(allocator, "/archive/{s}.html", .{&archive_hash});
        defer allocator.free(archive);
        try writeOne(io, allocator, output_root, seen, .{
            .href = href,
            .title = title,
            .content_html = content,
            .class_name = if (std.mem.eql(u8, kind, "wikipedia")) "link-preview--wikipedia" else null,
            .site_name = site_name,
            .archive = archive,
        });
        count += 1;
    }
    return count;
}

fn writeOne(
    io: Io,
    allocator: std.mem.Allocator,
    output_root: []const u8,
    seen: *std.AutoHashMap([16]u8, []const u8),
    preview: Preview,
) !void {
    const key = render.shortHash(preview.href);
    if (seen.get(key)) |existing| {
        if (!std.mem.eql(u8, existing, preview.href)) return error.PreviewHashCollision;
        return error.DuplicatePreview;
    }
    try seen.put(key, preview.href);

    const html = try renderPreview(allocator, preview);
    defer allocator.free(html);
    const path = try std.fmt.allocPrint(allocator, "{s}/previews/{s}.html", .{ output_root, &key });
    defer allocator.free(path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = html });
}

fn renderPreview(allocator: std.mem.Allocator, preview: Preview) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "<aside id=\"link-preview\" class=\"link-preview");
    if (preview.class_name) |class_name| {
        try out.append(allocator, ' ');
        try out.appendSlice(allocator, class_name);
    }
    try out.appendSlice(allocator, "\" role=\"status\" data-preview-href=\"");
    try render.appendAttributeEscaped(allocator, &out, preview.href);
    try out.appendSlice(allocator, "\">\n  <div class=\"link-preview__header\"><div class=\"link-preview__title-row\"><strong>");
    try render.appendHtmlEscaped(allocator, &out, preview.title);
    try out.appendSlice(allocator, "</strong><button class=\"link-preview__close\" type=\"button\" aria-label=\"Close preview\">×</button></div></div>\n  <div class=\"link-preview__body\"><div class=\"link-preview__content\">");
    try out.appendSlice(allocator, preview.content_html);
    try out.appendSlice(allocator, "</div>");
    if (preview.image) |image| {
        try out.appendSlice(allocator, "<figure class=\"link-preview__figure\"><img src=\"");
        try render.appendAttributeEscaped(allocator, &out, image);
        try out.appendSlice(allocator, "\"");
        if (preview.image_width) |width| try out.print(allocator, " width=\"{d}\"", .{width});
        if (preview.image_height) |height| try out.print(allocator, " height=\"{d}\"", .{height});
        try out.appendSlice(allocator, " alt=\"");
        try render.appendHtmlEscaped(allocator, &out, preview.title);
        try out.appendSlice(allocator, " preview\" loading=\"lazy\" decoding=\"async\"></figure>");
    }
    try out.appendSlice(allocator, "</div>\n  <small class=\"link-preview__meta\">");
    var has_meta = false;
    if (preview.site_name) |site_name| {
        try render.appendHtmlEscaped(allocator, &out, site_name);
        has_meta = true;
    }
    if (preview.date) |date| {
        try appendSeparator(allocator, &out, has_meta);
        try appendDate(allocator, &out, date);
        has_meta = true;
    }
    if (preview.file_size) |size| {
        try appendSeparator(allocator, &out, has_meta);
        try appendFileSize(allocator, &out, size);
        has_meta = true;
    }
    if (preview.archive) |archive| {
        try appendSeparator(allocator, &out, has_meta);
        try out.appendSlice(allocator, "<a href=\"");
        try render.appendAttributeEscaped(allocator, &out, archive);
        try out.appendSlice(allocator, "\">archive record</a>");
        has_meta = true;
    }
    if (preview.pdf) {
        try appendSeparator(allocator, &out, has_meta);
        try out.appendSlice(allocator, "<a href=\"");
        try render.appendAttributeEscaped(allocator, &out, preview.href);
        try out.appendSlice(allocator, "\">open PDF</a>");
    }
    try out.appendSlice(allocator, "</small>\n</aside>\n");
    return out.toOwnedSlice(allocator);
}

fn internalPreviewContent(allocator: std.mem.Allocator, html: []const u8, fallback: []const u8) ![]u8 {
    const body = skipLeadingToc(internalPageBody(html));
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var search_pos: usize = 0;
    var block_count: usize = 0;
    while (std.mem.indexOfPos(u8, body, search_pos, "<p")) |block_start| {
        const tag_end = std.mem.indexOfScalarPos(u8, body, block_start, '>') orelse break;
        const tag = body[block_start..tag_end];
        if (std.mem.indexOf(u8, tag, "class=\"date\"") != null) {
            search_pos = tag_end + 1;
            continue;
        }
        const close = findClosingTag(body, tag_end + 1, "p") orelse break;
        const passive = try stripPreviewAttributes(allocator, body[block_start..close.end]);
        defer allocator.free(passive);
        if (!hasReadableText(passive)) {
            search_pos = close.end;
            continue;
        }
        if (out.items.len + passive.len > preview_html_limit and out.items.len != 0) break;
        try out.appendSlice(allocator, passive);
        try out.append(allocator, '\n');
        block_count += 1;
        search_pos = close.end;
        if (out.items.len >= preview_html_limit or block_count >= 5) break;
    }
    if (out.items.len != 0) return out.toOwnedSlice(allocator);
    out.deinit(allocator);
    return paragraph(allocator, fallback);
}

fn internalPageBody(html: []const u8) []const u8 {
    var body = extractElement(html, "article") orelse html;
    if (std.mem.indexOf(u8, body, "</header>")) |header_end| body = body[header_end + "</header>".len ..];
    const boundaries = [_][]const u8{
        "<section class=\"article-links\"",
        "<!-- generated:connections:start -->",
        "<section class=\"article-generated\"",
    };
    for (boundaries) |needle| {
        if (std.mem.indexOf(u8, body, needle)) |position| body = body[0..position];
    }
    return body;
}

fn skipLeadingToc(html: []const u8) []const u8 {
    if (std.mem.indexOf(u8, html, "<nav id=\"TOC\"")) |start| {
        if (std.mem.indexOfPos(u8, html, start, "</nav>")) |end| {
            if (std.mem.trim(u8, html[0..start], " \t\r\n").len == 0) return html[end + "</nav>".len ..];
        }
    }
    return html;
}

fn stripPreviewAttributes(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var cursor: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<a")) |anchor_start| {
        const tag_end = std.mem.indexOfScalarPos(u8, html, anchor_start, '>') orelse break;
        const tag = html[anchor_start..tag_end];
        const generated_start = std.mem.indexOf(u8, tag, " data-previewable") orelse {
            search_pos = tag_end + 1;
            continue;
        };
        try out.appendSlice(allocator, html[cursor..anchor_start]);
        try out.appendSlice(allocator, tag[0..generated_start]);
        try out.append(allocator, '>');
        cursor = tag_end + 1;
        search_pos = tag_end + 1;
    }
    try out.appendSlice(allocator, html[cursor..]);
    return out.toOwnedSlice(allocator);
}

fn hasReadableText(html: []const u8) bool {
    var inside_tag = false;
    for (html) |byte| {
        if (byte == '<') {
            inside_tag = true;
            continue;
        }
        if (byte == '>') {
            inside_tag = false;
            continue;
        }
        if (!inside_tag and !std.ascii.isWhitespace(byte) and byte != '&' and byte != ';') return true;
    }
    return false;
}

fn wikipediaContent(allocator: std.mem.Allocator, summary: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var cursor: usize = 0;
    var count: usize = 0;
    while (cursor < summary.len and count < 3) {
        while (cursor < summary.len and std.ascii.isWhitespace(summary[cursor])) : (cursor += 1) {}
        if (cursor >= summary.len) break;
        const remaining = summary[cursor..];
        const end = sentenceBoundary(remaining) orelse remaining.len;
        const sentence = std.mem.trim(u8, remaining[0..end], " \t\r\n");
        if (sentence.len != 0) {
            try out.appendSlice(allocator, "<p");
            if (count == 0) try out.appendSlice(allocator, " data-preview-lede=\"true\"");
            try out.append(allocator, '>');
            try render.appendHtmlEscaped(allocator, &out, sentence);
            try out.appendSlice(allocator, "</p>\n");
            count += 1;
        }
        cursor += end;
    }
    return out.toOwnedSlice(allocator);
}

fn paragraph(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "<p>");
    try render.appendHtmlEscaped(allocator, &out, text);
    try out.appendSlice(allocator, "</p>");
    return out.toOwnedSlice(allocator);
}

fn sentenceBoundary(text: []const u8) ?usize {
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        if (text[index] != '.' and text[index] != '!' and text[index] != '?') continue;
        if (index >= 2 and text[index - 2] == '.' and std.ascii.isUpper(text[index - 1])) continue;
        const after = index + 1;
        if (after >= text.len or std.ascii.isWhitespace(text[after])) return after;
    }
    return null;
}

fn appendSeparator(allocator: std.mem.Allocator, out: *std.ArrayList(u8), needed: bool) !void {
    if (needed) try out.appendSlice(allocator, " · ");
}

fn appendDate(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    if (value.len != 10 or value[4] != '-' or value[7] != '-') return render.appendHtmlEscaped(allocator, out, value);
    const month_number = std.fmt.parseUnsigned(u8, value[5..7], 10) catch return render.appendHtmlEscaped(allocator, out, value);
    const day = std.fmt.parseUnsigned(u8, value[8..10], 10) catch return render.appendHtmlEscaped(allocator, out, value);
    const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    if (month_number == 0 or month_number > months.len) return render.appendHtmlEscaped(allocator, out, value);
    try out.print(allocator, "{d} {s} {s}", .{ day, months[month_number - 1], value[0..4] });
}

fn appendFileSize(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: usize) !void {
    if (value < 1024) return out.print(allocator, "{d} B", .{value});
    const kilobytes = @as(f64, @floatFromInt(value)) / 1024.0;
    if (kilobytes < 1024.0) return out.print(allocator, "{d:.0} KB", .{kilobytes});
    try out.print(allocator, "{d:.1} MB", .{kilobytes / 1024.0});
}

fn sourceFor(sources: []const graph.Source, slug: []const u8) ?graph.Source {
    for (sources) |source| if (std.mem.eql(u8, source.page.slug, slug)) return source;
    return null;
}

fn jsonString(value: std.json.Value, field: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const child = value.object.get(field) orelse return null;
    if (child != .string) return null;
    return child.string;
}

fn displayHost(url: []const u8) ?[]const u8 {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    var start = scheme_end + "://".len;
    if (std.mem.startsWith(u8, url[start..], "www.")) start += "www.".len;
    var end = start;
    while (end < url.len and url[end] != '/' and url[end] != '?' and url[end] != '#') : (end += 1) {}
    return if (end == start) null else url[start..end];
}

fn extractElement(html: []const u8, tag_name: []const u8) ?[]const u8 {
    var open_buf: [32]u8 = undefined;
    const open = std.fmt.bufPrint(&open_buf, "<{s}", .{tag_name}) catch return null;
    const start = std.mem.indexOf(u8, html, open) orelse return null;
    const open_end = std.mem.indexOfScalarPos(u8, html, start, '>') orelse return null;
    var close_buf: [32]u8 = undefined;
    const close = std.fmt.bufPrint(&close_buf, "</{s}>", .{tag_name}) catch return null;
    const end = std.mem.indexOfPos(u8, html, open_end + 1, close) orelse return null;
    return html[open_end + 1 .. end];
}

const ClosingTag = struct { start: usize, end: usize };

fn findClosingTag(html: []const u8, start: usize, tag_name: []const u8) ?ClosingTag {
    var needle_buf: [32]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buf, "</{s}", .{tag_name}) catch return null;
    var search_pos = start;
    while (std.mem.indexOfPos(u8, html, search_pos, needle)) |close_start| {
        const after_name = close_start + needle.len;
        if (after_name >= html.len) return null;
        if (html[after_name] != '>' and !std.ascii.isWhitespace(html[after_name])) {
            search_pos = after_name;
            continue;
        }
        const close_end = std.mem.indexOfScalarPos(u8, html, after_name, '>') orelse return null;
        return .{ .start = close_start, .end = close_end + 1 };
    }
    return null;
}
