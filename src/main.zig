const out = std.io.getStdOut().writer();
const err = std.io.getStdErr().writer();

const loud = false;

pub fn main() !void {
    if (std.os.argv.len > 2) {
        try err.print("Too many arguments. Usage: glance <file_path>\n", .{});
    } else if (std.os.argv.len < 2) {
        try err.print("Too few arguments. Usage: glance <file_path>\n", .{});
    } else {
        const path = std.mem.span(std.os.argv[1]);
        find_gits(path) catch @panic("Failed to get path");
    }
}

fn find_gits(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var entry = try walker.next();
    var count: u8 = 0;
    while (entry) |it| {
        if (std.mem.eql(u8, it.basename, ".git")) {
            count += 1;
            try out.print("[{d}] Found .git repository at: {s}\r", .{ count, it.path });
        }
        entry = walker.next() catch {
            if (loud) {
                try err.print("Failed to read directory {s}.\n", .{it.path});
            }
            continue;
        };
    }
    try out.print("\n{d} git repositories found\n", .{count});
}

const std = @import("std");
const ctime = @cImport({
    @cInclude("time.h");
});
