const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const web = b.dependency("web", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("web_assets", web.module("web_assets"));
    exe_mod.addImport("web_security_headers", web.module("web_security_headers"));
    exe_mod.addImport("web_server", web.module("web_server"));

    const exe = b.addExecutable(.{
        .name = "webapp",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the static site server");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("web_assets", web.module("web_assets"));
    test_mod.addImport("web_security_headers", web.module("web_security_headers"));
    test_mod.addImport("web_server", web.module("web_server"));
    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const site_tool_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/site.zig"),
        .target = target,
        .optimize = optimize,
    });
    const site_model_mod = b.createModule(.{
        .root_source_file = b.path("src/site/model.zig"),
        .target = target,
        .optimize = optimize,
    });
    const site_views_mod = b.createModule(.{
        .root_source_file = b.path("src/site/views.zig"),
        .target = target,
        .optimize = optimize,
    });
    site_views_mod.addImport("site_model", site_model_mod);
    site_views_mod.addImport("web_html", web.module("web_html"));
    const site_http_cache_mod = b.createModule(.{
        .root_source_file = b.path("src/site/http_cache.zig"),
        .target = target,
        .optimize = optimize,
    });
    site_http_cache_mod.addImport("web_cache", web.module("web_cache"));
    exe_mod.addImport("site_http_cache", site_http_cache_mod);
    test_mod.addImport("site_http_cache", site_http_cache_mod);
    site_tool_mod.addImport("site_model", site_model_mod);
    site_tool_mod.addImport("site_views", site_views_mod);
    site_tool_mod.addImport("web_htmx", web.module("web_htmx"));
    const site_view_tests = b.addTest(.{
        .root_module = site_views_mod,
    });
    const run_site_view_tests = b.addRunArtifact(site_view_tests);
    test_step.dependOn(&run_site_view_tests.step);
    const site_http_cache_tests = b.addTest(.{
        .root_module = site_http_cache_mod,
    });
    test_step.dependOn(&b.addRunArtifact(site_http_cache_tests).step);
    const site_tool = b.addExecutable(.{
        .name = "site-tool",
        .root_module = site_tool_mod,
    });

    const css_cmd = b.addRunArtifact(site_tool);
    css_cmd.addArg("write");
    const css_step = b.step("css", "Generate static/style.css and update HTML cache-busters");
    css_step.dependOn(&css_cmd.step);

    const check_site_cmd = b.addRunArtifact(site_tool);
    check_site_cmd.addArg("check");
    const check_site_step = b.step("check-site", "Check generated CSS, cache-busters, and local asset references");
    check_site_step.dependOn(&check_site_cmd.step);

    const enrich_links_cmd = b.addRunArtifact(site_tool);
    enrich_links_cmd.addArg("enrich-links");
    const enrich_links_step = b.step("enrich-links", "Refresh cached external-link context with curl");
    enrich_links_step.dependOn(&enrich_links_cmd.step);

    const pdf_previews_cmd = b.addRunArtifact(site_tool);
    pdf_previews_cmd.addArg("pdf-previews");
    const pdf_previews_step = b.step("pdf-previews", "Render committed PDF preview images with pdftoppm");
    pdf_previews_step.dependOn(&pdf_previews_cmd.step);

    const compress_assets_cmd = b.addRunArtifact(site_tool);
    compress_assets_cmd.addArg("compress-assets");
    const compress_assets_step = b.step("compress-assets", "Generate committed .br/.gz siblings for text static assets");
    compress_assets_step.dependOn(&compress_assets_cmd.step);
}
