const std = @import("std");

const Io = std.Io;

const source_css_path = "src/styles/site.css";
const generated_css_path = "static/style.css";
const theme_js_path = "static/theme.js";
const site_features_js_path = "static/site-features.js";
const link_context_path = "src/content/link_context.json";
const static_dir_path = "static";
const metadata_dir_path = "static/metadata";
const pages_json_path = "static/metadata/pages.json";
const related_dir_path = "static/metadata/related";
const backlinks_dir_path = "static/metadata/backlinks";
const similar_dir_path = "static/metadata/similar";
const connections_dir_path = "static/metadata/connections";
const annotations_json_path = "static/metadata/annotations.json";
const external_links_json_path = "static/metadata/external-links.json";
const archive_dir_path = "static/archive";
const archive_index_path = "static/archive/index.html";
const resume_pdf_href = "/resume.pdf";
const resume_pdf_path = "static/resume.pdf";
const resume_preview_prefix = "resume-preview-";
const resume_preview_ext = ".jpg";
const resume_preview_width = 760;
const max_file_size = 16 * 1024 * 1024;
const max_fetch_size = 2 * 1024 * 1024;
const link_summary_limit = 360;
const internal_summary_limit = 1000;
const wikipedia_summary_limit = 1200;
const link_title_limit = 140;
const curl_user_agent = "plosca.ru-link-enricher/1.0 (+https://plosca.ru/about)";

const CheckError = error{SiteCheckFailed};
const PdfPreviewError = error{PdfPreviewFailed};

const AssetVersions = struct {
    style: [16]u8,
    theme: [16]u8,
    site_features: [16]u8,
};

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
    } else if (std.mem.eql(u8, args[1], "enrich-links")) {
        try enrichLinks(init.io, init.gpa);
    } else if (std.mem.eql(u8, args[1], "pdf-previews")) {
        try writePdfPreviews(init.io, init.gpa);
    } else {
        usageAndExit();
    }
}

fn usageAndExit() noreturn {
    std.debug.print(
        \\Usage:
        \\  site-tool write
        \\  site-tool check
        \\  site-tool enrich-links
        \\  site-tool pdf-previews
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

    const versions = try readAssetVersions(io, gpa, css);
    const updated = try syncHtmlAssetRefs(io, gpa, versions, true);
    const artifacts = try writeGeneratedArtifacts(io, gpa, versions);
    std.debug.print(
        "asset versions style={s} theme={s} site-features={s}; updated {d} asset ref(s), enhanced {d} HTML file(s), generated {d} metadata artifact(s)\n",
        .{ versions.style[0..], versions.theme[0..], versions.site_features[0..], updated, enhanced, artifacts },
    );
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

    const versions = try readAssetVersions(io, gpa, generated_css);
    failures += try syncHtmlAssetRefs(io, gpa, versions, false);
    failures += try checkGeneratedMetadata(io, gpa);
    failures += try checkGeneratedArtifacts(io, gpa);
    failures += try auditReferences(io, gpa, generated_css);
    failures += try auditContent(io, gpa);

    if (failures != 0) return CheckError.SiteCheckFailed;
    std.debug.print("site check passed; asset versions style={s} theme={s} site-features={s}\n", .{ versions.style[0..], versions.theme[0..], versions.site_features[0..] });
}

fn readAssetVersions(io: Io, gpa: std.mem.Allocator, css: []const u8) !AssetVersions {
    const cwd = Io.Dir.cwd();
    const theme_js = try cwd.readFileAlloc(io, theme_js_path, gpa, .limited(max_file_size));
    defer gpa.free(theme_js);
    const site_features_js = try cwd.readFileAlloc(io, site_features_js_path, gpa, .limited(max_file_size));
    defer gpa.free(site_features_js);

    return .{
        .style = assetVersion(css),
        .theme = assetVersion(theme_js),
        .site_features = assetVersion(site_features_js),
    };
}

fn assetVersion(contents: []const u8) [16]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(contents);
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

const PdfPreviewInfo = struct {
    href: []u8,
    path: []u8,
    basename: []u8,
    file_size: usize,

    fn deinit(self: PdfPreviewInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.href);
        gpa.free(self.path);
        gpa.free(self.basename);
    }
};

const ImageDimensions = struct {
    width: usize,
    height: usize,
};

fn resumePdfPreviewInfo(io: Io, gpa: std.mem.Allocator) !PdfPreviewInfo {
    const pdf = try Io.Dir.cwd().readFileAlloc(io, resume_pdf_path, gpa, .limited(max_file_size));
    defer gpa.free(pdf);

    const hash = assetVersion(pdf);
    const basename = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ resume_preview_prefix, hash[0..], resume_preview_ext });
    errdefer gpa.free(basename);
    const href = try std.fmt.allocPrint(gpa, "/{s}", .{basename});
    errdefer gpa.free(href);
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ static_dir_path, basename });
    errdefer gpa.free(path);

    return .{
        .href = href,
        .path = path,
        .basename = basename,
        .file_size = pdf.len,
    };
}

fn writePdfPreviews(io: Io, gpa: std.mem.Allocator) !void {
    const preview = try resumePdfPreviewInfo(io, gpa);
    defer preview.deinit(gpa);

    try removeStaleResumePreviews(io, preview.basename);

    const prefix = try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ static_dir_path, resume_preview_prefix, preview.basename[resume_preview_prefix.len .. preview.basename.len - resume_preview_ext.len] });
    defer gpa.free(prefix);

    const argv = [_][]const u8{
        "pdftoppm",
        "-singlefile",
        "-jpeg",
        "-jpegopt",
        "quality=86,progressive=y,optimize=y",
        "-scale-to-x",
        "760",
        "-scale-to-y",
        "-1",
        resume_pdf_path,
        prefix,
    };
    const result = std.process.run(gpa, io, .{
        .argv = &argv,
        .expand_arg0 = .expand,
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("pdftoppm is required for `zig build pdf-previews`; install Poppler to regenerate {s}\n", .{preview.path});
        }
        return err;
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!ok) {
        std.debug.print("pdftoppm failed while rendering {s}:\n{s}\n", .{ resume_pdf_path, result.stderr });
        return PdfPreviewError.PdfPreviewFailed;
    }

    const dimensions = try readJpegDimensions(io, gpa, preview.path);
    if (dimensions.width != resume_preview_width) {
        std.debug.print("{s}: expected width {d}, got {d}\n", .{ preview.path, resume_preview_width, dimensions.width });
        return PdfPreviewError.PdfPreviewFailed;
    }
    std.debug.print("rendered {s} ({d}x{d})\n", .{ preview.path, dimensions.width, dimensions.height });
}

fn removeStaleResumePreviews(io: Io, expected_basename: []const u8) !void {
    var static_dir = try Io.Dir.cwd().openDir(io, static_dir_path, .{ .iterate = true });
    defer static_dir.close(io);

    var it = static_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!isResumePreviewName(entry.name)) continue;
        if (std.mem.eql(u8, entry.name, expected_basename)) continue;
        try static_dir.deleteFile(io, entry.name);
    }
}

fn isResumePreviewName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, resume_preview_prefix) and std.mem.endsWith(u8, name, resume_preview_ext);
}

fn readJpegDimensions(io: Io, gpa: std.mem.Allocator, path: []const u8) !ImageDimensions {
    const data = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_size));
    defer gpa.free(data);
    return parseJpegDimensions(data) orelse error.InvalidJpeg;
}

fn parseJpegDimensions(data: []const u8) ?ImageDimensions {
    if (data.len < 4 or data[0] != 0xff or data[1] != 0xd8) return null;

    var index: usize = 2;
    while (index + 3 < data.len) {
        while (index < data.len and data[index] != 0xff) index += 1;
        if (index + 3 >= data.len) return null;
        while (index < data.len and data[index] == 0xff) index += 1;
        if (index >= data.len) return null;

        const marker = data[index];
        index += 1;
        if (marker == 0xd9 or marker == 0xda) return null;
        if (marker == 0x01 or (marker >= 0xd0 and marker <= 0xd7)) continue;
        if (index + 1 >= data.len) return null;

        const segment_len = (@as(usize, data[index]) << 8) | data[index + 1];
        if (segment_len < 2 or index + segment_len > data.len) return null;
        if (isJpegStartOfFrame(marker)) {
            if (segment_len < 7) return null;
            return .{
                .height = (@as(usize, data[index + 3]) << 8) | data[index + 4],
                .width = (@as(usize, data[index + 5]) << 8) | data[index + 6],
            };
        }
        index += segment_len;
    }
    return null;
}

fn isJpegStartOfFrame(marker: u8) bool {
    return switch (marker) {
        0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf => true,
        else => false,
    };
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

fn writeGeneratedArtifacts(io: Io, gpa: std.mem.Allocator, versions: AssetVersions) !usize {
    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, related_dir_path);
    try cwd.createDirPath(io, backlinks_dir_path);
    try cwd.createDirPath(io, similar_dir_path);
    try cwd.createDirPath(io, connections_dir_path);
    try cwd.createDirPath(io, archive_dir_path);

    var written: usize = 0;
    for (pages) |page| {
        if (page.kind == .error_page) continue;

        const related = try renderRelatedFragment(gpa, page);
        defer gpa.free(related);
        try writeGeneratedForPage(io, gpa, related_dir_path, page, related);
        written += 1;

        const backlinks = try renderBacklinksFragment(io, gpa, page);
        defer gpa.free(backlinks);
        try writeGeneratedForPage(io, gpa, backlinks_dir_path, page, backlinks);
        written += 1;

        const similar = try renderSimilarFragment(gpa, page);
        defer gpa.free(similar);
        try writeGeneratedForPage(io, gpa, similar_dir_path, page, similar);
        written += 1;

        const connections = try renderConnectionsFragment(io, gpa, page);
        defer gpa.free(connections);
        try writeGeneratedForPage(io, gpa, connections_dir_path, page, connections);
        written += 1;
    }

    const annotations = try renderAnnotationsJson(io, gpa);
    defer gpa.free(annotations);
    try cwd.writeFile(io, .{ .sub_path = annotations_json_path, .data = annotations });
    written += 1;

    const external_links = try renderExternalLinksJson(io, gpa);
    defer gpa.free(external_links);
    try cwd.writeFile(io, .{ .sub_path = external_links_json_path, .data = external_links });
    written += 1;

    written += try writeArchivePages(io, gpa, versions);
    written += try writeTextAlternates(io, gpa);
    return written;
}

fn checkGeneratedArtifacts(io: Io, gpa: std.mem.Allocator) !usize {
    var failures: usize = 0;

    const required_paths = [_][]const u8{
        annotations_json_path,
        external_links_json_path,
        archive_index_path,
    };
    for (required_paths) |path| {
        if (!try fileExists(io, gpa, path)) {
            std.debug.print("{s} is missing; run `zig build css`\n", .{path});
            failures += 1;
        }
    }

    const expected_annotations = try renderAnnotationsJson(io, gpa);
    defer gpa.free(expected_annotations);
    failures += try checkGeneratedFileContents(io, gpa, annotations_json_path, expected_annotations);

    const expected_external_links = try renderExternalLinksJson(io, gpa);
    defer gpa.free(expected_external_links);
    failures += try checkGeneratedFileContents(io, gpa, external_links_json_path, expected_external_links);
    failures += try checkResumePdfPreview(io, gpa);

    for (pages) |page| {
        if (page.kind == .error_page) continue;
        failures += try checkGeneratedPageArtifact(io, gpa, related_dir_path, page);
        failures += try checkGeneratedPageArtifact(io, gpa, backlinks_dir_path, page);
        failures += try checkGeneratedPageArtifact(io, gpa, similar_dir_path, page);
        failures += try checkGeneratedPageArtifact(io, gpa, connections_dir_path, page);

        if (page.kind == .article or page.kind == .prose) {
            const markdown_path = try std.fmt.allocPrint(gpa, "static/{s}.md", .{page.slug});
            defer gpa.free(markdown_path);
            const text_path = try std.fmt.allocPrint(gpa, "static/{s}.txt", .{page.slug});
            defer gpa.free(text_path);
            if (!try fileExists(io, gpa, markdown_path)) {
                std.debug.print("{s} is missing; run `zig build css`\n", .{markdown_path});
                failures += 1;
            }
            if (!try fileExists(io, gpa, text_path)) {
                std.debug.print("{s} is missing; run `zig build css`\n", .{text_path});
                failures += 1;
            }
        }
    }
    return failures;
}

fn checkResumePdfPreview(io: Io, gpa: std.mem.Allocator) !usize {
    const preview = try resumePdfPreviewInfo(io, gpa);
    defer preview.deinit(gpa);

    var failures: usize = 0;
    if (!try fileExists(io, gpa, preview.path)) {
        std.debug.print("{s} is missing; run `zig build pdf-previews` then `zig build css`\n", .{preview.path});
        failures += 1;
    } else {
        const dimensions = readJpegDimensions(io, gpa, preview.path) catch |err| {
            std.debug.print("{s}: invalid JPEG preview: {s}\n", .{ preview.path, @errorName(err) });
            failures += 1;
            return failures + try checkStaleResumePreviews(io, preview.basename);
        };
        if (dimensions.width != resume_preview_width) {
            std.debug.print("{s}: expected width {d}, got {d}; run `zig build pdf-previews`\n", .{ preview.path, resume_preview_width, dimensions.width });
            failures += 1;
        }
    }

    failures += try checkStaleResumePreviews(io, preview.basename);
    return failures;
}

fn checkStaleResumePreviews(io: Io, expected_basename: []const u8) !usize {
    var static_dir = try Io.Dir.cwd().openDir(io, static_dir_path, .{ .iterate = true });
    defer static_dir.close(io);

    var failures: usize = 0;
    var it = static_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!isResumePreviewName(entry.name)) continue;
        if (std.mem.eql(u8, entry.name, expected_basename)) continue;
        std.debug.print("static/{s} is stale; run `zig build pdf-previews`\n", .{entry.name});
        failures += 1;
    }
    return failures;
}

fn checkGeneratedFileContents(io: Io, gpa: std.mem.Allocator, path: []const u8, expected: []const u8) !usize {
    const actual = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => |e| return e,
    };
    defer gpa.free(actual);
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("{s} is not synchronized with generated site metadata; run `zig build css`\n", .{path});
        return 1;
    }
    return 0;
}

fn checkGeneratedPageArtifact(io: Io, gpa: std.mem.Allocator, dir_path: []const u8, page: PageMeta) !usize {
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}.html", .{ dir_path, page.slug });
    defer gpa.free(path);
    if (!try fileExists(io, gpa, path)) {
        std.debug.print("{s} is missing; run `zig build css`\n", .{path});
        return 1;
    }
    return 0;
}

fn writeGeneratedForPage(io: Io, gpa: std.mem.Allocator, dir_path: []const u8, page: PageMeta, data: []const u8) !void {
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}.html", .{ dir_path, page.slug });
    defer gpa.free(path);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
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

fn appendJsonNumberField(gpa: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: usize, comma: bool) !void {
    try out.appendSlice(gpa, "      ");
    try appendJsonString(gpa, out, key);
    try out.print(gpa, ": {d}", .{value});
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

fn renderRelatedFragment(gpa: std.mem.Allocator, page: PageMeta) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try appendPageListSection(gpa, &out, "Related", "Pages explicitly connected to this page.", page.related);
    return try out.toOwnedSlice(gpa);
}

fn renderBacklinksFragment(io: Io, gpa: std.mem.Allocator, page: PageMeta) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    try out.appendSlice(gpa, "<section class=\"generated-section generated-backlinks\">\n");
    try out.appendSlice(gpa, "  <h3>Backlinks</h3>\n");
    try out.appendSlice(gpa, "  <p>Local pages that link here.</p>\n");
    try out.appendSlice(gpa, "  <ul>\n");

    var count: usize = 0;
    for (pages) |source| {
        if (source.kind == .error_page or std.mem.eql(u8, source.slug, page.slug)) continue;
        if (try pageLinksTo(io, gpa, source, page.route)) {
            try out.appendSlice(gpa, "    <li><a href=\"");
            try appendHtmlEscaped(gpa, &out, source.route);
            try out.appendSlice(gpa, "\">");
            try appendHtmlEscaped(gpa, &out, source.title);
            try out.appendSlice(gpa, "</a><span>");
            try appendHtmlEscaped(gpa, &out, source.description);
            try out.appendSlice(gpa, "</span></li>\n");
            count += 1;
        }
    }

    if (count == 0) {
        try out.appendSlice(gpa, "    <li><span>No local backlinks yet.</span></li>\n");
    }
    try out.appendSlice(gpa, "  </ul>\n</section>\n");
    return try out.toOwnedSlice(gpa);
}

fn renderSimilarFragment(gpa: std.mem.Allocator, page: PageMeta) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    try out.appendSlice(gpa, "<section class=\"generated-section generated-similar\">\n");
    try out.appendSlice(gpa, "  <h3>Similar</h3>\n");
    try out.appendSlice(gpa, "  <p>Small tag-based suggestions from the local manifest.</p>\n");
    try out.appendSlice(gpa, "  <ul>\n");

    var count: usize = 0;
    for (pages) |candidate| {
        if (candidate.kind == .error_page or std.mem.eql(u8, candidate.slug, page.slug)) continue;
        if (similarityScore(page, candidate) == 0) continue;
        try out.appendSlice(gpa, "    <li><a href=\"");
        try appendHtmlEscaped(gpa, &out, candidate.route);
        try out.appendSlice(gpa, "\">");
        try appendHtmlEscaped(gpa, &out, candidate.title);
        try out.appendSlice(gpa, "</a><span>");
        try appendHtmlEscaped(gpa, &out, candidate.description);
        try out.appendSlice(gpa, "</span></li>\n");
        count += 1;
    }

    if (count == 0) {
        try out.appendSlice(gpa, "    <li><span>No similar local pages yet.</span></li>\n");
    }
    try out.appendSlice(gpa, "  </ul>\n</section>\n");
    return try out.toOwnedSlice(gpa);
}

fn renderConnectionsFragment(io: Io, gpa: std.mem.Allocator, page: PageMeta) ![]u8 {
    const related = try renderRelatedFragment(gpa, page);
    defer gpa.free(related);
    const backlinks = try renderBacklinksFragment(io, gpa, page);
    defer gpa.free(backlinks);
    const similar = try renderSimilarFragment(gpa, page);
    defer gpa.free(similar);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "<div class=\"generated-connections\">\n");
    try out.appendSlice(gpa, related);
    try out.appendSlice(gpa, backlinks);
    try out.appendSlice(gpa, similar);
    try out.appendSlice(gpa, "</div>\n");
    return try out.toOwnedSlice(gpa);
}

fn appendPageListSection(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    heading: []const u8,
    intro: []const u8,
    routes: []const []const u8,
) !void {
    try out.appendSlice(gpa, "<section class=\"generated-section generated-related\">\n");
    try out.appendSlice(gpa, "  <h3>");
    try appendHtmlEscaped(gpa, out, heading);
    try out.appendSlice(gpa, "</h3>\n  <p>");
    try appendHtmlEscaped(gpa, out, intro);
    try out.appendSlice(gpa, "</p>\n  <ul>\n");
    if (routes.len == 0) {
        try out.appendSlice(gpa, "    <li><span>No related pages yet.</span></li>\n");
    } else {
        for (routes) |route| {
            try out.appendSlice(gpa, "    <li><a href=\"");
            try appendHtmlEscaped(gpa, out, route);
            try out.appendSlice(gpa, "\">");
            if (pageByRoute(route)) |target| {
                try appendHtmlEscaped(gpa, out, target.title);
                try out.appendSlice(gpa, "</a><span>");
                try appendHtmlEscaped(gpa, out, target.description);
                try out.appendSlice(gpa, "</span>");
            } else {
                try appendHtmlEscaped(gpa, out, route);
                try out.appendSlice(gpa, "</a>");
            }
            try out.appendSlice(gpa, "</li>\n");
        }
    }
    try out.appendSlice(gpa, "  </ul>\n</section>\n");
}

fn similarityScore(a: PageMeta, b: PageMeta) usize {
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

fn pageByRoute(route: []const u8) ?PageMeta {
    const normalized = normalizedRoute(route);
    for (pages) |page| {
        if (std.mem.eql(u8, page.route, normalized)) return page;
    }
    return null;
}

fn normalizedRoute(raw: []const u8) []const u8 {
    var value = raw;
    if (std.mem.indexOfAny(u8, value, "?#")) |index| value = value[0..index];
    if (std.mem.endsWith(u8, value, ".html")) value = value[0 .. value.len - ".html".len];
    if (std.mem.eql(u8, value, "/index")) return "/";
    return value;
}

fn pageLinksTo(io: Io, gpa: std.mem.Allocator, source: PageMeta, target_route: []const u8) !bool {
    const html = try readStaticFile(io, gpa, source.file);
    defer gpa.free(html);
    const main_html = extractElement(html, "main") orelse html;

    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, main_html, search_pos, "href=")) |href_pos| {
        const quote_pos = href_pos + "href=".len;
        if (quote_pos >= main_html.len) break;
        const quote = main_html[quote_pos];
        if (quote != '"' and quote != '\'') {
            search_pos = quote_pos + 1;
            continue;
        }

        const value_start = quote_pos + 1;
        const value_end = std.mem.indexOfScalarPos(u8, main_html, value_start, quote) orelse return error.InvalidHtml;
        const raw = main_html[value_start..value_end];
        if (std.mem.eql(u8, normalizedRoute(raw), target_route)) return true;
        search_pos = value_end + 1;
    }

    return false;
}

fn readStaticFile(io: Io, gpa: std.mem.Allocator, file_name: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ static_dir_path, file_name });
    defer gpa.free(path);
    return try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_file_size));
}

fn extractElement(html: []const u8, tag_name: []const u8) ?[]const u8 {
    const open = std.fmt.allocPrint(std.heap.page_allocator, "<{s}", .{tag_name}) catch return null;
    defer std.heap.page_allocator.free(open);
    const close = std.fmt.allocPrint(std.heap.page_allocator, "</{s}>", .{tag_name}) catch return null;
    defer std.heap.page_allocator.free(close);

    const open_start = std.mem.indexOf(u8, html, open) orelse return null;
    const open_end = std.mem.indexOfScalarPos(u8, html, open_start, '>') orelse return null;
    const close_start = std.mem.indexOfPos(u8, html, open_end + 1, close) orelse return null;
    return html[open_end + 1 .. close_start];
}

fn appendHtmlEscaped(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    for (value) |char| {
        switch (char) {
            '&' => try out.appendSlice(gpa, "&amp;"),
            '<' => try out.appendSlice(gpa, "&lt;"),
            '>' => try out.appendSlice(gpa, "&gt;"),
            '"' => try out.appendSlice(gpa, "&quot;"),
            '\'' => try out.appendSlice(gpa, "&#39;"),
            else => try out.append(gpa, char),
        }
    }
}

fn renderAnnotationsJson(io: Io, gpa: std.mem.Allocator) ![]u8 {
    var link_context = try loadLinkContextCache(io, gpa);
    defer if (link_context) |*parsed| parsed.deinit();

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var seen: std.ArrayList([]u8) = .empty;
    defer freeStringList(gpa, &seen);

    try out.appendSlice(gpa, "{\n  \"annotations\": [\n");
    var count: usize = 0;
    for (pages) |page| {
        if (page.kind == .error_page) continue;
        const html = try readStaticFile(io, gpa, page.file);
        defer gpa.free(html);
        const main_html = extractElement(html, "main") orelse html;
        try appendAnnotationsFromHtml(io, gpa, &out, &seen, page, main_html, &count, if (link_context) |*parsed| &parsed.value else null);
    }
    try out.appendSlice(gpa, "\n  ]\n}\n");
    return try out.toOwnedSlice(gpa);
}

fn renderExternalLinksJson(io: Io, gpa: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var seen: std.ArrayList([]u8) = .empty;
    defer freeStringList(gpa, &seen);

    try out.appendSlice(gpa, "{\n  \"external_links\": [\n");
    var count: usize = 0;
    try collectExternalLinks(io, gpa, &seen);
    for (seen.items) |url| {
        if (count != 0) try out.appendSlice(gpa, ",\n");
        const archive_path = try archivePath(gpa, url);
        defer gpa.free(archive_path);
        try out.appendSlice(gpa, "    {\n");
        try appendJsonField(gpa, &out, "url", url, true);
        try appendJsonField(gpa, &out, "archive", archive_path, false);
        try out.appendSlice(gpa, "    }");
        count += 1;
    }
    try out.appendSlice(gpa, "\n  ]\n}\n");
    return try out.toOwnedSlice(gpa);
}

fn appendAnnotationsFromHtml(
    io: Io,
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    seen: *std.ArrayList([]u8),
    page: PageMeta,
    html: []const u8,
    count: *usize,
    link_context: ?*const std.json.Value,
) !void {
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<a")) |anchor_start| {
        if (isInsideHtmlComment(html, anchor_start)) {
            search_pos = anchor_start + "<a".len;
            continue;
        }
        const tag_end = std.mem.indexOfScalarPos(u8, html, anchor_start, '>') orelse break;
        const close = findClosingTag(html, tag_end + 1, "a") orelse break;
        const tag = html[anchor_start..tag_end];
        if (std.mem.indexOf(u8, tag, "heading-anchor") != null) {
            search_pos = close.end;
            continue;
        }
        const href = attributeValue(tag, "href") orelse {
            search_pos = close.end;
            continue;
        };
        if (href.len == 0 or href[0] == '#' or std.mem.startsWith(u8, href, "mailto:")) {
            search_pos = close.end;
            continue;
        }
        if (containsString(seen.items, href)) {
            search_pos = close.end;
            continue;
        }

        const text = try htmlText(gpa, html[tag_end + 1 .. close.start]);
        defer gpa.free(text);
        if (std.mem.trim(u8, text, " \t\r\n").len == 0) {
            search_pos = close.end;
            continue;
        }

        try seen.append(gpa, try gpa.dupe(u8, href));
        if (count.* != 0) try out.appendSlice(gpa, ",\n");
        try appendAnnotationObject(io, gpa, out, page, href, text, link_context);
        count.* += 1;
        search_pos = close.end;
    }
}

fn appendAnnotationObject(
    io: Io,
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_page: PageMeta,
    href: []const u8,
    text: []const u8,
    link_context: ?*const std.json.Value,
) !void {
    const kind = linkKind(href);
    const trimmed_text = std.mem.trim(u8, text, " \t\r\n");
    try out.appendSlice(gpa, "    {\n");
    try appendJsonField(gpa, out, "href", href, true);
    try appendJsonField(gpa, out, "text", trimmed_text, true);
    try appendJsonField(gpa, out, "kind", kind, true);
    try appendJsonField(gpa, out, "source", source_page.route, true);
    try appendJsonField(gpa, out, "source_title", source_page.title, true);
    if (pageByRoute(href)) |target| {
        const summary = try internalPageSummary(io, gpa, target);
        defer gpa.free(summary);
        const context_kind = switch (target.kind) {
            .article, .prose => "article",
            else => "internal",
        };
        try appendJsonField(gpa, out, "title", target.title, true);
        try appendJsonField(gpa, out, "summary", summary, true);
        if (target.date) |date| try appendJsonField(gpa, out, "date", date, true);
        try appendJsonField(gpa, out, "site_name", "plosca.ru", true);
        try appendJsonField(gpa, out, "context_kind", context_kind, false);
    } else if (std.mem.eql(u8, kind, "external")) {
        try appendExternalAnnotation(gpa, out, href, trimmed_text, link_context);
    } else if (std.mem.eql(u8, kind, "pdf") and std.mem.eql(u8, href, resume_pdf_href)) {
        try appendResumePdfAnnotation(io, gpa, out);
    } else {
        try appendJsonField(gpa, out, "title", trimmed_text, true);
        try appendJsonField(gpa, out, "summary", "Static asset or local route.", false);
    }
    try out.appendSlice(gpa, "    }");
}

fn appendResumePdfAnnotation(io: Io, gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    const preview = try resumePdfPreviewInfo(io, gpa);
    defer preview.deinit(gpa);

    try appendJsonField(gpa, out, "title", "Resume PDF", true);
    try appendJsonField(gpa, out, "summary", "One-page resume PDF for Mircea Ilie Ploscaru, focused on full-stack development, data engineering, BI, and automation.", true);
    try appendJsonField(gpa, out, "site_name", "plosca.ru", true);
    try appendJsonField(gpa, out, "context_kind", "pdf", true);

    if (try fileExists(io, gpa, preview.path)) {
        const dimensions = try readJpegDimensions(io, gpa, preview.path);
        try appendJsonNumberField(gpa, out, "file_size", preview.file_size, true);
        try appendJsonField(gpa, out, "preview_image", preview.href, true);
        try appendJsonNumberField(gpa, out, "preview_width", dimensions.width, true);
        try appendJsonNumberField(gpa, out, "preview_height", dimensions.height, false);
    } else {
        try appendJsonNumberField(gpa, out, "file_size", preview.file_size, false);
    }
}

fn internalPageSummary(io: Io, gpa: std.mem.Allocator, page: PageMeta) ![]u8 {
    const html = try readStaticFile(io, gpa, page.file);
    defer gpa.free(html);

    const article = extractElement(html, "article") orelse html;
    var body = article;
    if (std.mem.indexOf(u8, body, "</header>")) |header_end| {
        body = body[header_end + "</header>".len ..];
    }
    if (std.mem.indexOf(u8, body, "<section class=\"article-links\"")) |section_start| {
        body = body[0..section_start];
    }
    if (std.mem.indexOf(u8, body, "<section class=\"generated-section\"")) |section_start| {
        body = body[0..section_start];
    }

    const paragraphs = try articleParagraphPreviewText(gpa, body);
    defer gpa.free(paragraphs);
    if (std.mem.trim(u8, paragraphs, " \t\r\n").len == 0) {
        return try gpa.dupe(u8, page.description);
    }
    return try normalizePreviewText(gpa, paragraphs, internal_summary_limit);
}

fn articleParagraphPreviewText(gpa: std.mem.Allocator, html: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var search_pos: usize = 0;
    var paragraph_count: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<p")) |paragraph_start| {
        const tag_end = std.mem.indexOfScalarPos(u8, html, paragraph_start, '>') orelse break;
        const tag = html[paragraph_start..tag_end];
        const close = findClosingTag(html, tag_end + 1, "p") orelse break;
        search_pos = close.end;

        if (std.mem.indexOf(u8, tag, "class=\"date\"") != null) continue;

        const text = try htmlText(gpa, html[tag_end + 1 .. close.start]);
        defer gpa.free(text);
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (trimmed.len == 0) continue;

        if (out.items.len != 0) try out.appendSlice(gpa, "\n\n");
        try out.appendSlice(gpa, trimmed);
        paragraph_count += 1;
        if (out.items.len >= internal_summary_limit or paragraph_count >= 4) break;
    }

    return try out.toOwnedSlice(gpa);
}

fn appendExternalAnnotation(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    href: []const u8,
    fallback_title: []const u8,
    link_context: ?*const std.json.Value,
) !void {
    const archive_path = try archivePath(gpa, href);
    defer gpa.free(archive_path);

    const context = if (link_context) |root| findLinkContext(root, href) else null;
    const context_status = if (context) |value| jsonStringField(value.*, "status") else null;
    const usable_context = if (context_status) |status|
        std.mem.eql(u8, status, "ok") or std.mem.eql(u8, status, "manual")
    else
        false;
    const title = if (usable_context and context != null)
        firstNonEmpty(&.{ jsonStringField(context.?.*, "title"), @as(?[]const u8, fallback_title) })
    else
        fallback_title;
    const summary = if (usable_context and context != null)
        firstNonEmpty(&.{ jsonStringField(context.?.*, "summary"), null })
    else
        null;
    const site_name = if (context) |value|
        firstNonEmpty(&.{ jsonStringField(value.*, "site_name"), displayHost(href) })
    else
        displayHost(href);
    const context_kind = if (context) |value| jsonStringField(value.*, "kind") else null;

    try appendJsonField(gpa, out, "title", title orelse fallback_title, true);
    if (summary) |value| {
        try appendJsonField(gpa, out, "summary", value, true);
    } else {
        const fallback = try std.fmt.allocPrint(gpa, "External link to {s}.", .{site_name orelse "another site"});
        defer gpa.free(fallback);
        try appendJsonField(gpa, out, "summary", fallback, true);
    }
    if (site_name) |value| try appendJsonField(gpa, out, "site_name", value, true);
    if (context_kind) |value| try appendJsonField(gpa, out, "context_kind", value, true);
    if (context) |value| {
        if (jsonStringField(value.*, "canonical_url")) |canonical| {
            try appendJsonField(gpa, out, "canonical_url", canonical, true);
        }
    }
    try appendJsonField(gpa, out, "archive", archive_path, false);
}

fn firstNonEmpty(values: []const ?[]const u8) ?[]const u8 {
    for (values) |maybe_value| {
        const value = maybe_value orelse continue;
        if (std.mem.trim(u8, value, " \t\r\n").len != 0) return value;
    }
    return null;
}

fn loadLinkContextCache(io: Io, gpa: std.mem.Allocator) !?std.json.Parsed(std.json.Value) {
    const data = Io.Dir.cwd().readFileAlloc(io, link_context_path, gpa, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => |e| return e,
    };
    defer gpa.free(data);
    return try std.json.parseFromSlice(std.json.Value, gpa, data, .{});
}

fn findLinkContext(root: *const std.json.Value, url: []const u8) ?*const std.json.Value {
    if (root.* != .object) return null;
    const links = root.object.get("links") orelse return null;
    if (links != .object) return null;
    return links.object.getPtr(url);
}

fn jsonStringField(value: std.json.Value, field: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const child = value.object.get(field) orelse return null;
    if (child != .string) return null;
    return child.string;
}

fn displayHost(url: []const u8) ?[]const u8 {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    var host_start = scheme_end + "://".len;
    if (std.mem.startsWith(u8, url[host_start..], "www.")) host_start += "www.".len;
    var host_end = host_start;
    while (host_end < url.len and url[host_end] != '/' and url[host_end] != '?' and url[host_end] != '#') : (host_end += 1) {}
    if (host_end == host_start) return null;
    return url[host_start..host_end];
}

fn linkKind(href: []const u8) []const u8 {
    if (std.mem.startsWith(u8, href, "http://") or std.mem.startsWith(u8, href, "https://")) return "external";
    if (std.mem.endsWith(u8, href, ".pdf")) return "pdf";
    if (pageByRoute(href) != null) return "internal";
    return "asset";
}

fn collectExternalLinks(io: Io, gpa: std.mem.Allocator, urls: *std.ArrayList([]u8)) !void {
    for (pages) |page| {
        if (page.kind == .error_page) continue;
        const html = try readStaticFile(io, gpa, page.file);
        defer gpa.free(html);
        const main_html = extractElement(html, "main") orelse html;
        var search_pos: usize = 0;
        while (std.mem.indexOfPos(u8, main_html, search_pos, "href=")) |href_pos| {
            const quote_pos = href_pos + "href=".len;
            if (quote_pos >= main_html.len) break;
            const quote = main_html[quote_pos];
            if (quote != '"' and quote != '\'') {
                search_pos = quote_pos + 1;
                continue;
            }
            const value_start = quote_pos + 1;
            const value_end = std.mem.indexOfScalarPos(u8, main_html, value_start, quote) orelse return error.InvalidHtml;
            const href = main_html[value_start..value_end];
            if ((std.mem.startsWith(u8, href, "http://") or std.mem.startsWith(u8, href, "https://")) and !containsString(urls.items, href)) {
                try urls.append(gpa, try gpa.dupe(u8, href));
            }
            search_pos = value_end + 1;
        }
    }
}

const LinkContextData = struct {
    status: []const u8,
    kind: []const u8,
    title: ?[]u8 = null,
    summary: ?[]u8 = null,
    site_name: ?[]u8 = null,
    canonical_url: ?[]u8 = null,
    source_url: ?[]u8 = null,
    fetched_at: []u8,
    err: ?[]u8 = null,

    fn deinit(self: *LinkContextData, gpa: std.mem.Allocator) void {
        if (self.title) |value| gpa.free(value);
        if (self.summary) |value| gpa.free(value);
        if (self.site_name) |value| gpa.free(value);
        if (self.canonical_url) |value| gpa.free(value);
        if (self.source_url) |value| gpa.free(value);
        if (self.err) |value| gpa.free(value);
        gpa.free(self.fetched_at);
    }
};

const CurlFetch = struct {
    body: ?[]u8 = null,
    err: ?[]u8 = null,

    fn deinit(self: *CurlFetch, gpa: std.mem.Allocator) void {
        if (self.body) |value| gpa.free(value);
        if (self.err) |value| gpa.free(value);
    }
};

fn enrichLinks(io: Io, gpa: std.mem.Allocator) !void {
    var urls: std.ArrayList([]u8) = .empty;
    defer freeStringList(gpa, &urls);
    try collectExternalLinks(io, gpa, &urls);

    var previous = try loadLinkContextCache(io, gpa);
    defer if (previous) |*parsed| parsed.deinit();

    try Io.Dir.cwd().createDirPath(io, "src/content");

    const fetched_at = try isoTimestamp(io, gpa);
    defer gpa.free(fetched_at);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\n  \"version\": 1,\n  \"updated_at\": ");
    try appendJsonString(gpa, &out, fetched_at);
    try out.appendSlice(gpa, ",\n  \"links\": {\n");

    var fetched_count: usize = 0;
    var preserved_count: usize = 0;
    var failed_count: usize = 0;
    for (urls.items, 0..) |url, index| {
        if (index != 0) try out.appendSlice(gpa, ",\n");
        try out.appendSlice(gpa, "    ");
        try appendJsonString(gpa, &out, url);
        try out.appendSlice(gpa, ": {\n");

        const previous_context = if (previous) |*parsed| findLinkContext(&parsed.value, url) else null;
        if (previous_context) |value| {
            if (jsonStringField(value.*, "status")) |status| {
                if (std.mem.eql(u8, status, "manual")) {
                    try appendCachedContextObject(gpa, &out, url, value.*, fetched_at);
                    preserved_count += 1;
                    try out.appendSlice(gpa, "    }");
                    continue;
                }
            }
        }

        var context = try enrichSingleLink(io, gpa, url, fetched_at);
        defer context.deinit(gpa);
        const failed = std.mem.eql(u8, context.status, "failed");
        if (failed) {
            if (previous_context) |value| {
                if (isUsableCachedContext(value.*)) {
                    try appendCachedContextObject(gpa, &out, url, value.*, fetched_at);
                    preserved_count += 1;
                    try out.appendSlice(gpa, "    }");
                    continue;
                }
            }
            failed_count += 1;
        } else {
            fetched_count += 1;
        }
        try appendLinkContextObject(gpa, &out, url, context);
        try out.appendSlice(gpa, "    }");
    }

    try out.appendSlice(gpa, "\n  }\n}\n");
    const data = try out.toOwnedSlice(gpa);
    defer gpa.free(data);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = link_context_path, .data = data });
    std.debug.print("enriched {d} link(s), preserved {d}, failed {d}; wrote {s}\n", .{
        fetched_count,
        preserved_count,
        failed_count,
        link_context_path,
    });
}

fn enrichSingleLink(io: Io, gpa: std.mem.Allocator, url: []const u8, fetched_at: []const u8) !LinkContextData {
    if (try wikipediaSummaryUrl(gpa, url)) |summary_url| {
        defer gpa.free(summary_url);
        return try enrichWikipediaLink(io, gpa, url, summary_url, fetched_at);
    }
    if (try youtubeOembedUrl(gpa, url)) |oembed_url| {
        defer gpa.free(oembed_url);
        return try enrichYoutubeLink(io, gpa, url, oembed_url, fetched_at);
    }
    return try enrichGenericLink(io, gpa, url, fetched_at);
}

fn appendLinkContextObject(gpa: std.mem.Allocator, out: *std.ArrayList(u8), url: []const u8, context: LinkContextData) !void {
    try appendJsonField(gpa, out, "status", context.status, true);
    try appendJsonField(gpa, out, "kind", context.kind, true);
    try appendJsonField(gpa, out, "title", context.title orelse displayHost(url) orelse url, true);
    try appendJsonField(gpa, out, "summary", context.summary orelse "", true);
    try appendJsonField(gpa, out, "site_name", context.site_name orelse displayHost(url) orelse "external", true);
    try appendJsonField(gpa, out, "canonical_url", context.canonical_url orelse url, true);
    try appendJsonField(gpa, out, "source_url", context.source_url orelse url, true);
    try appendJsonField(gpa, out, "fetched_at", context.fetched_at, context.err != null);
    if (context.err) |err| try appendJsonField(gpa, out, "error", err, false);
}

fn appendCachedContextObject(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    url: []const u8,
    context: std.json.Value,
    fetched_at: []const u8,
) !void {
    const has_error = jsonStringField(context, "error") != null;
    try appendJsonField(gpa, out, "status", jsonStringField(context, "status") orelse "manual", true);
    try appendJsonField(gpa, out, "kind", jsonStringField(context, "kind") orelse "manual", true);
    try appendJsonField(gpa, out, "title", jsonStringField(context, "title") orelse displayHost(url) orelse url, true);
    try appendJsonField(gpa, out, "summary", jsonStringField(context, "summary") orelse "", true);
    try appendJsonField(gpa, out, "site_name", jsonStringField(context, "site_name") orelse displayHost(url) orelse "external", true);
    try appendJsonField(gpa, out, "canonical_url", jsonStringField(context, "canonical_url") orelse url, true);
    try appendJsonField(gpa, out, "source_url", jsonStringField(context, "source_url") orelse url, true);
    try appendJsonField(gpa, out, "fetched_at", jsonStringField(context, "fetched_at") orelse fetched_at, has_error);
    if (jsonStringField(context, "error")) |err| try appendJsonField(gpa, out, "error", err, false);
}

fn isUsableCachedContext(context: std.json.Value) bool {
    const status = jsonStringField(context, "status") orelse return false;
    if (!std.mem.eql(u8, status, "ok") and !std.mem.eql(u8, status, "manual")) return false;
    const summary = jsonStringField(context, "summary") orelse return false;
    return std.mem.trim(u8, summary, " \t\r\n").len != 0;
}

fn enrichWikipediaLink(
    io: Io,
    gpa: std.mem.Allocator,
    url: []const u8,
    summary_url: []const u8,
    fetched_at: []const u8,
) !LinkContextData {
    var fetch = try curlFetch(io, gpa, summary_url);
    defer fetch.deinit(gpa);
    if (fetch.body) |body| {
        if (try contextFromWikipediaSummary(gpa, body, url, summary_url, fetched_at)) |context| return context;
    }

    const fallback_url = try wikipediaExtractUrl(gpa, url);
    defer if (fallback_url) |value| gpa.free(value);
    if (fallback_url) |extract_url| {
        var fallback_fetch = try curlFetch(io, gpa, extract_url);
        defer fallback_fetch.deinit(gpa);
        if (fallback_fetch.body) |body| {
            if (try contextFromWikipediaExtract(gpa, body, url, extract_url, fetched_at)) |context| return context;
        }
        if (fallback_fetch.err) |err| return try failedContext(gpa, url, "wikipedia", extract_url, fetched_at, err);
    }

    return try failedContext(gpa, url, "wikipedia", summary_url, fetched_at, fetch.err orelse "Wikipedia summary did not include an extract");
}

fn enrichGenericLink(io: Io, gpa: std.mem.Allocator, url: []const u8, fetched_at: []const u8) !LinkContextData {
    var fetch = try curlFetch(io, gpa, url);
    defer fetch.deinit(gpa);
    if (fetch.err) |err| return try failedContext(gpa, url, "failed", url, fetched_at, err);
    const body = fetch.body orelse return try failedContext(gpa, url, "failed", url, fetched_at, "empty response");

    if (!looksLikeHtml(body)) {
        return try failedContext(gpa, url, "failed", url, fetched_at, "response did not look like HTML");
    }

    const raw_title = firstNonEmpty(&.{
        findMetaContentByNameOrProperty(body, "property", "og:title"),
        findMetaContentByNameOrProperty(body, "name", "twitter:title"),
        findElementContent(body, "title"),
        displayHost(url),
    }) orelse url;
    const raw_meta_summary = firstNonEmpty(&.{
        findMetaContentByNameOrProperty(body, "property", "og:description"),
        findMetaContentByNameOrProperty(body, "name", "twitter:description"),
        findMetaContentByNameOrProperty(body, "name", "description"),
    });
    const raw_summary = raw_meta_summary orelse findElementContent(body, "p");
    const raw_site = firstNonEmpty(&.{
        findMetaContentByNameOrProperty(body, "property", "og:site_name"),
        displayHost(url),
    }) orelse "external";
    const raw_canonical = firstNonEmpty(&.{
        findCanonicalLink(body),
        findMetaContentByNameOrProperty(body, "property", "og:url"),
        @as(?[]const u8, url),
    }) orelse url;
    const canonical = if (std.mem.eql(u8, raw_canonical, "undefined")) url else raw_canonical;

    const title = try normalizePreviewText(gpa, raw_title, link_title_limit);
    const summary = if (raw_summary) |value|
        try normalizePreviewText(gpa, value, link_summary_limit)
    else
        try std.fmt.allocPrint(gpa, "External link to {s}.", .{displayHost(url) orelse "another site"});
    const site_name = try normalizePreviewText(gpa, raw_site, 80);
    const canonical_url = try normalizePreviewText(gpa, canonical, 400);
    const source_url = try gpa.dupe(u8, url);
    return .{
        .status = "ok",
        .kind = if (raw_meta_summary != null) "opengraph" else "generic",
        .title = title,
        .summary = summary,
        .site_name = site_name,
        .canonical_url = canonical_url,
        .source_url = source_url,
        .fetched_at = try gpa.dupe(u8, fetched_at),
    };
}

fn enrichYoutubeLink(
    io: Io,
    gpa: std.mem.Allocator,
    url: []const u8,
    oembed_url: []const u8,
    fetched_at: []const u8,
) !LinkContextData {
    var fetch = try curlFetch(io, gpa, oembed_url);
    defer fetch.deinit(gpa);
    if (fetch.err) |err| return try failedContext(gpa, url, "youtube", oembed_url, fetched_at, err);
    const body = fetch.body orelse return try failedContext(gpa, url, "youtube", oembed_url, fetched_at, "empty response");

    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch {
        return try failedContext(gpa, url, "youtube", oembed_url, fetched_at, "YouTube oEmbed response was not JSON");
    };
    defer parsed.deinit();

    const raw_title = jsonStringField(parsed.value, "title") orelse return try failedContext(gpa, url, "youtube", oembed_url, fetched_at, "YouTube oEmbed response had no title");
    const author = jsonStringField(parsed.value, "author_name");
    const summary = if (author) |name|
        try std.fmt.allocPrint(gpa, "YouTube video by {s}.", .{name})
    else
        try gpa.dupe(u8, "YouTube video.");
    defer gpa.free(summary);

    return .{
        .status = "ok",
        .kind = "youtube",
        .title = try normalizePreviewText(gpa, raw_title, link_title_limit),
        .summary = try normalizePreviewText(gpa, summary, link_summary_limit),
        .site_name = try gpa.dupe(u8, "YouTube"),
        .canonical_url = try gpa.dupe(u8, url),
        .source_url = try gpa.dupe(u8, oembed_url),
        .fetched_at = try gpa.dupe(u8, fetched_at),
    };
}

fn contextFromWikipediaSummary(
    gpa: std.mem.Allocator,
    body: []const u8,
    url: []const u8,
    summary_url: []const u8,
    fetched_at: []const u8,
) !?LinkContextData {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();

    const raw_summary = firstNonEmpty(&.{
        jsonStringField(parsed.value, "extract"),
        jsonStringField(parsed.value, "description"),
    }) orelse return null;
    const raw_title = firstNonEmpty(&.{ jsonStringField(parsed.value, "title"), displayHost(url) }) orelse url;
    const canonical = jsonNestedString(parsed.value, &.{ "content_urls", "desktop", "page" }) orelse url;

    return .{
        .status = "ok",
        .kind = "wikipedia",
        .title = try normalizePreviewText(gpa, raw_title, link_title_limit),
        .summary = try normalizePreviewText(gpa, raw_summary, wikipedia_summary_limit),
        .site_name = try gpa.dupe(u8, "Wikipedia"),
        .canonical_url = try gpa.dupe(u8, canonical),
        .source_url = try gpa.dupe(u8, summary_url),
        .fetched_at = try gpa.dupe(u8, fetched_at),
    };
}

fn contextFromWikipediaExtract(
    gpa: std.mem.Allocator,
    body: []const u8,
    url: []const u8,
    extract_url: []const u8,
    fetched_at: []const u8,
) !?LinkContextData {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();

    const pages_value = jsonNestedValue(parsed.value, &.{ "query", "pages" }) orelse return null;
    if (pages_value != .object) return null;
    var it = pages_value.object.iterator();
    while (it.next()) |entry| {
        const page = entry.value_ptr.*;
        const raw_summary = jsonStringField(page, "extract") orelse continue;
        if (std.mem.trim(u8, raw_summary, " \t\r\n").len == 0) continue;
        const raw_title = firstNonEmpty(&.{ jsonStringField(page, "title"), displayHost(url) }) orelse url;
        return .{
            .status = "ok",
            .kind = "wikipedia",
            .title = try normalizePreviewText(gpa, raw_title, link_title_limit),
            .summary = try normalizePreviewText(gpa, raw_summary, wikipedia_summary_limit),
            .site_name = try gpa.dupe(u8, "Wikipedia"),
            .canonical_url = try gpa.dupe(u8, url),
            .source_url = try gpa.dupe(u8, extract_url),
            .fetched_at = try gpa.dupe(u8, fetched_at),
        };
    }
    return null;
}

fn failedContext(
    gpa: std.mem.Allocator,
    url: []const u8,
    kind: []const u8,
    source_url: []const u8,
    fetched_at: []const u8,
    err: []const u8,
) !LinkContextData {
    return .{
        .status = "failed",
        .kind = kind,
        .title = if (displayHost(url)) |host| try gpa.dupe(u8, host) else try gpa.dupe(u8, url),
        .summary = try std.fmt.allocPrint(gpa, "External link to {s}.", .{displayHost(url) orelse "another site"}),
        .site_name = if (displayHost(url)) |host| try gpa.dupe(u8, host) else try gpa.dupe(u8, "external"),
        .canonical_url = try gpa.dupe(u8, url),
        .source_url = try gpa.dupe(u8, source_url),
        .fetched_at = try gpa.dupe(u8, fetched_at),
        .err = try normalizePreviewText(gpa, err, 220),
    };
}

fn curlFetch(io: Io, gpa: std.mem.Allocator, url: []const u8) !CurlFetch {
    const argv = [_][]const u8{
        "curl",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-time",
        "8",
        "--header",
        "Accept: text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
        "--header",
        "Accept-Encoding: identity",
        "--range",
        "0-1048575",
        "--user-agent",
        curl_user_agent,
        url,
    };
    const result = std.process.run(gpa, io, .{
        .argv = &argv,
        .expand_arg0 = .expand,
        .stdout_limit = .limited(max_fetch_size),
        .stderr_limit = .limited(64 * 1024),
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("curl is required for `zig build enrich-links`; install curl or refresh {s} manually\n", .{link_context_path});
        }
        if (err == error.StreamTooLong) {
            return .{ .err = try std.fmt.allocPrint(gpa, "response exceeded {d} byte metadata fetch limit", .{max_fetch_size}) };
        }
        return err;
    };

    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (ok) {
        gpa.free(result.stderr);
        return .{ .body = result.stdout };
    }

    const trimmed = std.mem.trim(u8, result.stderr, " \t\r\n");
    const message = if (trimmed.len == 0)
        try std.fmt.allocPrint(gpa, "curl failed for {s}", .{url})
    else
        try gpa.dupe(u8, trimmed);
    gpa.free(result.stdout);
    gpa.free(result.stderr);
    return .{ .err = message };
}

fn wikipediaSummaryUrl(gpa: std.mem.Allocator, url: []const u8) !?[]u8 {
    const host = fullHost(url) orelse return null;
    const display = displayHost(url) orelse return null;
    if (!std.mem.endsWith(u8, display, "wikipedia.org")) return null;
    const path_start = host.end;
    if (!std.mem.startsWith(u8, url[path_start..], "/wiki/")) return null;
    const raw_title = url[path_start + "/wiki/".len .. urlPathEnd(url, path_start + "/wiki/".len)];
    if (raw_title.len == 0) return null;
    return try std.fmt.allocPrint(gpa, "{s}://{s}/api/rest_v1/page/summary/{s}", .{
        url[0..host.scheme_end],
        url[host.start..host.end],
        raw_title,
    });
}

fn youtubeOembedUrl(gpa: std.mem.Allocator, url: []const u8) !?[]u8 {
    const display = displayHost(url) orelse return null;
    if (!std.mem.eql(u8, display, "youtu.be") and
        !std.mem.eql(u8, display, "youtube.com") and
        !std.mem.endsWith(u8, display, ".youtube.com"))
    {
        return null;
    }
    const encoded = try percentEncode(gpa, url, .query);
    defer gpa.free(encoded);
    return try std.fmt.allocPrint(gpa, "https://www.youtube.com/oembed?url={s}&format=json", .{encoded});
}

fn wikipediaExtractUrl(gpa: std.mem.Allocator, url: []const u8) !?[]u8 {
    const host = fullHost(url) orelse return null;
    const display = displayHost(url) orelse return null;
    if (!std.mem.endsWith(u8, display, "wikipedia.org")) return null;
    const path_start = host.end;
    if (!std.mem.startsWith(u8, url[path_start..], "/wiki/")) return null;
    const raw_title = url[path_start + "/wiki/".len .. urlPathEnd(url, path_start + "/wiki/".len)];
    if (raw_title.len == 0) return null;
    const title = try percentEncode(gpa, raw_title, .query);
    defer gpa.free(title);
    return try std.fmt.allocPrint(
        gpa,
        "{s}://{s}/w/api.php?action=query&prop=extracts&exintro=1&explaintext=1&redirects=1&format=json&titles={s}",
        .{ url[0..host.scheme_end], url[host.start..host.end], title },
    );
}

const HostRange = struct {
    scheme_end: usize,
    start: usize,
    end: usize,
};

fn fullHost(url: []const u8) ?HostRange {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    const start = scheme_end + "://".len;
    var end = start;
    while (end < url.len and url[end] != '/' and url[end] != '?' and url[end] != '#') : (end += 1) {}
    if (end == start) return null;
    return .{ .scheme_end = scheme_end, .start = start, .end = end };
}

fn urlPathEnd(url: []const u8, start: usize) usize {
    var end = start;
    while (end < url.len and url[end] != '?' and url[end] != '#') : (end += 1) {}
    return end;
}

const PercentEncodeMode = enum { path, query };

fn percentEncode(gpa: std.mem.Allocator, value: []const u8, mode: PercentEncodeMode) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const hex = "0123456789ABCDEF";
    for (value) |char| {
        const keep = std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.' or char == '~' or
            (mode == .path and (char == '%' or char == '(' or char == ')' or char == ':' or char == '@'));
        if (keep) {
            try out.append(gpa, char);
        } else if (mode == .query and char == ' ') {
            try out.append(gpa, '+');
        } else {
            try out.append(gpa, '%');
            try out.append(gpa, hex[char >> 4]);
            try out.append(gpa, hex[char & 0x0f]);
        }
    }
    return try out.toOwnedSlice(gpa);
}

fn looksLikeHtml(body: []const u8) bool {
    const prefix = body[0..@min(body.len, 4096)];
    return std.ascii.indexOfIgnoreCase(prefix, "<html") != null or
        std.ascii.indexOfIgnoreCase(prefix, "<!doctype html") != null or
        std.ascii.indexOfIgnoreCase(prefix, "<meta") != null or
        std.ascii.indexOfIgnoreCase(prefix, "<title") != null;
}

fn findMetaContentByNameOrProperty(html: []const u8, attr: []const u8, expected: []const u8) ?[]const u8 {
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<meta")) |meta_start| {
        const tag_end = std.mem.indexOfScalarPos(u8, html, meta_start, '>') orelse return null;
        const tag = html[meta_start..tag_end];
        if (attributeEquals(tag, attr, expected)) {
            if (attributeValue(tag, "content")) |content| return content;
        }
        search_pos = tag_end + 1;
    }
    return null;
}

fn findCanonicalLink(html: []const u8) ?[]const u8 {
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, html, search_pos, "<link")) |link_start| {
        const tag_end = std.mem.indexOfScalarPos(u8, html, link_start, '>') orelse return null;
        const tag = html[link_start..tag_end];
        if (attributeContainsWord(tag, "rel", "canonical")) {
            if (attributeValue(tag, "href")) |href| return href;
        }
        search_pos = tag_end + 1;
    }
    return null;
}

fn attributeContainsWord(tag: []const u8, attr_name: []const u8, expected: []const u8) bool {
    const value = attributeValue(tag, attr_name) orelse return false;
    var it = std.mem.tokenizeAny(u8, value, " \t\r\n");
    while (it.next()) |word| {
        if (std.ascii.eqlIgnoreCase(word, expected)) return true;
    }
    return false;
}

fn jsonNestedValue(value: std.json.Value, path: []const []const u8) ?std.json.Value {
    var cursor = value;
    for (path) |field| {
        if (cursor != .object) return null;
        cursor = cursor.object.get(field) orelse return null;
    }
    return cursor;
}

fn jsonNestedString(value: std.json.Value, path: []const []const u8) ?[]const u8 {
    const child = jsonNestedValue(value, path) orelse return null;
    if (child != .string) return null;
    return child.string;
}

fn normalizePreviewText(gpa: std.mem.Allocator, raw: []const u8, limit: usize) ![]u8 {
    const plain = try htmlText(gpa, raw);
    defer gpa.free(plain);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var last_space = true;
    for (plain) |char| {
        if (std.ascii.isWhitespace(char)) {
            if (!last_space) {
                try out.append(gpa, ' ');
                last_space = true;
            }
        } else {
            try out.append(gpa, char);
            last_space = false;
        }
    }
    while (out.items.len != 0 and out.items[out.items.len - 1] == ' ') _ = out.pop();

    if (out.items.len <= limit) return try out.toOwnedSlice(gpa);
    const end = utf8SafePrefixLen(out.items, limit);
    const trimmed = std.mem.trimEnd(u8, out.items[0..end], " \t\r\n.,;:");
    const result = try std.fmt.allocPrint(gpa, "{s}...", .{trimmed});
    out.deinit(gpa);
    return result;
}

fn utf8SafePrefixLen(value: []const u8, max_len: usize) usize {
    if (value.len <= max_len) return value.len;
    var end = max_len;
    while (end > 0 and (value[end] & 0xc0) == 0x80) end -= 1;
    return end;
}

fn isoTimestamp(io: Io, gpa: std.mem.Allocator) ![]u8 {
    const now = Io.Clock.real.now(io).nanoseconds;
    const secs: u64 = if (now > 0) @intCast(@divTrunc(now, std.time.ns_per_s)) else 0;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = secs };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return try std.fmt.allocPrint(
        gpa,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
}

fn writeArchivePages(io: Io, gpa: std.mem.Allocator, versions: AssetVersions) !usize {
    var urls: std.ArrayList([]u8) = .empty;
    defer freeStringList(gpa, &urls);
    try collectExternalLinks(io, gpa, &urls);

    var written: usize = 0;
    const index = try renderArchiveIndex(gpa, urls.items, versions);
    defer gpa.free(index);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = archive_index_path, .data = index });
    written += 1;

    for (urls.items) |url| {
        const path = try archiveFilePath(gpa, url);
        defer gpa.free(path);
        const page = try renderArchivePage(gpa, url, versions);
        defer gpa.free(page);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = page });
        written += 1;
    }
    return written;
}

fn renderArchiveIndex(gpa: std.mem.Allocator, urls: []const []const u8, versions: AssetVersions) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try appendGeneratedPageHead(gpa, &out, "External link archive registry", "Local metadata records for external links referenced by plosca.ru.", versions);
    try out.appendSlice(gpa, "<main id=\"main\"><article><h1>External link archive registry</h1>\n");
    try out.appendSlice(gpa, "<p>This is a metadata registry, not a copy of third-party pages.</p>\n<ul>\n");
    for (urls) |url| {
        const path = try archivePath(gpa, url);
        defer gpa.free(path);
        try out.appendSlice(gpa, "<li><a href=\"");
        try appendHtmlEscaped(gpa, &out, path);
        try out.appendSlice(gpa, "\">");
        try appendHtmlEscaped(gpa, &out, url);
        try out.appendSlice(gpa, "</a></li>\n");
    }
    try out.appendSlice(gpa, "</ul></article></main></body></html>\n");
    return try out.toOwnedSlice(gpa);
}

fn renderArchivePage(gpa: std.mem.Allocator, url: []const u8, versions: AssetVersions) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try appendGeneratedPageHead(gpa, &out, "Archive record", "Local metadata record for an external link referenced by plosca.ru.", versions);
    try out.appendSlice(gpa, "<main id=\"main\"><article><h1>Archive record</h1>\n");
    try out.appendSlice(gpa, "<p>This page records an external link target so old references remain understandable. It does not store or republish the third-party page.</p>\n");
    try out.appendSlice(gpa, "<dl><dt>URL</dt><dd><a href=\"");
    try appendHtmlEscaped(gpa, &out, url);
    try out.appendSlice(gpa, "\">");
    try appendHtmlEscaped(gpa, &out, url);
    try out.appendSlice(gpa, "</a></dd></dl>\n");
    try out.appendSlice(gpa, "<p><a href=\"/archive\">Back to archive registry</a></p></article></main></body></html>\n");
    return try out.toOwnedSlice(gpa);
}

fn appendGeneratedPageHead(gpa: std.mem.Allocator, out: *std.ArrayList(u8), title: []const u8, description: []const u8, versions: AssetVersions) !void {
    try out.appendSlice(gpa, "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\" />\n");
    try out.appendSlice(gpa, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n<title>");
    try appendHtmlEscaped(gpa, out, title);
    try out.appendSlice(gpa, "</title>\n<meta name=\"description\" content=\"");
    try appendHtmlEscaped(gpa, out, description);
    try out.print(gpa, "\" />\n<meta name=\"theme-color\" content=\"#ffffff\" />\n<script src=\"/theme.js?v={s}\"></script>\n<link rel=\"stylesheet\" href=\"/style.css?v={s}\" />\n</head><body><span id=\"top\" aria-hidden=\"true\"></span>\n", .{ versions.theme[0..], versions.style[0..] });
}

fn writeTextAlternates(io: Io, gpa: std.mem.Allocator) !usize {
    var written: usize = 0;
    for (pages) |page| {
        if (page.kind != .article and page.kind != .prose) continue;
        const html = try readStaticFile(io, gpa, page.file);
        defer gpa.free(html);
        const markdown = try renderTextAlternate(gpa, page, html, true);
        defer gpa.free(markdown);
        const text = try renderTextAlternate(gpa, page, html, false);
        defer gpa.free(text);

        const markdown_path = try std.fmt.allocPrint(gpa, "static/{s}.md", .{page.slug});
        defer gpa.free(markdown_path);
        const text_path = try std.fmt.allocPrint(gpa, "static/{s}.txt", .{page.slug});
        defer gpa.free(text_path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = markdown_path, .data = markdown });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = text_path, .data = text });
        written += 2;
    }
    return written;
}

fn renderTextAlternate(gpa: std.mem.Allocator, page: PageMeta, html: []const u8, markdown: bool) ![]u8 {
    const article = extractElement(html, "article") orelse html;
    const plain = try htmlText(gpa, article);
    defer gpa.free(plain);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    if (markdown) {
        try out.appendSlice(gpa, "# ");
        try out.appendSlice(gpa, page.title);
        try out.appendSlice(gpa, "\n\n");
    } else {
        try out.appendSlice(gpa, page.title);
        try out.appendSlice(gpa, "\n");
        try out.appendNTimes(gpa, '=', page.title.len);
        try out.appendSlice(gpa, "\n\n");
    }
    if (page.date) |date| {
        try out.print(gpa, "Date: {s}\n\n", .{date});
    }
    try out.print(gpa, "Canonical: https://plosca.ru{s}\n\n", .{page.route});
    try out.appendSlice(gpa, page.description);
    try out.appendSlice(gpa, "\n\n---\n\n");
    try out.appendSlice(gpa, std.mem.trim(u8, plain, " \t\r\n"));
    try out.appendSlice(gpa, "\n");
    return try out.toOwnedSlice(gpa);
}

fn htmlText(gpa: std.mem.Allocator, html: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var i: usize = 0;
    var last_space = true;
    while (i < html.len) {
        if (std.mem.startsWith(u8, html[i..], "<nav")) {
            if (std.mem.indexOfPos(u8, html, i, "</nav>")) |end| {
                i = end + "</nav>".len;
                continue;
            }
        }
        if (std.mem.startsWith(u8, html[i..], "<a")) {
            if (std.mem.indexOfPos(u8, html, i, "heading-anchor")) |anchor_marker| {
                const tag_end = std.mem.indexOfScalarPos(u8, html, i, '>') orelse break;
                if (anchor_marker < tag_end) {
                    if (findClosingTag(html, tag_end, "a")) |close| {
                        i = close.end;
                        continue;
                    }
                }
            }
            if (std.mem.indexOfPos(u8, html, i, "up-btn")) |up_marker| {
                const tag_end = std.mem.indexOfScalarPos(u8, html, i, '>') orelse break;
                if (up_marker < tag_end) {
                    if (findClosingTag(html, tag_end, "a")) |close| {
                        i = close.end;
                        continue;
                    }
                }
            }
        }
        if (html[i] == '<') {
            if (std.mem.indexOfScalarPos(u8, html, i, '>')) |end| {
                if (!last_space) {
                    try out.append(gpa, '\n');
                    last_space = true;
                }
                i = end + 1;
                continue;
            }
        }
        if (html[i] == '&') {
            if (try appendDecodedEntity(gpa, &out, html[i..])) |consumed| {
                i += consumed;
                last_space = false;
                continue;
            }
        }
        if (std.ascii.isWhitespace(html[i])) {
            if (!last_space) {
                try out.append(gpa, ' ');
                last_space = true;
            }
        } else {
            try out.append(gpa, html[i]);
            last_space = false;
        }
        i += 1;
    }
    return try out.toOwnedSlice(gpa);
}

const ClosingTag = struct {
    start: usize,
    end: usize,
};

fn findClosingTag(html: []const u8, start: usize, tag_name: []const u8) ?ClosingTag {
    const needle = std.fmt.allocPrint(std.heap.page_allocator, "</{s}", .{tag_name}) catch return null;
    defer std.heap.page_allocator.free(needle);

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

fn appendDecodedEntity(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !?usize {
    const entities = [_]struct { encoded: []const u8, decoded: []const u8 }{
        .{ .encoded = "&amp;", .decoded = "&" },
        .{ .encoded = "&lt;", .decoded = "<" },
        .{ .encoded = "&gt;", .decoded = ">" },
        .{ .encoded = "&quot;", .decoded = "\"" },
        .{ .encoded = "&#39;", .decoded = "'" },
        .{ .encoded = "&nbsp;", .decoded = " " },
    };
    for (entities) |entity| {
        if (std.mem.startsWith(u8, text, entity.encoded)) {
            try out.appendSlice(gpa, entity.decoded);
            return entity.encoded.len;
        }
    }
    return null;
}

fn archivePath(gpa: std.mem.Allocator, url: []const u8) ![]u8 {
    const digest = shortHash(url);
    return try std.fmt.allocPrint(gpa, "/archive/{s}.html", .{digest[0..]});
}

fn archiveFilePath(gpa: std.mem.Allocator, url: []const u8) ![]u8 {
    const digest = shortHash(url);
    return try std.fmt.allocPrint(gpa, "static/archive/{s}.html", .{digest[0..]});
}

fn shortHash(value: []const u8) [16]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(value);
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

fn containsString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}

fn freeStringList(gpa: std.mem.Allocator, list: *std.ArrayList([]u8)) void {
    for (list.items) |item| gpa.free(item);
    list.deinit(gpa);
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

fn syncHtmlAssetRefs(io: Io, gpa: std.mem.Allocator, versions: AssetVersions, write: bool) !usize {
    var static_dir = try Io.Dir.cwd().openDir(io, static_dir_path, .{ .iterate = true });
    defer static_dir.close(io);

    var updated_or_failed: usize = 0;
    var it = static_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".html")) continue;

        const html = try static_dir.readFileAlloc(io, entry.name, gpa, .limited(max_file_size));
        defer gpa.free(html);

        const result = try rewriteAssetRefs(gpa, html, versions);
        defer gpa.free(result.html);

        if (write) {
            if (!std.mem.eql(u8, html, result.html)) {
                try static_dir.writeFile(io, .{ .sub_path = entry.name, .data = result.html });
                updated_or_failed += 1;
            }
        } else {
            if (result.style_refs == 0) {
                std.debug.print("static/{s}: no stylesheet href found\n", .{entry.name});
                updated_or_failed += 1;
            }
            if (result.theme_refs == 0) {
                std.debug.print("static/{s}: no theme.js script found\n", .{entry.name});
                updated_or_failed += 1;
            }
            if (result.mismatches != 0) {
                std.debug.print("static/{s}: first-party asset refs are not synchronized; run `zig build css`\n", .{entry.name});
                updated_or_failed += result.mismatches;
            }
        }
    }

    return updated_or_failed;
}

const RewriteResult = struct {
    html: []u8,
    style_refs: usize,
    theme_refs: usize,
    site_features_refs: usize,
    mismatches: usize,
};

const SingleRewriteResult = struct {
    html: []u8,
    refs: usize,
    mismatches: usize,
};

fn rewriteAssetRefs(gpa: std.mem.Allocator, html: []const u8, versions: AssetVersions) !RewriteResult {
    const stylesheet = try std.fmt.allocPrint(gpa, "/style.css?v={s}", .{versions.style[0..]});
    defer gpa.free(stylesheet);
    const theme = try std.fmt.allocPrint(gpa, "/theme.js?v={s}", .{versions.theme[0..]});
    defer gpa.free(theme);
    const site_features = try std.fmt.allocPrint(gpa, "/site-features.js?v={s}", .{versions.site_features[0..]});
    defer gpa.free(site_features);

    const style_result = try rewriteSingleAssetRef(gpa, html, "href=", "/style.css", stylesheet);
    errdefer gpa.free(style_result.html);
    const theme_result = try rewriteSingleAssetRef(gpa, style_result.html, "src=", "/theme.js", theme);
    gpa.free(style_result.html);
    errdefer gpa.free(theme_result.html);
    const site_features_result = try rewriteSingleAssetRef(gpa, theme_result.html, "src=", "/site-features.js", site_features);
    gpa.free(theme_result.html);

    return .{
        .html = site_features_result.html,
        .style_refs = style_result.refs,
        .theme_refs = theme_result.refs,
        .site_features_refs = site_features_result.refs,
        .mismatches = style_result.mismatches + theme_result.mismatches + site_features_result.mismatches,
    };
}

fn rewriteSingleAssetRef(gpa: std.mem.Allocator, html: []const u8, attr: []const u8, base_ref: []const u8, versioned_ref: []const u8) !SingleRewriteResult {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var cursor: usize = 0;
    var search_pos: usize = 0;
    var refs: usize = 0;
    var mismatches: usize = 0;

    while (std.mem.indexOfPos(u8, html, search_pos, attr)) |href_pos| {
        const quote_pos = href_pos + attr.len;
        if (quote_pos >= html.len) break;
        const quote = html[quote_pos];
        if (quote != '"' and quote != '\'') {
            search_pos = quote_pos + 1;
            continue;
        }

        const value_start = quote_pos + 1;
        if (!std.mem.startsWith(u8, html[value_start..], base_ref)) {
            search_pos = value_start;
            continue;
        }

        const value_end = std.mem.indexOfScalarPos(u8, html, value_start, quote) orelse return error.InvalidHtml;
        refs += 1;
        if (!std.mem.eql(u8, html[value_start..value_end], versioned_ref)) mismatches += 1;

        try out.appendSlice(gpa, html[cursor..value_start]);
        try out.appendSlice(gpa, versioned_ref);
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
        const close = findClosingTag(html, tag_end + 1, "a") orelse break;
        const tag = html[anchor_start..tag_end];
        const inner = html[tag_end + 1 .. close.start];
        if (!anchorHasReadableContent(inner) and !std.mem.containsAtLeast(u8, tag, 1, "href=\"#cb")) {
            std.debug.print("static/{s}: anchor has no readable text near byte {d}\n", .{ page.file, anchor_start });
            failures += 1;
        }
        search_pos = close.end;
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

    return try fileExists(io, gpa, path);
}

fn fileExists(io: Io, gpa: std.mem.Allocator, path: []const u8) !bool {
    _ = gpa;
    var file = Io.Dir.cwd().openFile(io, path, .{ .allow_directory = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    file.close(io);
    return true;
}
