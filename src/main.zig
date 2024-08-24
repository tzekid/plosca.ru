const std = @import("std");
const zap = @import("zap");
const print = std.debug.print;

const MIME_TYPES = std.StaticStringMap(
    []const u8,
    .{
        .{ "html", "text/html; charset=utf-8" },
        .{ "htm", "text/html; charset=utf-8" },
        .{ "css", "text/css; charset=utf-8" },
        .{ "js", "text/javascript; charset=utf-8" },
        .{ "mjs", "text/javascript; charset=utf-8" },
        .{ "json", "application/json" },
        .{ "jsonld", "application/ld+json" },
        .{ "xml", "application/xml" },
        .{ "xul", "application/vnd.mozilla.xul+xml" },
        .{ "txt", "text/plain; charset=utf-8" },
        .{ "csh", "application/x-csh" },
        .{ "sh", "application/x-sh" },
        .{ "csv", "text/csv; charset=utf-8" },
        .{ "ics", "text/calendar" },
        .{ "aac", "audio/aac" },
        .{ "abw", "application/x-abiword" },
        .{ "apng", "image/apng" },
        .{ "arc", "application/x-freearc" },
        .{ "avif", "image/avif" },
        .{ "avi", "video/x-msvideo" },
        .{ "azw", "application/vnd.amazon.ebook" },
        .{ "bin", "application/octet-stream" },
        .{ "bmp", "image/bmp" },
        .{ "bz", "application/x-bzip" },
        .{ "bz2", "application/x-bzip2" },
        .{ "cda", "application/x-cdf" },
        .{ "doc", "application/msword" },
        .{ "docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
        .{ "eot", "application/vnd.ms-fontobject" },
        .{ "epub", "application/epub+zip" },
        .{ "gz", "application/gzip" },
        .{ "gif", "image/gif" },
        .{ "ico", "image/vnd.microsoft.icon" },
        .{ "jar", "application/java-archive" },
        .{ "jpeg", "image/jpeg" },
        .{ "mid", "audio/midi" },
        .{ "midi", "audio/midi" },
        .{ "mp3", "audio/mpeg" },
        .{ "mp4", "video/mp4" },
        .{ "mpeg", "video/mpeg" },
        .{ "mpkg", "application/vnd.apple.installer+xml" },
        .{ "odp", "application/vnd.oasis.opendocument.presentation" },
        .{ "ods", "application/vnd.oasis.opendocument.spreadsheet" },
        .{ "odt", "application/vnd.oasis.opendocument.text" },
        .{ "oga", "audio/ogg" },
        .{ "ogv", "video/ogg" },
        .{ "ogx", "application/ogg" },
        .{ "opus", "audio/ogg" },
        .{ "otf", "font/otf" },
        .{ "png", "image/png" },
        .{ "pdf", "application/pdf" },
        .{ "php", "application/x-httpd-php" },
        .{ "ppt", "application/vnd.ms-powerpoint" },
        .{ "pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
        .{ "rar", "application/vnd.rar" },
        .{ "rtf", "application/rtf" },
        .{ "svg", "image/svg+xml" },
        .{ "tar", "application/x-tar" },
        .{ "tif", "image/tiff" },
        .{ "tiff", "image/tiff" },
        .{ "ts", "video/mp2t" },
        .{ "ttf", "font/ttf" },
        .{ "vsd", "application/vnd.visio" },
        .{ "wav", "audio/wav" },
        .{ "weba", "audio/webm" },
        .{ "webm", "video/webm" },
        .{ "webp", "image/webp" },
        .{ "woff", "font/woff" },
        .{ "woff2", "font/woff2" },
        .{ "xhtml", "application/xhtml+xml" },
        .{ "xls", "application/vnd.ms-excel" },
        .{ "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
        .{ "zip", "application/zip" },
        .{ "3gp", "video/3gpp" },
        .{ "3g2", "video/3gpp2" },
        .{ "7z", "application/x-7z-compressed" },
    },
);

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
        var file_path: []const u8 = ""; // I am going to hell for this
        var content_type: []const u8 = "text/plain; charset=utf-8"; // default

        if (std.mem.eql(u8, the_path, "/") or std.mem.eql(u8, the_path, "")) {
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/index.html", .{STATIC_FOLDER}) catch |err| {
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
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ STATIC_FOLDER, the_path }) catch |err| {
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
            file_path = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}.html", .{ STATIC_FOLDER, the_path }) catch |err| {
                std.log.err("Error allocating memory for file path: {}", .{err});
                return;
            };

            file_contents = readFileToString(std.heap.page_allocator, file_path) catch {
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
            // content_type = MIME_TYPES.get(the_path) orelse "application/octet-stream";
            var extension = std.fs.path.extension(file_path);
            if (extension.len > 0) {
                extension = extension[1..]; // Remove the leading dot
            }
            if (MIME_TYPES.get(extension)) |mime_type| {
                content_type = mime_type;
            }

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
