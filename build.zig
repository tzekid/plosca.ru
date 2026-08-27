const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const manifest_mod = b.createModule(.{
        .root_source_file = b.path("src/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const content_manifest_mod = b.createModule(.{
        .root_source_file = b.path("content/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    content_manifest_mod.addImport("manifest", manifest_mod);

    const sitec_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    sitec_mod.addImport("manifest", manifest_mod);
    sitec_mod.addImport("content_manifest", content_manifest_mod);

    const sitec = b.addExecutable(.{
        .name = "sitec",
        .root_module = sitec_mod,
    });
    b.installArtifact(sitec);

    const run_cmd = b.addRunArtifact(sitec);
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run sitec");
    run_step.dependOn(&run_cmd.step);

    const build_cmd = b.addRunArtifact(sitec);
    build_cmd.addArg("build");
    const site_step = b.step("site", "Compile the complete site into dist/");
    site_step.dependOn(&build_cmd.step);

    const check_cmd = b.addRunArtifact(sitec);
    check_cmd.addArg("check");
    const check_step = b.step("check-site", "Validate authored inputs and dist/");
    check_step.dependOn(&check_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("manifest", manifest_mod);
    test_mod.addImport("content_manifest", content_manifest_mod);
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run compiler tests");
    test_step.dependOn(&run_tests.step);

    const deterministic_cmd = b.addSystemCommand(&.{ "bash", "tests/deterministic-build.sh" });
    deterministic_cmd.addArtifactArg(sitec);
    const deterministic_step = b.step("deterministic-build", "Build dist twice and compare every byte");
    deterministic_step.dependOn(&deterministic_cmd.step);

    const browser_smoke_cmd = b.addSystemCommand(&.{ "bash", "tests/browser-smoke.sh" });
    browser_smoke_cmd.addArtifactArg(sitec);
    const browser_smoke_step = b.step("browser-smoke", "Run Caddy/Chromium acceptance checks");
    browser_smoke_step.dependOn(&browser_smoke_cmd.step);
}
