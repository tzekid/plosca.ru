const std = @import("std");
const zap = @import("zap");
const print = std.debug.print;

const STATIC_FOLDER = "static_old";

fn readFileToString(allocator: std.mem.Allocator, file_path: []const u8) !?[]const u8 {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        print("Failed to open file '{s}': {}", .{ file_path, err });
        return null;
    };
    defer file.close();

    const file_contents = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| {
        print("Failed to read file '{s}': {}", .{ file_path, err });
        return null;
    };

    return file_contents;
}

fn onRequest(r: zap.Request) void {
    if (r.path) |the_path| {
        var file_path: []const u8 = "";

        if (std.mem.eql(u8, the_path, "/") or std.mem.eql(u8, the_path, "")) {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/index.html", .{STATIC_FOLDER}) catch return;
        } else if (std.mem.indexOf(u8, the_path, ".")) |_| {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ STATIC_FOLDER, the_path }) catch return;
        } else {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ STATIC_FOLDER, the_path }) catch return;
        }

        const file_contents = readFileToString(std.heap.page_allocator, file_path) catch {
            // Handle the error and serve 404
            const file_path_404 = STATIC_FOLDER ++ "/404.html";
            const err_404_page = readFileToString(std.heap.page_allocator, file_path_404) catch |err_404| {
                std.log.err("Error reading 404 page: {}", .{err_404});
                return;
            } orelse {
                r.setStatus(.not_found);
                r.sendBody("404") catch return;
            };

            r.setStatus(.not_found);
            r.sendBody(err_404_page) catch return;
        };

        if (file_contents) |contents| {
            r.setStatus(.ok);
            r.setContentTypeFromFilename(file_path) catch return;
            r.sendBody(contents) catch return;
        }
    }
}

pub fn main() !void {
    // TODO: compile md -> html

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

    // file_cache.deinit();
}
