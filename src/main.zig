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
    if (r.path) |the_path| {
        var file_contents: ?[]const u8 = null;
        var content_type: []const u8 = "text/plain; charset=utf-8"; // default

        if (std.mem.eql(u8, the_path, "/") or std.mem.eql(u8, the_path, "")) {
            const file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/index.html", .{STATIC_FOLDER}) catch |err| {
                std.log.err("Error allocating memory for file path: {}", .{err});
                return;
            };

            file_contents = readFileToString(std.heap.page_allocator, file_path) catch {
                // serve 404
                const file_path_404 = STATIC_FOLDER ++ "/404.html";
                const err_404_page = readFileToString(std.heap.page_allocator, file_path_404) catch |err_404| {
                    std.log.err("Error reading 404 page: {}", .{err_404});
                    return; // Or handle this error in another way
                    // } orelse unreachable; // We assume 404.html exists and can be read
                } orelse {
                    r.setStatus(.not_found);
                    r.sendBody("404") catch return;
                };

                r.setStatus(.not_found);
                r.sendBody(err_404_page) catch return;
            };
        } else if (std.mem.indexOf(u8, the_path, ".")) |_| {
            const file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ STATIC_FOLDER, the_path }) catch |err| {
                std.log.err("Error allocating memory for file path: {}", .{err});
                return;
            };

            file_contents = readFileToString(std.heap.page_allocator, file_path) catch {
                // serve 404
                const file_path_404 = STATIC_FOLDER ++ "/404.html";
                const err_404_page = readFileToString(std.heap.page_allocator, file_path_404) catch |err_404| {
                    std.log.err("Error reading 404 page: {}", .{err_404});
                    return; // Or handle this error in another way
                    // } orelse unreachable; // We assume 404.html exists and can be read
                } orelse {
                    r.setStatus(.not_found);
                    r.sendBody("404") catch return;
                };

                r.setStatus(.not_found);
                r.sendBody(err_404_page) catch return;
            };
        } else {
            const file_path_with_html = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ STATIC_FOLDER, the_path }) catch |err| {
                std.log.err("Error allocating memory for file path: {}", .{err});
                return;
            };

            file_contents = readFileToString(std.heap.page_allocator, file_path_with_html) catch {
                // serve 404
                const file_path_404 = STATIC_FOLDER ++ "/404.html";
                const err_404_page = readFileToString(std.heap.page_allocator, file_path_404) catch |err_404| {
                    std.log.err("Error reading 404 page: {}", .{err_404});
                    return; // Or handle this error in another way
                } orelse unreachable;

                r.setStatus(.not_found);
                r.sendBody(err_404_page) catch return;
            };
        }

        if (file_contents) |contents| {
            // if (std.mem.endsWith(u8, the_path, ".html")) {
            if (std.mem.eql(u8, the_path, "/") or std.mem.eql(u8, the_path, "") or std.mem.endsWith(u8, the_path, ".html") {
                content_type = "text/html; charset=utf-8";
            } else if (std.mem.endsWith(u8, the_path, ".css")) {
                content_type = "text/css; charset=utf-8";
            } else if (std.mem.endsWith(u8, the_path, ".js")) {
                content_type = "text/javascript; charset=utf-8";
            } // Add more cases for other file types as needed

            r.setHeader("Content-Type", content_type) catch return;
            r.sendBody(contents) catch return;
        } else {
            const file_path_404 = STATIC_FOLDER ++ "/404.html";
            const err_404_page = readFileToString(std.heap.page_allocator, file_path_404) catch |err_404| {
                std.log.err("Error reading 404 page: {}", .{err_404});
                return;
            } orelse unreachable;

            r.setStatus(.not_found);
            r.sendBody(err_404_page) catch return;
        }
    }
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = onRequest,
        // .public_folder = STATIC_FOLDER,
        .log = true,
    });

    try listener.listen();

    std.debug.print("\nListening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 8,
        .workers = 8,
    });

    file_cache.deinit();
}
