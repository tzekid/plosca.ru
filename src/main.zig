const std = @import("std");
const zap = @import("zap");
const print = std.debug.print;

// TODO: replace std.mem.Allocator w/ an arena alloc
fn readFileToString(allocator: std.mem.Allocator, file_path: []const u8) !?[]u8 {
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
    r.setStatus(.not_found);

    const file_path = "static_old/404.html";
    const err_404_page = readFileToString(std.heap.page_allocator, file_path) catch |err| {
        std.log.err("Error: {}", .{err});
        return;
    } orelse {
        std.log.err("File '{s}' is empty or could not be read", .{file_path});
        return;
    };
    defer std.heap.page_allocator.free(err_404_page);

    r.sendBody(err_404_page) catch return;
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = onRequest,
        .public_folder = "static_old",
        .log = true,
    });
    try listener.listen();

    std.debug.print("\nListening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
