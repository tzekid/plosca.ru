pub const PageKind = enum {
    home,
    article,
    profile,
    prose,
    error_page,
};

pub const PageMeta = struct {
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

pub const LinkView = struct {
    href: []const u8,
    title: []const u8,
    description: ?[]const u8 = null,
    preview_key: ?[16]u8 = null,
};

pub const SectionKind = enum {
    related,
    backlinks,
    similar,

    pub fn className(self: SectionKind) []const u8 {
        return switch (self) {
            .related => "generated-related",
            .backlinks => "generated-backlinks",
            .similar => "generated-similar",
        };
    }
};

pub const PageListView = struct {
    kind: SectionKind,
    heading: []const u8,
    intro: []const u8,
    empty_text: []const u8,
    links: []const LinkView,
};

pub const ConnectionsView = struct {
    related: PageListView,
    backlinks: PageListView,
    similar: PageListView,
};

pub const Annotation = struct {
    href: []const u8,
    text: []const u8,
    kind: []const u8,
    source: []const u8,
    source_title: []const u8,
    title: []const u8,
    summary: []const u8,
    preview_html: ?[]const u8 = null,
    date: ?[]const u8 = null,
    site_name: ?[]const u8 = null,
    context_kind: ?[]const u8 = null,
    canonical_url: ?[]const u8 = null,
    archive: ?[]const u8 = null,
    file_size: ?usize = null,
    preview_image: ?[]const u8 = null,
    preview_width: ?usize = null,
    preview_height: ?usize = null,
};

pub const Representation = enum {
    full_page,
    fragment,
};

/// One immutable context is constructed before rendering begins. Public pages
/// use the default context; future authenticated routes can add viewer state
/// here without teaching component renderers about cookies or HTTP.
pub const RenderContext = struct {
    representation: Representation,
    locale: []const u8 = "en",
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

pub const pages = [_]PageMeta{
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

pub fn byRoute(raw: []const u8) ?PageMeta {
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

const std = @import("std");
