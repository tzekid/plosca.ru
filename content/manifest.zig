const manifest = @import("manifest");

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

pub const site: manifest.Site = .{
    .origin = "https://plosca.ru",
    .resume_preview = .{
        .href = "/resume.pdf",
        .title = "Resume PDF",
        .summary = "One-page resume PDF for Mircea Ilie Ploscaru, focused on full-stack development, data engineering, BI, and automation.",
        .image = "/resume-preview-27833c1a5937f8c5.jpg",
        .width = 760,
        .height = 1075,
    },
};

pub const pages = [_]manifest.Page{
    .{
        .slug = "home",
        .route = "/",
        .file = "index.html",
        .title = "Ilie Ploscaru",
        .description = "Personal site of Ilie Ploscaru, interested in psychology and tech.",
        .date = "2019-01-01",
        .updated = "2026-06-14",
        .tags = &home_tags,
        .related = &home_related,
        .kind = .home,
    },
    .{
        .slug = "about",
        .route = "/about",
        .file = "about.html",
        .title = "About",
        .description = "About Ilie Ploscaru: full-stack developer and data engineer focused on data platforms, BI, and automation.",
        .updated = "2026-06-14",
        .tags = &about_tags,
        .related = &about_related,
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
        .tags = &hello_tags,
        .related = &hello_related,
        .kind = .article,
    },
    .{
        .slug = "prose",
        .route = "/prose",
        .file = "prose.html",
        .title = "Prose",
        .description = "Prose by Ilie Ploscaru: old poems, essays, thoughts, and writing samples.",
        .updated = "2026-06-14",
        .tags = &prose_tags,
        .related = &prose_related,
        .kind = .prose,
    },
    .{
        .slug = "404",
        .route = "/404",
        .file = "404.html",
        .title = "Page not found | Ilie Ploscaru",
        .description = "The requested page was not found. Return to the main pages on plosca.ru.",
        .updated = "2026-06-14",
        .tags = &error_tags,
        .related = &error_related,
        .kind = .error_page,
    },
};
