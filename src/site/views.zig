const std = @import("std");
const model = @import("site_model");
const web_html = @import("web_html");

pub fn renderPageList(allocator: std.mem.Allocator, view: model.PageListView) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendPageList(allocator, &out, view);
    return out.toOwnedSlice(allocator);
}

pub fn renderConnections(allocator: std.mem.Allocator, view: model.ConnectionsView) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "<div class=\"generated-connections\">\n");
    try appendPageList(allocator, &out, view.related);
    try appendPageList(allocator, &out, view.backlinks);
    try appendPageList(allocator, &out, view.similar);
    try out.appendSlice(allocator, "</div>\n");
    return out.toOwnedSlice(allocator);
}

pub fn renderPreview(allocator: std.mem.Allocator, annotation: model.Annotation) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "<aside id=\"link-preview\" class=\"link-preview");
    if (std.mem.eql(u8, annotation.kind, "internal")) try out.appendSlice(allocator, " link-preview--article");
    if (annotation.context_kind) |kind| {
        if (std.mem.eql(u8, kind, "wikipedia")) try out.appendSlice(allocator, " link-preview--wikipedia");
        if (std.mem.eql(u8, kind, "pdf")) try out.appendSlice(allocator, " link-preview--pdf");
    }
    try out.appendSlice(allocator, "\" role=\"status\" data-preview-href=\"");
    try appendUrlAttribute(allocator, &out, annotation.href);
    try out.appendSlice(allocator, "\">\n");
    try out.appendSlice(allocator, "  <div class=\"link-preview__header\"><div class=\"link-preview__title-row\"><strong>");
    try appendHtmlEscaped(allocator, &out, annotation.title);
    try out.appendSlice(allocator, "</strong><button class=\"link-preview__close\" type=\"button\" aria-label=\"Close preview\">×</button></div></div>\n");
    try out.appendSlice(allocator, "  <div class=\"link-preview__body\"><div class=\"link-preview__content\">");
    if (annotation.preview_html) |preview_html| {
        try appendTrustedHtml(allocator, &out, preview_html);
    } else {
        try out.appendSlice(allocator, "<p>");
        try appendHtmlEscaped(allocator, &out, annotation.summary);
        try out.appendSlice(allocator, "</p>");
    }
    try out.appendSlice(allocator, "</div>");

    if (annotation.preview_image) |image| {
        try out.appendSlice(allocator, "<figure class=\"link-preview__figure\"><img src=\"");
        try appendUrlAttribute(allocator, &out, image);
        try out.appendSlice(allocator, "\"");
        if (annotation.preview_width) |width| try out.print(allocator, " width=\"{d}\"", .{width});
        if (annotation.preview_height) |height| try out.print(allocator, " height=\"{d}\"", .{height});
        try out.appendSlice(allocator, " alt=\"");
        try appendHtmlEscaped(allocator, &out, annotation.title);
        try out.appendSlice(allocator, " preview\" loading=\"lazy\" decoding=\"async\"></figure>");
    }
    try out.appendSlice(allocator, "</div>\n  <small class=\"link-preview__meta\">");

    var has_meta = false;
    if (annotation.site_name orelse annotation.context_kind) |source| {
        try appendHtmlEscaped(allocator, &out, source);
        has_meta = true;
    }
    if (annotation.date) |date| {
        try appendMetaSeparator(allocator, &out, has_meta);
        try appendFormattedDate(allocator, &out, date);
        has_meta = true;
    }
    if (annotation.file_size) |size| {
        try appendMetaSeparator(allocator, &out, has_meta);
        try appendFormattedBytes(allocator, &out, size);
        has_meta = true;
    }
    if (annotation.archive) |archive| {
        try appendMetaSeparator(allocator, &out, has_meta);
        try out.appendSlice(allocator, "<a href=\"");
        try appendUrlAttribute(allocator, &out, archive);
        try out.appendSlice(allocator, "\">archive record</a>");
        has_meta = true;
    }
    if (std.mem.eql(u8, annotation.kind, "pdf")) {
        try appendMetaSeparator(allocator, &out, has_meta);
        try out.appendSlice(allocator, "<a href=\"");
        try appendUrlAttribute(allocator, &out, annotation.href);
        try out.appendSlice(allocator, "\">open PDF</a>");
    }
    try out.appendSlice(allocator, "</small>\n</aside>\n");
    return out.toOwnedSlice(allocator);
}

pub fn appendHtmlEscaped(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    value: []const u8,
) !void {
    var writer = std.Io.Writer.Allocating.fromArrayList(allocator, out);
    defer out.* = writer.toArrayList();
    try web_html.text(&writer.writer, value);
}

fn appendUrlAttribute(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    value: []const u8,
) !void {
    var writer = std.Io.Writer.Allocating.fromArrayList(allocator, out);
    defer out.* = writer.toArrayList();
    try web_html.urlAttribute(&writer.writer, value);
}

fn appendTrustedHtml(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    value: []const u8,
) !void {
    var writer = std.Io.Writer.Allocating.fromArrayList(allocator, out);
    defer out.* = writer.toArrayList();
    try web_html.trusted(&writer.writer, .audited(value));
}

fn appendPageList(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    view: model.PageListView,
) !void {
    try out.appendSlice(allocator, "<section class=\"generated-section ");
    try out.appendSlice(allocator, view.kind.className());
    try out.appendSlice(allocator, "\">\n  <h3>");
    try appendHtmlEscaped(allocator, out, view.heading);
    try out.appendSlice(allocator, "</h3>\n  <p>");
    try appendHtmlEscaped(allocator, out, view.intro);
    try out.appendSlice(allocator, "</p>\n  <ul>\n");

    if (view.links.len == 0) {
        try out.appendSlice(allocator, "    <li><span>");
        try appendHtmlEscaped(allocator, out, view.empty_text);
        try out.appendSlice(allocator, "</span></li>\n");
    } else {
        for (view.links) |link| {
            try out.appendSlice(allocator, "    <li><a href=\"");
            try appendUrlAttribute(allocator, out, link.href);
            try out.appendSlice(allocator, "\"");
            if (link.preview_key) |key| {
                try out.appendSlice(allocator, " data-previewable=\"true\" hx-get=\"/metadata/previews/");
                try out.appendSlice(allocator, key[0..]);
                try out.appendSlice(allocator, ".html\" hx-trigger=\"preview:request\" hx-target=\"#link-preview\" hx-swap=\"outerSync\" hx-sync=\"#link-preview:replace\"");
            }
            try out.appendSlice(allocator, ">");
            try appendHtmlEscaped(allocator, out, link.title);
            try out.appendSlice(allocator, "</a>");
            if (link.description) |description| {
                try out.appendSlice(allocator, "<span>");
                try appendHtmlEscaped(allocator, out, description);
                try out.appendSlice(allocator, "</span>");
            }
            try out.appendSlice(allocator, "</li>\n");
        }
    }
    try out.appendSlice(allocator, "  </ul>\n</section>\n");
}

fn appendMetaSeparator(allocator: std.mem.Allocator, out: *std.ArrayList(u8), needed: bool) !void {
    if (needed) try out.appendSlice(allocator, " · ");
}

fn appendFormattedDate(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    if (value.len != 10 or value[4] != '-' or value[7] != '-') {
        return appendHtmlEscaped(allocator, out, value);
    }
    const month_number = std.fmt.parseUnsigned(u8, value[5..7], 10) catch {
        return appendHtmlEscaped(allocator, out, value);
    };
    const months = [_][]const u8{
        "January", "February", "March",     "April",   "May",      "June",
        "July",    "August",   "September", "October", "November", "December",
    };
    if (month_number == 0 or month_number > months.len) return appendHtmlEscaped(allocator, out, value);
    const day = std.fmt.parseUnsigned(u8, value[8..10], 10) catch {
        return appendHtmlEscaped(allocator, out, value);
    };
    try out.print(allocator, "{d} {s} {s}", .{ day, months[month_number - 1], value[0..4] });
}

fn appendFormattedBytes(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: usize) !void {
    if (value < 1024) return out.print(allocator, "{d} B", .{value});
    const units = [_][]const u8{ "KB", "MB", "GB" };
    var scaled = @as(f64, @floatFromInt(value)) / 1024.0;
    var unit_index: usize = 0;
    while (scaled >= 1024.0 and unit_index + 1 < units.len) : (unit_index += 1) scaled /= 1024.0;
    if (scaled >= 10.0 or unit_index == 0) {
        try out.print(allocator, "{d:.0} {s}", .{ scaled, units[unit_index] });
    } else {
        try out.print(allocator, "{d:.1} {s}", .{ scaled, units[unit_index] });
    }
}

test "connection views escape every text and attribute context" {
    const links = [_]model.LinkView{.{
        .href = "/a?x=\"<&",
        .title = "<script>",
        .description = "A & B",
    }};
    const section: model.PageListView = .{
        .kind = .related,
        .heading = "Related <",
        .intro = "A & B",
        .empty_text = "none",
        .links = &links,
    };
    const rendered = try renderConnections(std.testing.allocator, .{
        .related = section,
        .backlinks = section,
        .similar = section,
    });
    defer std.testing.allocator.free(rendered);

    try std.testing.expect(std.mem.indexOf(u8, rendered, "<script>") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "href=\"/a?x=&quot;&lt;&amp;\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "A &amp; B") != null);
}

test "connection views reject executable link schemes" {
    const links = [_]model.LinkView{.{
        .href = "javascript:alert(1)",
        .title = "unsafe",
    }};
    const section: model.PageListView = .{
        .kind = .related,
        .heading = "Related",
        .intro = "Links",
        .empty_text = "none",
        .links = &links,
    };
    try std.testing.expectError(error.UnsafeUrl, renderConnections(std.testing.allocator, .{
        .related = section,
        .backlinks = section,
        .similar = section,
    }));
}
