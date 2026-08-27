const std = @import("std");
const graph = @import("graph.zig");

const connections_start = "<!-- generated:connections:start -->";
const connections_end = "<!-- generated:connections:end -->";

pub const AssetUrls = struct {
    style: []const u8,
    theme: []const u8,
    preview: []const u8,
    code: []const u8,
};

pub fn page(
    allocator: std.mem.Allocator,
    authored: []const u8,
    connections: ?graph.Connections,
    asset_urls: AssetUrls,
) ![]u8 {
    const with_connections = if (connections) |value|
        try replaceConnections(allocator, authored, value)
    else
        try allocator.dupe(u8, authored);
    defer allocator.free(with_connections);
    return replaceAssetMarkers(allocator, with_connections, asset_urls);
}

pub fn archivePage(allocator: std.mem.Allocator, authored: []const u8, asset_urls: AssetUrls) ![]u8 {
    return replaceAssetMarkers(allocator, authored, asset_urls);
}

pub fn renderConnections(allocator: std.mem.Allocator, connections: graph.Connections) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "<div class=\"generated-connections\">\n");
    try appendSection(allocator, &out, "generated-related", "Related", "Pages explicitly connected to this page.", "No related pages yet.", connections.related);
    try appendSection(allocator, &out, "generated-backlinks", "Backlinks", "Local pages that link here.", "No local backlinks yet.", connections.backlinks);
    try appendSection(allocator, &out, "generated-similar", "Similar", "Small tag-based suggestions from the local manifest.", "No similar local pages yet.", connections.similar);
    try out.appendSlice(allocator, "</div>\n");
    return out.toOwnedSlice(allocator);
}

fn replaceConnections(allocator: std.mem.Allocator, authored: []const u8, connections: graph.Connections) ![]u8 {
    const start = std.mem.indexOf(u8, authored, connections_start) orelse return error.MissingConnectionsMarker;
    if (std.mem.indexOfPos(u8, authored, start + connections_start.len, connections_start) != null) return error.DuplicateConnectionsMarker;
    const body_start = start + connections_start.len;
    const end = std.mem.indexOfPos(u8, authored, body_start, connections_end) orelse return error.MissingConnectionsMarker;
    if (std.mem.indexOfPos(u8, authored, end + connections_end.len, connections_end) != null) return error.DuplicateConnectionsMarker;

    const generated = try renderConnections(allocator, connections);
    defer allocator.free(generated);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, authored[0..body_start]);
    try out.append(allocator, '\n');
    try out.appendSlice(allocator, generated);
    try out.appendSlice(allocator, authored[end..]);
    return out.toOwnedSlice(allocator);
}

fn replaceAssetMarkers(allocator: std.mem.Allocator, input: []const u8, urls: AssetUrls) ![]u8 {
    const replacements = [_]struct { marker: []const u8, value: []const u8 }{
        .{ .marker = "{{asset:style.css}}", .value = urls.style },
        .{ .marker = "{{asset:theme.js}}", .value = urls.theme },
        .{ .marker = "{{asset:preview.js}}", .value = urls.preview },
        .{ .marker = "{{asset:code.js}}", .value = urls.code },
    };

    var current = try allocator.dupe(u8, input);
    errdefer allocator.free(current);
    for (replacements) |replacement| {
        const next = try replaceAll(allocator, current, replacement.marker, replacement.value);
        allocator.free(current);
        current = next;
    }
    if (std.mem.indexOf(u8, current, "{{asset:") != null) return error.UnknownAssetMarker;
    return current;
}

fn replaceAll(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, cursor, needle)) |position| {
        try out.appendSlice(allocator, input[cursor..position]);
        try out.appendSlice(allocator, replacement);
        cursor = position + needle.len;
    }
    try out.appendSlice(allocator, input[cursor..]);
    return out.toOwnedSlice(allocator);
}

fn appendSection(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    class_name: []const u8,
    heading: []const u8,
    intro: []const u8,
    empty_text: []const u8,
    links: []const graph.Link,
) !void {
    try out.appendSlice(allocator, "<section class=\"generated-section ");
    try out.appendSlice(allocator, class_name);
    try out.appendSlice(allocator, "\">\n  <h3>");
    try appendHtmlEscaped(allocator, out, heading);
    try out.appendSlice(allocator, "</h3>\n  <p>");
    try appendHtmlEscaped(allocator, out, intro);
    try out.appendSlice(allocator, "</p>\n  <ul>\n");
    if (links.len == 0) {
        try out.appendSlice(allocator, "    <li><span>");
        try appendHtmlEscaped(allocator, out, empty_text);
        try out.appendSlice(allocator, "</span></li>\n");
    } else {
        for (links) |link| {
            const preview_key = shortHash(link.href);
            try out.appendSlice(allocator, "    <li><a href=\"");
            try appendAttributeEscaped(allocator, out, link.href);
            try out.appendSlice(allocator, "\" data-previewable data-preview-src=\"/previews/");
            try out.appendSlice(allocator, &preview_key);
            try out.appendSlice(allocator, ".html\">");
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

pub fn appendHtmlEscaped(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    for (value) |byte| {
        switch (byte) {
            '&' => try out.appendSlice(allocator, "&amp;"),
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            '"' => try out.appendSlice(allocator, "&quot;"),
            '\'' => try out.appendSlice(allocator, "&#39;"),
            else => try out.append(allocator, byte),
        }
    }
}

pub fn appendAttributeEscaped(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    if (std.mem.startsWith(u8, value, "javascript:") or std.mem.startsWith(u8, value, "data:")) return error.UnsafeUrl;
    return appendHtmlEscaped(allocator, out, value);
}

pub fn shortHash(value: []const u8) [16]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(value);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);
    return firstEightHex(digest);
}

pub fn contentHash(value: []const u8) [16]u8 {
    return shortHash(value);
}

fn firstEightHex(digest: [std.crypto.hash.sha2.Sha256.digest_length]u8) [16]u8 {
    const hex = "0123456789abcdef";
    var out: [16]u8 = undefined;
    for (digest[0..8], 0..) |byte, index| {
        out[index * 2] = hex[byte >> 4];
        out[index * 2 + 1] = hex[byte & 0x0f];
    }
    return out;
}

test "connections escape text and use direct preview URLs" {
    const links = [_]graph.Link{.{ .href = "/a?x=<&", .title = "<script>", .description = "A & B" }};
    const rendered = try renderConnections(std.testing.allocator, .{ .related = &links, .backlinks = &.{}, .similar = &.{} });
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "<script>") == null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "data-preview-src=\"/previews/") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "hx-") == null);
}
