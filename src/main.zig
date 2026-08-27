const std = @import("std");
const compiler = @import("compiler.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return usage();

    if (std.mem.eql(u8, args[1], "build")) {
        try compiler.buildSite(init.io, init.gpa);
    } else if (std.mem.eql(u8, args[1], "check")) {
        try compiler.checkSite(init.io, init.gpa);
    } else {
        return usage();
    }
}

fn usage() error{InvalidArguments} {
    std.debug.print("usage: sitec <build|check>\n", .{});
    return error.InvalidArguments;
}
