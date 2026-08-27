const std = @import("std");
const manifest = @import("manifest");

pub const Source = struct {
    page: manifest.Page,
    html: []const u8,
};

pub const Link = struct {
    href: []const u8,
    title: []const u8,
    description: ?[]const u8 = null,
};

pub const Connections = struct {
    related: []Link,
    backlinks: []Link,
    similar: []Link,

    pub fn deinit(self: Connections, allocator: std.mem.Allocator) void {
        allocator.free(self.related);
        allocator.free(self.backlinks);
        allocator.free(self.similar);
    }
};

pub fn build(
    allocator: std.mem.Allocator,
    page: manifest.Page,
    pages: []const manifest.Page,
    sources: []const Source,
) !Connections {
    var related: std.ArrayList(Link) = .empty;
    errdefer related.deinit(allocator);
    var backlinks: std.ArrayList(Link) = .empty;
    errdefer backlinks.deinit(allocator);
    var similar: std.ArrayList(Link) = .empty;
    errdefer similar.deinit(allocator);

    for (page.related) |route| {
        if (manifest.byRoute(pages, route)) |target| {
            try related.append(allocator, linkFor(target));
        } else {
            try related.append(allocator, .{ .href = route, .title = route });
        }
    }

    for (sources) |source| {
        if (source.page.kind == .error_page or std.mem.eql(u8, source.page.slug, page.slug)) continue;
        if (try linksTo(source.html, page.route)) try backlinks.append(allocator, linkFor(source.page));
    }

    for (pages) |candidate| {
        if (candidate.kind == .error_page or std.mem.eql(u8, candidate.slug, page.slug)) continue;
        if (similarityScore(page, candidate) != 0) try similar.append(allocator, linkFor(candidate));
    }

    return .{
        .related = try related.toOwnedSlice(allocator),
        .backlinks = try backlinks.toOwnedSlice(allocator),
        .similar = try similar.toOwnedSlice(allocator),
    };
}

fn linkFor(page: manifest.Page) Link {
    return .{
        .href = page.route,
        .title = page.title,
        .description = page.description,
    };
}

fn similarityScore(a: manifest.Page, b: manifest.Page) usize {
    var score: usize = 0;
    for (a.tags) |tag_a| {
        for (b.tags) |tag_b| {
            if (std.mem.eql(u8, tag_a, tag_b)) score += 1;
        }
    }
    for (a.related) |route| {
        if (std.mem.eql(u8, route, b.route)) score += 2;
    }
    for (b.related) |route| {
        if (std.mem.eql(u8, route, a.route)) score += 1;
    }
    return score;
}

fn linksTo(html: []const u8, target_route: []const u8) !bool {
    const body = extractElement(html, "main") orelse html;
    const authored = if (std.mem.indexOf(u8, body, "<!-- generated:connections:start -->")) |marker|
        body[0..marker]
    else
        body;

    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, authored, search_pos, "href=")) |href_pos| {
        const quote_pos = href_pos + "href=".len;
        if (quote_pos >= authored.len) break;
        const quote = authored[quote_pos];
        if (quote != '"' and quote != '\'') {
            search_pos = quote_pos + 1;
            continue;
        }
        const value_start = quote_pos + 1;
        const value_end = std.mem.indexOfScalarPos(u8, authored, value_start, quote) orelse return error.InvalidHtml;
        if (std.mem.eql(u8, manifest.normalizedRoute(authored[value_start..value_end]), target_route)) return true;
        search_pos = value_end + 1;
    }
    return false;
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

test "similarity includes explicit and reciprocal relationships" {
    const tags_a = [_][]const u8{"one"};
    const tags_b = [_][]const u8{"two"};
    const related_a = [_][]const u8{"/b"};
    const related_b = [_][]const u8{"/a"};
    const a: manifest.Page = .{ .slug = "a", .route = "/a", .file = "a.html", .title = "A", .description = "A", .tags = &tags_a, .related = &related_a, .kind = .article };
    const b: manifest.Page = .{ .slug = "b", .route = "/b", .file = "b.html", .title = "B", .description = "B", .tags = &tags_b, .related = &related_b, .kind = .article };
    try std.testing.expectEqual(@as(usize, 3), similarityScore(a, b));
}
