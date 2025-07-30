const out = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const loud = false;
const pad = 0;
const top = 3;

const OwnedStringHashMapEntry = struct {
    key: []const u8,
    value: u16,
};

const intro =
    \\
    \\   ▄██████▄   ▄█        ▄████████ ███▄▄▄▄    ▄████████   ▄████████
    \\  ███    ███ ███       ███    ███ ███▀▀▀██▄ ███    ███  ███    ███
    \\  ███    █▀  ███       ███    ███ ███   ███ ███    █▀   ███    █▀
    \\ ▄███        ███       ███    ███ ███   ███ ███        ▄███▄▄▄
    \\▀▀███ ████▄  ███     ▀███████████ ███   ███ ███       ▀▀███▀▀▀
    \\  ███    ███ ███       ███    ███ ███   ███ ███    █▄   ███    █▄
    \\  ███    ███ ███▌    ▄ ███    ███ ███   ███ ███    ███  ███    ███
    \\  ████████▀  █████▄▄██ ███    █▀   ▀█   █▀  ████████▀   ██████████
    \\             ▀
    \\
;

const Github = struct {
    const gray = prettyzig.RGB.init(21, 27, 35);
    const low = prettyzig.RGB.init(3, 58, 22);
    const medium = prettyzig.RGB.init(25, 108, 46);
    const high = prettyzig.RGB.init(46, 160, 67);
    const highest = prettyzig.RGB.init(86, 211, 100);
};

pub fn main() !void {
    if (std.os.argv.len > 3) {
        try stderr.print("Too many arguments. Usage: glance <file_path> <author>\n", .{});
    } else if (std.os.argv.len < 3) {
        try stderr.print("Too few arguments. Usage: glance <file_path> <author>\n", .{});
    } else {
        const path = std.mem.span(std.os.argv[1]);
        const author = std.mem.span(std.os.argv[2]);
        printClr(intro, .{ .ansi = .brightCyan });
        find_gits(path, author) catch @panic("Failed to get path");
    }
}

fn find_gits(path: []const u8, author: []const u8) !void {
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

    var contrib_counter = std.StringHashMap(u16).init(allocator);
    defer {
        var it = contrib_counter.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        contrib_counter.deinit();
    }

    var dir_entry = try walker.next();
    var count: u8 = 0;
    while (dir_entry) |it| {
        if (std.mem.eql(u8, it.basename, ".git")) {
            count += 1;
            try out.print("\r", .{});
            printClrInt(allocator, count, .{ .ansi = .brightCyan });
            try out.print(" git repositories found in {s}", .{path});
            var this_count: u16 = 0;
            try get_git_data_for_repo(allocator, it.path, &contrib_graph, "2025", author, &this_count);
            const key = try allocator.dupe(u8, it.path);
            try contrib_counter.put(key, this_count);
        }
        dir_entry = walker.next() catch {
            if (loud) {
                try stderr.print("Failed to read directory {s}.\n", .{it.path});
            }
            continue;
        };
    }
    var iter = contrib_counter.iterator();
    var arr = std.ArrayList(OwnedStringHashMapEntry).init(allocator);
    defer {
        arr.deinit();
    }
    while (iter.next()) |e| {
        const pair = OwnedStringHashMapEntry{ .key = e.key_ptr.*, .value = e.value_ptr.* };
        try arr.append(pair);
    }
    std.mem.sort(OwnedStringHashMapEntry, arr.items, {}, struct {
        fn desc(_: void, lhs: OwnedStringHashMapEntry, rhs: OwnedStringHashMapEntry) bool {
            return lhs.value > rhs.value;
        }
    }.desc);
    var output_count: usize = 0;
    try out.print("\n", .{});
    var max: u16 = 0;
    var total: u16 = 0;
    var values = contrib_graph.valueIterator();
    while (values.next()) |item| {
        total += item.*;
        if (item.* > max) {
            max = item.*;
        }
    }
    try out.print("\n", .{});
    printClrInt(allocator, total, .{ .rgb = Github.highest });
    try out.print(" total contributions by {s}", .{author});
    try out.print("\n", .{});
    for (arr.items) |it| {
        if (output_count >= top) {
            break;
        }
        if (it.value > 0) {
            var pieces = std.mem.splitSequence(u8, it.key, "/");
            var prev = pieces.peek().?;
            while (pieces.next()) |piece| {
                if (std.mem.eql(u8, piece, ".git")) {
                    printClr("[", .{ .rgb = Github.medium });
                    printClrInt(allocator, @intCast(output_count + 1), .{ .rgb = Github.highest });
                    printClr("]", .{ .rgb = Github.medium });
                    try out.print(" {s} - {d}\n", .{ prev, it.value });
                    output_count += 1;
                    break;
                }
                prev = piece;
            }
        }
    }
    const line_len = 31;
    printClr("\n╔", .{ .ansi = .brightCyan });
    for (0..paddedAmount(line_len) / 2 - 4) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr(" HEATMAP ", .{ .ansi = .brightCyan });
    for (0..paddedAmount(line_len) / 2 - 4) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr("╗\n║", .{ .ansi = .brightCyan });
    for (1..year_length) |i| {
        const day: u16 = @intCast(i);
        const value = contrib_graph.get(day);
        const now = std.time.timestamp();
        const nowgm = ctime.gmtime(&now);
        const yday: u16 = @intCast(nowgm.*.tm_yday + 1);
        const char: []const u8 = if (pad > 0) "█" else "■";
        const now_char: []const u8 = if (pad > 0) "●" else "◆";
        const empty_char: []const u8 = " ";
        if (day == yday) {
            printPadded(allocator, now_char, .{ .ansi = .red });
            continue;
        }
        if (value == null) {
            printPadded(allocator, empty_char, .{ .ansi = .brightRed });
        } else {
            const val: f64 = @floatFromInt(value.?);
            const percent: u16 = @intFromFloat(val / @as(f64, @floatFromInt(max)) * 100.0);
            switch (percent) {
                0...24 => {
                    printPadded(allocator, char, .{ .rgb = Github.low });
                },
                25...49 => {
                    printPadded(allocator, char, .{ .rgb = Github.medium });
                },
                50...74 => {
                    printPadded(allocator, char, .{ .rgb = Github.high });
                },
                75...100 => {
                    printPadded(allocator, char, .{ .rgb = Github.highest });
                },
                else => {
                    printPadded(allocator, empty_char, .{ .rgb = Github.low });
                },
            }
        }
        if (@rem(i, 31) == 0) {
            printClr("║\n║", .{ .ansi = .brightCyan });
        }
    }
    for (0..paddedAmount(line_len) - paddedAmount(@rem(year_length, 31)) + paddedAmount(1)) |_| {
        printClr(" ", .{ .ansi = .brightCyan });
    }
    printClr("║\n╚", .{ .ansi = .brightCyan });
    for (0..paddedAmount(line_len)) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr("╝\n", .{ .ansi = .brightCyan });
}

fn get_git_data_for_repo(allocator: std.mem.Allocator, path: []const u8, contrib_graph: *std.AutoHashMap(u16, u16), year_string: []const u8, author: []const u8, contrib_counter: *u16) !void {
    const argv = [_][]const u8{ "git", "-C", path, "log", "--oneline", "--all", "--no-patch", "--format=%ci", "--author", author };
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
            contrib_counter.* += 1;
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

fn paddedAmount(amount: u16) u16 {
    return amount * (pad * 2 + 1);
}

fn printPadded(allocator: std.mem.Allocator, string: []const u8, color: prettyzig.Color) void {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    if (pad > 0) {
        for (0..pad) |_| {
            buffer.appendSlice(" ") catch return;
        }
    }
    buffer.appendSlice(string) catch return;
    if (pad > 0) {
        for (0..pad) |_| {
            buffer.appendSlice(" ") catch return;
        }
    }
    printClr(buffer.items, color);
}

fn br(allocator: std.mem.Allocator, string: []const u8) []const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    buffer.appendSlice(string) catch return "";
    buffer.appendSlice("\n") catch return "";
    return buffer.items;
}

fn printClr(string: []const u8, color: prettyzig.Color) void {
    prettyzig.print(out, string, .{ .color = color }) catch return;
}

fn printClrInt(allocator: std.mem.Allocator, amount: u16, color: prettyzig.Color) void {
    const amount_str = std.fmt.allocPrint(allocator, "{d}", .{amount}) catch return;
    defer allocator.free(amount_str);
    printClr(amount_str, color);
}
