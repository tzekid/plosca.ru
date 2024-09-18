const std = @import("std");
const zap = @import("zap");
const zd = @import("zigdown");

const fs = std.fs;

const MARKDOWN_FOLDER = "markdown";
const PUBLIC_FOLDER = "public";
const STATIC_FOLDER = "static_old";

// TODO: delete all html files in public folder
// fn cleanPublicFolder() !void {
// }

fn render(stream: anytype, md: zd.Block) !void {
    var h_renderer = zd.htmlRenderer(stream, md.allocator());
    defer h_renderer.deinit();
    try h_renderer.renderBlock(md);
}

fn compileMarkdownToHtml() !void {
    var dir = try fs.cwd().openDir(MARKDOWN_FOLDER, .{});
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".md")) {
            const markdown_file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ MARKDOWN_FOLDER, entry.name });
            defer std.heap.page_allocator.free(markdown_file_path);

            const html_file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ PUBLIC_FOLDER, std.fs.path.basename(entry.name) });
            defer std.heap.page_allocator.free(html_file_path);

            std.debug.print("Compiling '{s}'\n", .{html_file_path});

            var file = try dir.openFile(entry.name, .{});
            defer file.close();

            const file_contents = file.readToEndAlloc(std.heap.page_allocator, std.math.maxInt(usize)) catch unreachable;
            defer std.heap.page_allocator.free(file_contents);

            const alloc = std.heap.page_allocator;
            const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
            var parser = zd.Parser.init(alloc, opts);
            defer parser.deinit();

            parser.parseMarkdown(file_contents) catch unreachable;
            const md: zd.Block = parser.document;

            // TODO: omit <html> and <body> tags
            // TODO: wrap in <article> tag
            // TODO: figure out how to insert header and footer

            const dest_file = try fs.cwd().createFile(html_file_path, .{ .read = true });
            defer dest_file.close();

            // // render to file
            render(dest_file.writer(), md) catch unreachable;
        }
    }
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
    // try cleanPublicFolder();
    // try compileMarkdownToHtml();

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = onRequest,
        .log = true,
    });

    try listener.listen();

    std.debug.print("\nListening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        // as per `/zap/tools/docserver.zig` for static stuff
        .threads = 2,
        .workers = 1,
    });
}
