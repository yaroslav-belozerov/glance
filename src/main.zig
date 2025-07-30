const out = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const loud = false;

const Github = struct {
    const gray = prettyzig.RGB.init(21, 27, 35);
    const low = prettyzig.RGB.init(3, 58, 22);
    const medium = prettyzig.RGB.init(25, 108, 46);
    const high = prettyzig.RGB.init(46, 160, 67);
    const highest = prettyzig.RGB.init(86, 211, 100);
};

pub fn main() !void {
    if (std.os.argv.len > 2) {
        try stderr.print("Too many arguments. Usage: glance <file_path>\n", .{});
    } else if (std.os.argv.len < 2) {
        try stderr.print("Too few arguments. Usage: glance <file_path>\n", .{});
    } else {
        const path = std.mem.span(std.os.argv[1]);
        find_gits(path) catch @panic("Failed to get path");
    }
}

fn find_gits(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var year_length: u16 = 365;
    if (isLeapYear(2025)) {
        year_length += 1;
    }
    var contrib_graph = std.AutoHashMap(u16, u16).init(allocator);
    defer contrib_graph.deinit();

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
            try get_git_data_for_repo(allocator, it.path, &contrib_graph, "2025");
        }
        entry = walker.next() catch {
            if (loud) {
                try stderr.print("Failed to read directory {s}.\n", .{it.path});
            }
            continue;
        };
    }
    try out.print("\n{d} git repositories found\n", .{count});
    var max: u16 = 0;
    var values = contrib_graph.valueIterator();
    while (values.next()) |item| {
        if (item.* > max) {
            max = item.*;
        }
    }
    try out.print("╔═══════════════════════════════╗\n║", .{});
    for (1..year_length) |i| {
        const day: u16 = @intCast(i);
        const value = contrib_graph.get(day);
        if (value == null) {
            try out.print(" ", .{});
        } else {
            const val: f64 = @floatFromInt(value.?);
            const percent: u16 = @intFromFloat(val / @as(f64, @floatFromInt(max)) * 100.0);
            const now = std.time.timestamp();
            const nowgm = ctime.gmtime(&now);
            const yday: u16 = @intCast(nowgm.*.tm_yday + 1);
            var char: []const u8 = "█";
            if (yday == day) {
                char = "*";
            }
            switch (percent) {
                0...24 => {
                    try prettyzig.print(out, char, .{ .color = .{ .rgb = Github.low } });
                },
                25...49 => {
                    try prettyzig.print(out, char, .{ .color = .{ .rgb = Github.medium } });
                },
                50...74 => {
                    try prettyzig.print(out, char, .{ .color = .{ .rgb = Github.high } });
                },
                75...100 => {
                    try prettyzig.print(out, char, .{ .color = .{ .rgb = Github.highest } });
                },
                else => {
                    try out.print(" ", .{});
                },
            }
        }
        if (@rem(i, 31) == 0) {
            try out.print("║\n║", .{});
        }
    }
    for (0..32 - @rem(year_length, 31)) |_| {
        try out.print(" ", .{});
    }
    try out.print("║\n╚═══════════════════════════════╝\n", .{});
}

fn get_git_data_for_repo(allocator: std.mem.Allocator, path: []const u8, contrib_graph: *std.AutoHashMap(u16, u16), year_string: []const u8) !void {
    const argv = [_][]const u8{ "git", "-C", path, "log", "--oneline", "--all", "--no-patch", "--format=%ci" };
    var child = std.process.Child.init(&argv, allocator);

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer stdout_buffer.deinit(allocator);
    var stderr_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer stderr_buffer.deinit(allocator);
    try child.spawn();
    child.collectOutput(allocator, &stdout_buffer, &stderr_buffer, 1024) catch {
        if (loud) {
            try stderr.print("\nFailed to collect output", .{});
        }
    };
    var lines = std.mem.splitSequence(u8, stdout_buffer.items, "\n");
    while (lines.next()) |ln| {
        var parts = std.mem.splitSequence(u8, ln, " ");
        const date = parts.first();
        var dateparts = std.mem.splitSequence(u8, date, "-");
        const year = dateparts.next() orelse return;
        const month = dateparts.next() orelse return;
        const day = dateparts.next() orelse return;
        if (std.mem.eql(u8, year, year_string)) {
            const day_of_month = getDayOfYear(year, month, day);
            const val = contrib_graph.get(day_of_month);
            if (val != null) {
                try contrib_graph.put(day_of_month, val.? + 1);
            } else {
                try contrib_graph.put(day_of_month, 1);
            }
        }
    }
}

const std = @import("std");
const ctime = @cImport({
    @cInclude("time.h");
});
const prettyzig = @import("prettyzig");

fn getDayOfYear(year_str: []const u8, month_str: []const u8, day_str: []const u8) u16 {
    const year = std.fmt.parseInt(i32, year_str, 10) catch @panic("Could not parse year");
    const month = std.fmt.parseInt(u8, month_str, 10) catch @panic("Could not parse month");
    const day = std.fmt.parseInt(u8, day_str, 10) catch @panic("Could not parse day");
    const monthDays = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var day_of_year: u16 = 0;
    var i: usize = 0;
    while (i < month - 1) : (i += 1) {
        day_of_year += monthDays[i];
        if (i == 1 and isLeapYear(year)) { // February index = 1
            day_of_year += 1;
        }
    }
    return day_of_year + day;
}

fn isLeapYear(year: i32) bool {
    return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
}
