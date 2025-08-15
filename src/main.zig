const std = @import("std");
const fs = std.fs;

const zap = @import("zap");
const zd = @import("zigdown");

const markdown_folder = "markdown";
const public_folder = "public";
const static_folder = "static_old";

// fn cleanPublicFolder() !void {
//     var dir = try fs.cwd().openDir(public_folder, .{ .iterate = true });
//     defer dir.close();

//     var iterator = dir.iterate();
//     while (try iterator.next()) |entry| {
//         if (std.mem.endsWith(u8, entry.name, ".html")) {
//             try dir.deleteFile(entry.name);
//         }
//     }
// }

/// Render a parsed markdown root block to an output stream as HTML.
/// The renderer allocates transient state with the markdown's allocator.
fn render(stream: anytype, md: zd.Block) !void {
    var h_renderer = zd.htmlRenderer(stream, md.allocator());
    defer h_renderer.deinit();
    try h_renderer.renderBlock(md);
}

// fn compileMarkdownToHtml() !void {
//     var dir = try fs.cwd().openDir(markdown_folder, .{ .iterate = true });
//     defer dir.close();

//     var iterator = dir.iterate();
//     while (try iterator.next()) |entry| {
//         if (std.mem.endsWith(u8, entry.name, ".md")) {
//             const markdown_file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ markdown_folder, entry.name });
//             defer std.heap.page_allocator.free(markdown_file_path);

//             const basename = std.fs.path.stem(entry.name);
//             const html_file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ public_folder, basename });
//             defer std.heap.page_allocator.free(html_file_path);

//             std.debug.print("Compiling '{s}'\n", .{html_file_path});

//             var file = try dir.openFile(entry.name, .{});
//             defer file.close();

//             const file_contents = try file.readToEndAlloc(std.heap.page_allocator, std.math.maxInt(usize));
//             defer std.heap.page_allocator.free(file_contents);

//             const alloc = std.heap.page_allocator;
//             const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
//             var parser = zd.Parser.init(alloc, opts);
//             defer parser.deinit();

//             try parser.parseMarkdown(file_contents);
//             const md: zd.Block = parser.document;

//             // TODO: omit <html> and <body> tags
//             // TODO: wrap in <article> tag
//             // TODO: figure out how to insert header and footer

//             const dest_file = try fs.cwd().createFile(html_file_path, .{ .read = true });
//             defer dest_file.close();

//             try render(dest_file.writer(), md);
//         }
//     }
// }

/// zap request handler:
/// - Normalizes the requested path into a file in STATIC_FOLDER.
/// - Adds ".html" when the path has no '.' (treat as a logical page).
/// - Defaults "/" and "" to "index.html".
/// - Sets MIME based on the resolved filename; falls back to 404 on errors.
fn onRequest(r: zap.Request) void {
    if (r.path) |the_path| {
        var file_path: []const u8 = "";

        if (std.mem.eql(u8, the_path, "/") or std.mem.eql(u8, the_path, "")) {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/index.html", .{static_folder}) catch return;
        } else if (std.mem.indexOf(u8, the_path, ".")) |_| {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ static_folder, the_path }) catch return;
        } else {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ static_folder, the_path }) catch return;
        }

        // Best-effort content type; if it fails, serve 404 page.
        r.setContentTypeFromFilename(file_path) catch {
            r.setStatus(.not_found);
            r.sendFile(static_folder ++ "/404.html") catch return;
        };

        r.sendFile(file_path) catch {
            r.setStatus(.not_found);
            r.sendFile(static_folder ++ "/404.html") catch return;
        };
    }
}

/// Entry point:
/// (Currently) only starts the zap HTTP server serving STATIC_FOLDER.
/// Markdown compilation is disabled (uncomment to enable build-on-start).
pub fn main() !void {
    // try cleanPublicFolder();
    // try compileMarkdownToHtml();

    var listener = zap.HttpListener.init(.{
        .port = 9327,
        .on_request = onRequest,
        .log = true,
    });
    try listener.listen();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_path = try std.fs.cwd().realpath(".", &buf);
    std.debug.print("\nCurrent directory: {s}\n", .{cwd_path});

    std.debug.print("\nListening on 0.0.0.0:9327\n", .{});
    zap.start(.{
        // as per `/zap/tools/docserver.zig` for static stuff
        .threads = 2,
        .workers = 1,
    });
}
