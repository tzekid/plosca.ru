const std = @import("std");
const zap = @import("zap");
const print = std.debug.print;

const MIME_TYPES = struct { file_type: []const u8, mime_type: []const u8 };
const mime_types_map: []const MIME_TYPES = &.{
    .{ .file_type = "html", .mime_type = "text/html; charset=utf-8" },
    .{ .file_type = "htm", .mime_type = "text/html; charset=utf-8" },
    .{ .file_type = "css", .mime_type = "text/css; charset=utf-8" },
    .{ .file_type = "js", .mime_type = "text/javascript; charset=utf-8" },
    .{ .file_type = "mjs", .mime_type = "text/javascript; charset=utf-8" },
    .{ .file_type = "json", .mime_type = "application/json" },
    .{ .file_type = "jsonld", .mime_type = "application/ld+json" },
    .{ .file_type = "xml", .mime_type = "application/xml" },
    .{ .file_type = "xul", .mime_type = "application/vnd.mozilla.xul+xml" },
    .{ .file_type = "txt", .mime_type = "text/plain; charset=utf-8" },
    .{ .file_type = "csh", .mime_type = "application/x-csh" },
    .{ .file_type = "sh", .mime_type = "application/x-sh" },
    .{ .file_type = "csv", .mime_type = "text/csv; charset=utf-8" },
    .{ .file_type = "ics", .mime_type = "text/calendar" },
    .{ .file_type = "aac", .mime_type = "audio/aac" },
    .{ .file_type = "abw", .mime_type = "application/x-abiword" },
    .{ .file_type = "apng", .mime_type = "image/apng" },
    .{ .file_type = "arc", .mime_type = "application/x-freearc" },
    .{ .file_type = "avif", .mime_type = "image/avif" },
    .{ .file_type = "avi", .mime_type = "video/x-msvideo" },
    .{ .file_type = "azw", .mime_type = "application/vnd.amazon.ebook" },
    .{ .file_type = "bin", .mime_type = "application/octet-stream" },
    .{ .file_type = "bmp", .mime_type = "image/bmp" },
    .{ .file_type = "bz", .mime_type = "application/x-bzip" },
    .{ .file_type = "bz2", .mime_type = "application/x-bzip2" },
    .{ .file_type = "cda", .mime_type = "application/x-cdf" },
    .{ .file_type = "doc", .mime_type = "application/msword" },
    .{ .file_type = "docx", .mime_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
    .{ .file_type = "eot", .mime_type = "application/vnd.ms-fontobject" },
    .{ .file_type = "epub", .mime_type = "application/epub+zip" },
    .{ .file_type = "gz", .mime_type = "application/gzip" },
    .{ .file_type = "gif", .mime_type = "image/gif" },
    .{ .file_type = "ico", .mime_type = "image/vnd.microsoft.icon" },
    .{ .file_type = "jar", .mime_type = "application/java-archive" },
    .{ .file_type = "jpeg", .mime_type = "image/jpeg" },
    .{ .file_type = "mid", .mime_type = "audio/midi" },
    .{ .file_type = "midi", .mime_type = "audio/midi" },
    .{ .file_type = "mp3", .mime_type = "audio/mpeg" },
    .{ .file_type = "mp4", .mime_type = "video/mp4" },
    .{ .file_type = "mpeg", .mime_type = "video/mpeg" },
    .{ .file_type = "mpkg", .mime_type = "application/vnd.apple.installer+xml" },
    .{ .file_type = "odp", .mime_type = "application/vnd.oasis.opendocument.presentation" },
    .{ .file_type = "ods", .mime_type = "application/vnd.oasis.opendocument.spreadsheet" },
    .{ .file_type = "odt", .mime_type = "application/vnd.oasis.opendocument.text" },
    .{ .file_type = "oga", .mime_type = "audio/ogg" },
    .{ .file_type = "ogv", .mime_type = "video/ogg" },
    .{ .file_type = "ogx", .mime_type = "application/ogg" },
    .{ .file_type = "opus", .mime_type = "audio/ogg" },
    .{ .file_type = "otf", .mime_type = "font/otf" },
    .{ .file_type = "png", .mime_type = "image/png" },
    .{ .file_type = "pdf", .mime_type = "application/pdf" },
    .{ .file_type = "php", .mime_type = "application/x-httpd-php" },
    .{ .file_type = "ppt", .mime_type = "application/vnd.ms-powerpoint" },
    .{ .file_type = "pptx", .mime_type = "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
    .{ .file_type = "rar", .mime_type = "application/vnd.rar" },
    .{ .file_type = "rtf", .mime_type = "application/rtf" },
    .{ .file_type = "svg", .mime_type = "image/svg+xml" },
    .{ .file_type = "tar", .mime_type = "application/x-tar" },
    .{ .file_type = "tif", .mime_type = "image/tiff" },
    .{ .file_type = "tiff", .mime_type = "image/tiff" },
    .{ .file_type = "ts", .mime_type = "video/mp2t" },
    .{ .file_type = "ttf", .mime_type = "font/ttf" },
    .{ .file_type = "vsd", .mime_type = "application/vnd.visio" },
    .{ .file_type = "wav", .mime_type = "audio/wav" },
    .{ .file_type = "weba", .mime_type = "audio/webm" },
    .{ .file_type = "webm", .mime_type = "video/webm" },
    .{ .file_type = "webp", .mime_type = "image/webp" },
    .{ .file_type = "woff", .mime_type = "font/woff" },
    .{ .file_type = "woff2", .mime_type = "font/woff2" },
    .{ .file_type = "xhtml", .mime_type = "application/xhtml+xml" },
    .{ .file_type = "xls", .mime_type = "application/vnd.ms-excel" },
    .{ .file_type = "xlsx", .mime_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
    .{ .file_type = "zip", .mime_type = "application/zip" },
    .{ .file_type = "3gp", .mime_type = "video/3gpp" },
    .{ .file_type = "3g2", .mime_type = "video/3gpp2" },
    .{ .file_type = "7z", .mime_type = "application/x-7z-compressed" },
};

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
        var file_path: []const u8 = "";
        var content_type: []const u8 = "text/plain; charset=utf-8"; // default

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
            var extension = std.fs.path.extension(file_path);
            if (extension.len > 0) {
                extension = extension[1..];
            }
            for (mime_types_map) |mime_type| {
                if (std.mem.eql(u8, mime_type.file_type, extension)) {
                    content_type = mime_type.mime_type;
                    break;
                }
            }

            r.setHeader("Content-Type", content_type) catch return;
            r.sendBody(contents) catch return;
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
