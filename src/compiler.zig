const std = @import("std");
const assets = @import("assets.zig");
const content = @import("content_manifest");
const graph = @import("graph.zig");
const previews = @import("previews.zig");
const render = @import("render.zig");
const validate = @import("validate.zig");

const Io = std.Io;
const output_path = "dist";
const temporary_path = "dist.tmp";
const backup_path = "dist.previous";
const max_page_size = 16 * 1024 * 1024;

pub fn buildSite(io: Io, gpa: std.mem.Allocator) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cwd = Io.Dir.cwd();

    try cwd.deleteTree(io, temporary_path);
    try validate.source(io, arena, &content.pages);
    const versions = try assets.readVersions(io, arena);
    const asset_urls = try assets.urls(arena, versions);
    const sources = try loadSources(io, arena);

    try cwd.createDirPath(io, temporary_path);
    errdefer cwd.deleteTree(io, temporary_path) catch {};

    const preview_count = try compileTo(io, arena, temporary_path, sources, asset_urls);
    try validate.dist(io, arena, temporary_path, &content.pages, preview_count);
    try publish(io);

    std.debug.print(
        "built {s}: {d} pages, {d} previews, assets style={s} theme={s} preview={s}\n",
        .{ output_path, content.pages.len, preview_count, &versions.style, &versions.theme, &versions.preview },
    );
}

pub fn checkSite(io: Io, gpa: std.mem.Allocator) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cwd = Io.Dir.cwd();
    try cwd.deleteTree(io, temporary_path);
    errdefer cwd.deleteTree(io, temporary_path) catch {};
    try validate.source(io, arena, &content.pages);
    const versions = try assets.readVersions(io, arena);
    const asset_urls = try assets.urls(arena, versions);
    const sources = try loadSources(io, arena);
    try cwd.createDirPath(io, temporary_path);
    const preview_count = try compileTo(io, arena, temporary_path, sources, asset_urls);
    try validate.dist(io, arena, temporary_path, &content.pages, preview_count);
    try validate.dist(io, arena, output_path, &content.pages, preview_count);
    if (!try directoriesEqual(io, arena, temporary_path, output_path)) {
        std.debug.print("{s} is not synchronized with authored source; run `sitec build`\n", .{output_path});
        return error.OutputOutOfDate;
    }
    try cwd.deleteTree(io, temporary_path);
    std.debug.print("site check passed: {d} pages, {d} previews\n", .{ content.pages.len, preview_count });
}

fn compileTo(
    io: Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    sources: []const graph.Source,
    asset_urls: render.AssetUrls,
) !usize {
    try assets.copyAll(io, root, allocator);
    try writePages(io, allocator, root, sources, asset_urls);
    try writeArchive(io, allocator, root, asset_urls);
    return previews.writeAll(io, allocator, root, &content.pages, content.site, sources);
}

fn loadSources(io: Io, allocator: std.mem.Allocator) ![]graph.Source {
    const sources = try allocator.alloc(graph.Source, content.pages.len);
    for (&content.pages, 0..) |page, index| {
        const path = try std.fmt.allocPrint(allocator, "content/pages/{s}", .{page.file});
        const html = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_page_size));
        sources[index] = .{ .page = page, .html = html };
    }
    return sources;
}

fn writePages(
    io: Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    sources: []const graph.Source,
    asset_urls: render.AssetUrls,
) !void {
    for (sources) |source| {
        const generated_connections: ?graph.Connections = if (source.page.kind == .article or source.page.kind == .prose)
            try graph.build(allocator, source.page, &content.pages, sources)
        else
            null;
        defer if (generated_connections) |connections| connections.deinit(allocator);

        const html = try render.page(allocator, source.html, generated_connections, asset_urls);
        defer allocator.free(html);
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, source.page.file });
        defer allocator.free(path);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = html });
    }
}

fn writeArchive(io: Io, allocator: std.mem.Allocator, root: []const u8, asset_urls: render.AssetUrls) !void {
    const cwd = Io.Dir.cwd();
    const output_dir = try std.fmt.allocPrint(allocator, "{s}/archive", .{root});
    defer allocator.free(output_dir);
    try cwd.createDirPath(io, output_dir);

    var source_dir = try cwd.openDir(io, "assets/archive", .{ .iterate = true });
    defer source_dir.close(io);
    var iterator = source_dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".html")) return error.InvalidArchiveAsset;
        const source_path = try std.fmt.allocPrint(allocator, "assets/archive/{s}", .{entry.name});
        defer allocator.free(source_path);
        const authored = try cwd.readFileAlloc(io, source_path, allocator, .limited(max_page_size));
        defer allocator.free(authored);
        const html = try render.archivePage(allocator, authored, asset_urls);
        defer allocator.free(html);
        const destination = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ output_dir, entry.name });
        defer allocator.free(destination);
        try cwd.writeFile(io, .{ .sub_path = destination, .data = html });
    }
}

fn publish(io: Io) !void {
    const cwd = Io.Dir.cwd();
    try cwd.deleteTree(io, backup_path);

    const had_output = try directoryExists(io, output_path);
    if (had_output) try cwd.rename(output_path, cwd, backup_path, io);
    errdefer if (had_output) cwd.rename(backup_path, cwd, output_path, io) catch {};

    try cwd.rename(temporary_path, cwd, output_path, io);
    if (had_output) cwd.deleteTree(io, backup_path) catch |err| {
        std.debug.print("warning: built site published but could not remove {s}: {s}\n", .{ backup_path, @errorName(err) });
    };
}

fn directoryExists(io: Io, path: []const u8) !bool {
    var dir = Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |other| return other,
    };
    dir.close(io);
    return true;
}

fn directoriesEqual(io: Io, allocator: std.mem.Allocator, left_path: []const u8, right_path: []const u8) !bool {
    const cwd = Io.Dir.cwd();
    var left_dir = try cwd.openDir(io, left_path, .{ .iterate = true });
    defer left_dir.close(io);
    var right_dir = try cwd.openDir(io, right_path, .{ .iterate = true });
    defer right_dir.close(io);

    var left_count: usize = 0;
    var left_iterator = left_dir.iterate();
    while (try left_iterator.next(io)) |entry| {
        left_count += 1;
        const left_child = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ left_path, entry.name });
        defer allocator.free(left_child);
        const right_child = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ right_path, entry.name });
        defer allocator.free(right_child);
        const right_stat = cwd.statFile(io, right_child, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => |other| return other,
        };

        if (entry.kind == .directory and right_stat.kind == .directory) {
            if (!try directoriesEqual(io, allocator, left_child, right_child)) return false;
        } else if (entry.kind == .file and right_stat.kind == .file) {
            const left_data = try cwd.readFileAlloc(io, left_child, allocator, .limited(max_page_size));
            defer allocator.free(left_data);
            const right_data = try cwd.readFileAlloc(io, right_child, allocator, .limited(max_page_size));
            defer allocator.free(right_data);
            if (!std.mem.eql(u8, left_data, right_data)) return false;
        } else {
            return false;
        }
    }

    var right_count: usize = 0;
    var right_iterator = right_dir.iterate();
    while (try right_iterator.next(io)) |_| {
        right_count += 1;
    }
    return left_count == right_count;
}
