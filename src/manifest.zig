const std = @import("std");

pub const PageKind = enum {
    home,
    article,
    profile,
    prose,
    error_page,
};

pub const Page = struct {
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

pub const ResumePreview = struct {
    href: []const u8,
    title: []const u8,
    summary: []const u8,
    image: []const u8,
    width: usize,
    height: usize,
};

pub const Site = struct {
    origin: []const u8,
    resume_preview: ResumePreview,
};

pub fn byRoute(pages: []const Page, raw: []const u8) ?Page {
    const route = normalizedRoute(raw);
    for (pages) |page| {
        if (std.mem.eql(u8, page.route, route)) return page;
    }
    return null;
}

pub fn normalizedRoute(raw: []const u8) []const u8 {
    var value = raw;
    if (std.mem.indexOfAny(u8, value, "?#")) |index| value = value[0..index];
    if (std.mem.endsWith(u8, value, ".html")) value = value[0 .. value.len - ".html".len];
    if (std.mem.eql(u8, value, "/index")) return "/";
    return value;
}

test "route normalization retains the public route contract" {
    try std.testing.expectEqualStrings("/", normalizedRoute("/index.html?x=1"));
    try std.testing.expectEqualStrings("/about", normalizedRoute("/about.html#work"));
}
