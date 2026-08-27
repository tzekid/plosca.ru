const std = @import("std");
const render = @import("render.zig");

const Io = std.Io;
const max_asset_size = 32 * 1024 * 1024;

pub const Versions = struct {
    style: [16]u8,
    theme: [16]u8,
    preview: [16]u8,
};

pub const Copy = struct {
    source: []const u8,
    output: []const u8,
};

pub const copies = [_]Copy{
    .{ .source = "assets/style.css", .output = "style.css" },
    .{ .source = "assets/theme.js", .output = "theme.js" },
    .{ .source = "assets/preview.js", .output = "preview.js" },
    .{ .source = "assets/fonts/6xKtdSZaM9iE8KbpRA_hK1QN.woff2", .output = "6xKtdSZaM9iE8KbpRA_hK1QN.woff2" },
    .{ .source = "assets/fonts/PH1InQe0rvp_yN3TzIuyyQ.woff2", .output = "PH1InQe0rvp_yN3TzIuyyQ.woff2" },
    .{ .source = "assets/images/resume-preview-27833c1a5937f8c5.jpg", .output = "resume-preview-27833c1a5937f8c5.jpg" },
    .{ .source = "assets/icons/android-chrome-192x192.png", .output = "android-chrome-192x192.png" },
    .{ .source = "assets/icons/android-chrome-384x384.png", .output = "android-chrome-384x384.png" },
    .{ .source = "assets/icons/android-chrome-512x512.png", .output = "android-chrome-512x512.png" },
    .{ .source = "assets/icons/apple-touch-icon.png", .output = "apple-touch-icon.png" },
    .{ .source = "assets/icons/favicon-16x16.png", .output = "favicon-16x16.png" },
    .{ .source = "assets/icons/favicon-32x32.png", .output = "favicon-32x32.png" },
    .{ .source = "assets/icons/mstile-70x70.png", .output = "mstile-70x70.png" },
    .{ .source = "assets/icons/mstile-144x144.png", .output = "mstile-144x144.png" },
    .{ .source = "assets/icons/mstile-150x150.png", .output = "mstile-150x150.png" },
    .{ .source = "assets/icons/mstile-310x150.png", .output = "mstile-310x150.png" },
    .{ .source = "assets/icons/mstile-310x310.png", .output = "mstile-310x310.png" },
    .{ .source = "assets/resume.pdf", .output = "resume.pdf" },
    .{ .source = "assets/robots.txt", .output = "robots.txt" },
    .{ .source = "assets/site.webmanifest", .output = "site.webmanifest" },
    .{ .source = "assets/sitemap.xml", .output = "sitemap.xml" },
    .{ .source = "assets/hello_world.md", .output = "hello_world.md" },
    .{ .source = "assets/hello_world.txt", .output = "hello_world.txt" },
    .{ .source = "assets/prose.md", .output = "prose.md" },
    .{ .source = "assets/prose.txt", .output = "prose.txt" },
};

pub fn readVersions(io: Io, allocator: std.mem.Allocator) !Versions {
    return .{
        .style = try hashFile(io, allocator, "assets/style.css"),
        .theme = try hashFile(io, allocator, "assets/theme.js"),
        .preview = try hashFile(io, allocator, "assets/preview.js"),
    };
}

pub fn urls(allocator: std.mem.Allocator, versions: Versions) !render.AssetUrls {
    return .{
        .style = try std.fmt.allocPrint(allocator, "/style.css?v={s}", .{&versions.style}),
        .theme = try std.fmt.allocPrint(allocator, "/theme.js?v={s}", .{&versions.theme}),
        .preview = try std.fmt.allocPrint(allocator, "/preview.js?v={s}", .{&versions.preview}),
    };
}

pub fn copyAll(io: Io, output_root: []const u8, allocator: std.mem.Allocator) !void {
    const cwd = Io.Dir.cwd();
    for (copies) |entry| {
        const destination = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_root, entry.output });
        defer allocator.free(destination);
        try cwd.copyFile(entry.source, cwd, destination, io, .{ .replace = true, .make_path = true });
    }
}

fn hashFile(io: Io, allocator: std.mem.Allocator, path: []const u8) ![16]u8 {
    const data = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_asset_size));
    defer allocator.free(data);
    return render.contentHash(data);
}
