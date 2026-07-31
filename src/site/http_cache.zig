const std = @import("std");
const web_cache = @import("web_cache");

pub const HttpDate = web_cache.HttpDate;
pub const public_revalidate = web_cache.Policy.public_revalidate.headerValue();
pub const immutable = web_cache.Policy.immutable.headerValue();
pub const private_no_store = web_cache.Policy.no_store.headerValue();
pub const no_store = "no-store";

pub const RenderScope = enum {
    public,
    personalized,
};

pub const Representation = enum {
    full_page,
    fragment,
};

/// Every input that can change public rendered bytes belongs in this key.
/// Route handlers first parse a bounded typed query, then serialize its
/// canonical form into `canonical_params`.
pub const RenderKey = struct {
    route: []const u8,
    representation: Representation,
    canonical_params: []const u8,
    data_revision: []const u8,
    renderer_version: []const u8,
    content_encoding: []const u8 = "identity",
};

pub fn policyForScope(scope: RenderScope) []const u8 {
    return switch (scope) {
        .public => public_revalidate,
        .personalized => private_no_store,
    };
}

pub fn policyForStaticPath(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(ext, ".html") or
        std.ascii.eqlIgnoreCase(ext, ".md") or
        std.ascii.eqlIgnoreCase(ext, ".txt"))
    {
        return public_revalidate;
    }
    if (std.ascii.eqlIgnoreCase(ext, ".css") or
        std.ascii.eqlIgnoreCase(ext, ".js") or
        std.ascii.eqlIgnoreCase(ext, ".webmanifest") or
        std.ascii.eqlIgnoreCase(ext, ".pdf") or
        std.ascii.eqlIgnoreCase(ext, ".png") or
        std.ascii.eqlIgnoreCase(ext, ".jpg") or
        std.ascii.eqlIgnoreCase(ext, ".jpeg") or
        std.ascii.eqlIgnoreCase(ext, ".gif") or
        std.ascii.eqlIgnoreCase(ext, ".svg") or
        std.ascii.eqlIgnoreCase(ext, ".ico") or
        std.ascii.eqlIgnoreCase(ext, ".woff") or
        std.ascii.eqlIgnoreCase(ext, ".woff2"))
    {
        return immutable;
    }
    return public_revalidate;
}

pub fn makeStaticEtag(
    path: []const u8,
    encoding_suffix: []const u8,
    size: u64,
    mtime_ns: i96,
    out: *[34]u8,
) []const u8 {
    var size_buffer: [32]u8 = undefined;
    const size_text = std.fmt.bufPrint(&size_buffer, "{d}", .{size}) catch unreachable;
    var mtime_buffer: [48]u8 = undefined;
    const mtime_text = std.fmt.bufPrint(&mtime_buffer, "{d}", .{mtime_ns}) catch unreachable;
    const etag = web_cache.Etag.fromParts(&.{ path, encoding_suffix, size_text, mtime_text });
    @memcpy(out, etag.slice());
    return out[0..];
}

pub fn makeRenderEtag(key: RenderKey, rendered: []const u8, out: *[66]u8) []const u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(key.route);
    hash.update("\x00");
    hash.update(@tagName(key.representation));
    hash.update("\x00");
    hash.update(key.canonical_params);
    hash.update("\x00");
    hash.update(key.data_revision);
    hash.update("\x00");
    hash.update(key.renderer_version);
    hash.update("\x00");
    hash.update(key.content_encoding);
    hash.update("\x00");
    hash.update(rendered);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);
    writeQuotedHex(digest[0..], out);
    return out[0..];
}

pub fn matchesIfNoneMatch(value: []const u8, etag: []const u8) bool {
    return web_cache.matches(value, etag);
}

fn writeQuotedHex(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2 + 2);
    const hex = "0123456789abcdef";
    out[0] = '"';
    for (bytes, 0..) |byte, index| {
        out[1 + index * 2] = hex[byte >> 4];
        out[2 + index * 2] = hex[byte & 0x0f];
    }
    out[out.len - 1] = '"';
}

test "public and personalized render policy cannot be confused" {
    try std.testing.expectEqualStrings(public_revalidate, policyForScope(.public));
    try std.testing.expectEqualStrings(private_no_store, policyForScope(.personalized));
}

test "static validators use shared structured ETags" {
    var first_buffer: [34]u8 = undefined;
    const first = makeStaticEtag("style.css", "", 42, 7, &first_buffer);
    var second_buffer: [34]u8 = undefined;
    const second = makeStaticEtag("style.css", ".br", 42, 7, &second_buffer);
    try std.testing.expect(!std.mem.eql(u8, first, second));
    var weak_buffer: [36]u8 = undefined;
    const weak = try std.fmt.bufPrint(&weak_buffer, "W/{s}", .{first});
    try std.testing.expect(matchesIfNoneMatch(weak, first));
}

test "render validators vary by representation and data revision" {
    const base: RenderKey = .{
        .route = "/graphs/activity",
        .representation = .full_page,
        .canonical_params = "range=year",
        .data_revision = "42",
        .renderer_version = "activity-v1",
    };
    var full_buf: [66]u8 = undefined;
    const full = makeRenderEtag(base, "<svg></svg>", &full_buf);

    var fragment_key = base;
    fragment_key.representation = .fragment;
    var fragment_buf: [66]u8 = undefined;
    const fragment = makeRenderEtag(fragment_key, "<svg></svg>", &fragment_buf);
    try std.testing.expect(!std.mem.eql(u8, full, fragment));

    var revised_key = base;
    revised_key.data_revision = "43";
    var revised_buf: [66]u8 = undefined;
    const revised = makeRenderEtag(revised_key, "<svg></svg>", &revised_buf);
    try std.testing.expect(!std.mem.eql(u8, full, revised));
}
