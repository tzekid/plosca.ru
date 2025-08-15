const std = @import("std");
const zap = @import("zap");
const zd = @import("zigdown");

const fs = std.fs;

/// Folder containing the source markdown documents to be compiled.
const MARKDOWN_FOLDER = "markdown";
/// Destination folder where compiled HTML pages are written.
const PUBLIC_FOLDER = "public";
/// Folder served directly by the HTTP server (legacy / pre-built static files).
const STATIC_FOLDER = "static_old";

// NOTE: Current flow (disabled in main()):
// 1. (Planned) cleanPublicFolder(): remove previously generated HTML
// 2. compileMarkdownToHtml(): regenerate HTML from markdown sources into `public/`
// 3. (Future) Copy / merge into STATIC_FOLDER or serve PUBLIC_FOLDER directly
//
// TODO: delete all html files in public folder
// fn cleanPublicFolder() !void {
// }

/// Render a parsed markdown root block to an output stream as HTML.
/// The renderer allocates transient state with the markdown's allocator.
fn render(stream: anytype, md: zd.Block) !void {
    var h_renderer = zd.htmlRenderer(stream, md.allocator());
    defer h_renderer.deinit();
    try h_renderer.renderBlock(md);
}

/// Walk the MARKDOWN_FOLDER, parse every *.md file and emit an HTML file
/// with the same base name into PUBLIC_FOLDER.
///
/// Current limitations / TODOs:
/// - Writes raw HTML that still includes <html>/<body> (wants stripping)
/// - No templating (header / footer / layout not injected yet)
/// - Uses the global page allocator (consider a bounded arena per file)
fn compileMarkdownToHtml() !void {
    var dir = try fs.cwd().openDir(MARKDOWN_FOLDER, .{});
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".md")) {
            // Compute full source and destination paths (html_file_path includes .html suffix).
            const markdown_file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ MARKDOWN_FOLDER, entry.name });
            defer std.heap.page_allocator.free(markdown_file_path);

            const html_file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ PUBLIC_FOLDER, std.fs.path.basename(entry.name) });
            defer std.heap.page_allocator.free(html_file_path);

            std.debug.print("Compiling '{s}'\n", .{html_file_path});

            // Open and slurp the markdown file (unbounded read; consider a size cap or streaming).
            var file = try dir.openFile(entry.name, .{});
            defer file.close();

            const file_contents = file.readToEndAlloc(std.heap.page_allocator, std.math.maxInt(usize)) catch unreachable;
            defer std.heap.page_allocator.free(file_contents);

            // Initialize parser (copy_input=false avoids duplicating the markdown buffer).
            const alloc = std.heap.page_allocator;
            const opts = zd.parser.ParserOpts{ .copy_input = false, .verbose = false };
            var parser = zd.Parser.init(alloc, opts);
            defer parser.deinit();

            // Parse and obtain the root document block.
            parser.parseMarkdown(file_contents) catch unreachable;
            const md: zd.Block = parser.document;

            // TODO: omit <html> and <body> tags
            // TODO: wrap in <article> tag
            // TODO: figure out how to insert header and footer

            // Create destination file (read flag enabled for potential post-processing).
            const dest_file = try fs.cwd().createFile(html_file_path, .{ .read = true });
            defer dest_file.close();

            // Render markdown AST as HTML into destination file.
            render(dest_file.writer(), md) catch unreachable;
        }
    }
}

/// zap request handler:
/// - Normalizes the requested path into a file in STATIC_FOLDER.
/// - Adds ".html" when the path has no '.' (treat as a logical page).
/// - Defaults "/" and "" to "index.html".
/// - Sets MIME based on the resolved filename; falls back to 404 on errors.
fn onRequest(r: zap.Request) void {
    if (r.path) |the_path| {
        var file_path: []const u8 = "";

        if (std.mem.eql(u8, the_path, "/") or std.mem.eql(u8, the_path, "")) {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/index.html", .{STATIC_FOLDER}) catch return;
        } else if (std.mem.indexOf(u8, the_path, ".")) |_| {
            // Path already looks like a file (contains a dot) -> serve directly.
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ STATIC_FOLDER, the_path }) catch return;
        } else {
            // Treat as page slug -> append ".html".
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ STATIC_FOLDER, the_path }) catch return;
        }

        // Best-effort content type; if it fails, serve 404 page.
        r.setContentTypeFromFilename(file_path) catch {
            r.setStatus(.not_found);
            r.sendFile(STATIC_FOLDER ++ "/404.html") catch return;
        };
        // Attempt to send the resolved file; on failure send 404 page.
        r.sendFile(file_path) catch {
            r.setStatus(.not_found);
            r.sendFile(STATIC_FOLDER ++ "/404.html") catch return;
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
