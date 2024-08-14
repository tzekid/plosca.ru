const std = @import("std");
const zap = @import("zap");
const print = std.debug.print;

const STATIC_FOLDER = "static_old";

const MyHashContext = struct {
    pub fn hash(self: @This(), key: []const u8) u64 {
        _ = self;

        return std.hash.Wyhash.hash(0, key);
    }

    pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
        _ = self;
        return std.mem.eql(u8, a, b);
    }
};

const FileCache = std.hash_map.HashMap([]const u8, []const u8, MyHashContext, std.hash_map.default_max_load_percentage);

var file_cache = FileCache.init(std.heap.page_allocator);

fn readFileToString(allocator: std.mem.Allocator, file_path: []const u8) !?[]const u8 {
    if (file_cache.get(file_path)) |file_contents| {
        print("Serving file '{s}' from cache\n", .{file_path});
        return file_contents;
    } else {
        print("File '{s}' is not cached\n", .{file_path});
    }

    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        print("Failed to open file '{s}': {}", .{ file_path, err });
        return null;
    };
    defer file.close();

    const file_contents = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| {
        print("Failed to read file '{s}': {}", .{ file_path, err });
        return null;
    };

    file_cache.put(file_path, file_contents) catch {
        print("Failed to cache file '{s}'\n", .{file_path});
        allocator.free(file_contents);
        return null;
    };

    print("File '{s}' cached\n", .{file_path});
    return file_contents;
}

fn onRequest(r: zap.Request) void {
    r.setStatus(.not_found);

    const file_path: []const u8 = STATIC_FOLDER ++ "/404.html";

    const err_404_page: []const u8 = readFileToString(std.heap.page_allocator, file_path) catch |err| {
        std.log.err("Error: {}", .{err});
        return;
    } orelse {
        std.log.err("File '{s}' is empty or could not be read", .{file_path});
        return;
    };

    r.setStatus(.not_found);

    r.sendBody(err_404_page) catch return;
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = onRequest,
        .public_folder = STATIC_FOLDER,
        .log = true,
    });

    try listener.listen();

    std.debug.print("\nListening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });

    file_cache.deinit();
}
//
