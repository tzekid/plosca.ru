const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "webapp",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the static site server");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
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
}
