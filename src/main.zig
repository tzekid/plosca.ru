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

        r.setContentTypeFromFilename(file_path) catch {
            r.setStatus(.not_found);
            r.sendFile(STATIC_FOLDER ++ "/404.html") catch return;
        };
        r.sendFile(file_path) catch {
            r.setStatus(.not_found);
            r.sendFile(STATIC_FOLDER ++ "/404.html") catch return;
        };
    }
}

pub fn main() !void {
    // TODO: compile md -> html

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = onRequest,
        .log = true,
    });

    try listener.listen();

    std.debug.print("\nListening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 8,
        .workers = 8,
    });
}
