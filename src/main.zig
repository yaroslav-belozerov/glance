const out = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

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
    const conf = args.parseArgs(std.os.argv);
    if (!conf.no_intro) {
        printClr(intro, .{ .ansi = .brightCyan });
    }
    find_gits(conf) catch @panic("Failed to get path");
}

fn find_gits(conf: args.Config) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var year_length: u16 = 365;
    if (isLeapYear(conf.year)) {
        year_length += 1;
    }
    var contrib_graph = std.AutoHashMap(u16, u16).init(allocator);
    defer contrib_graph.deinit();

    var dir = try std.fs.cwd().openDir(conf.path, .{ .iterate = true });
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
            if (conf.loud) {
                try out.print("\n", .{});
            } else {
                try out.print("\r", .{});
            }
            printClrInt(allocator, count, .{ .ansi = .brightCyan });
            try out.print(" git repositories found", .{});
            var this_count: u16 = 0;
            const year_string = try std.fmt.allocPrint(allocator, "{d}", .{conf.year});
            defer allocator.free(year_string);
            try get_git_data_for_repo(allocator, it.path, &contrib_graph, year_string, conf.author, &this_count, conf.loud);
            const key = try allocator.dupe(u8, it.path);
            try contrib_counter.put(key, this_count);
        }
        dir_entry = walker.next() catch {
            if (conf.loud) {
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
    var total: u16 = 0;
    var values = contrib_graph.valueIterator();
    while (values.next()) |item| {
        total += item.*;
    }
    try out.print("\n", .{});
    printClrInt(allocator, total, .{ .rgb = Github.highest });
    if (std.mem.eql(u8, conf.author, "")) {
        try out.print(" total contributions by everyone in {d}", .{conf.year});
    } else {
        try out.print(" total contributions by {s} in {d}", .{ conf.author, conf.year });
    }
    if (total == 0) {
        try out.print("\n", .{});
        return;
    }
    try out.print("\n", .{});
    for (arr.items) |it| {
        if (output_count >= conf.top) {
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
    if (conf.weekly) {
        try printWeekly(conf, year_length, &contrib_graph, allocator);
    } else {
        try printDaily(conf, year_length, &contrib_graph, allocator);
    }
}

fn get_git_data_for_repo(allocator: std.mem.Allocator, path: []const u8, contrib_graph: *std.AutoHashMap(u16, u16), year_string: []const u8, author: []const u8, contrib_counter: *u16, loud: bool) !void {
    var argv = [_][]const u8{ "git", "-C", path, "log", "--oneline", "--all", "--no-patch", "--format=%ci" };
    var child: ?std.process.Child = null;
    if (!std.mem.eql(u8, author, "")) {
        child = std.process.Child.init(&(argv ++ [_][]const u8{ "--author", author }), allocator);
    } else {
        child = std.process.Child.init(&argv, allocator);
    }

    child.?.stdout_behavior = .Pipe;
    child.?.stderr_behavior = .Pipe;

    var stdout_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer stdout_buffer.deinit(allocator);
    var stderr_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer stderr_buffer.deinit(allocator);
    try child.?.spawn();
    child.?.collectOutput(allocator, &stdout_buffer, &stderr_buffer, 1024) catch {
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
const args = @import("cliargs");

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

fn paddedAmount(padding: u16, amount: u16) u16 {
    return amount * (padding * 2 + 1);
}

fn printPadded(allocator: std.mem.Allocator, padding: u16, string: []const u8, color: prettyzig.Color) void {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    if (padding > 0) {
        for (0..padding) |_| {
            buffer.appendSlice(" ") catch return;
        }
    }
    buffer.appendSlice(string) catch return;
    if (padding > 0) {
        for (0..padding) |_| {
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

fn printDaily(conf: args.Config, year_length: u16, contrib_graph: *std.AutoHashMap(u16, u16), allocator: std.mem.Allocator) !void {
    var max: u16 = 0;
    var max_changed = false;
    var max_day: u16 = 0;
    var min: u16 = std.math.maxInt(u16);
    var min_changed = false;
    var min_day: u16 = std.math.maxInt(u16);
    var values = contrib_graph.iterator();
    while (values.next()) |item| {
        if (item.value_ptr.* > max) {
            max = item.value_ptr.*;
            max_day = item.key_ptr.*;
            max_changed = true;
        }
        if (item.value_ptr.* < min and item.value_ptr.* > 0) {
            min = item.value_ptr.*;
            min_day = item.key_ptr.*;
            min_changed = true;
        }
    }
    std.debug.print("\n", .{});
    if (max_changed) {
        const day_num = try std.fmt.allocPrint(allocator, "#{d}", .{max_day});
        const day_contrib_num = try std.fmt.allocPrint(allocator, "{d}", .{max});
        defer allocator.free(day_num);
        defer allocator.free(day_contrib_num);
        printClr("Best day ", .{ .ansi = .brightCyan });
        printClr(day_num, .{ .rgb = Github.highest });
        std.debug.print(" with ", .{});
        printClr(day_contrib_num, .{ .rgb = Github.highest });
        std.debug.print(" contributions\n", .{});
    }
    if (min_changed) {
        const min_day_num = try std.fmt.allocPrint(allocator, "#{d}", .{min_day});
        const min_day_contrib_num = try std.fmt.allocPrint(allocator, "{d}", .{min});
        defer allocator.free(min_day_num);
        defer allocator.free(min_day_contrib_num);
        printClr("Worst day ", .{ .ansi = .brightCyan });
        printClr(min_day_num, .{ .rgb = Github.highest });
        std.debug.print(" with ", .{});
        printClr(min_day_contrib_num, .{ .rgb = Github.highest });
        std.debug.print(" contributions", .{});
        std.debug.print("\n", .{});
    }
    printClr("\n╔", .{ .ansi = .brightCyan });
    for (0..paddedAmount(conf.padding, conf.line_len) / 2 - 4) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr(" HEATMAP ", .{ .ansi = .brightCyan });
    for (0..paddedAmount(conf.padding, conf.line_len) / 2 - 5 + @rem(conf.line_len, 2)) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr("╗\n║", .{ .ansi = .brightCyan });
    const now = std.time.timestamp();
    const nowgm = ctime.gmtime(&now);
    var yday: u16 = @intCast(nowgm.*.tm_yday + 1);
    if (nowgm.*.tm_year + 1900 != conf.year) {
        yday = 999;
    }
    for (1..year_length) |i| {
        const day: u16 = @intCast(i);
        const value = contrib_graph.get(day);
        const char: []const u8 = if (conf.padding > 0) "█" else "■";
        const now_char: []const u8 = if (conf.padding > 0) "●" else "◆";
        const empty_char: []const u8 = " ";
        if (day == yday) {
            printPadded(allocator, conf.padding, now_char, .{ .ansi = .red });
            continue;
        }
        if (value == null) {
            printPadded(allocator, conf.padding, empty_char, .{ .ansi = .brightRed });
        } else {
            const val: f64 = @floatFromInt(value.?);
            const percent: u16 = @intFromFloat(val / @as(f64, @floatFromInt(max)) * 100.0);
            switch (percent) {
                0...24 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.low });
                },
                25...49 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.medium });
                },
                50...74 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.high });
                },
                75...100 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.highest });
                },
                else => {
                    printPadded(allocator, conf.padding, empty_char, .{ .rgb = Github.low });
                },
            }
        }
        if (@rem(i, conf.line_len) == 0) {
            printClr("║\n║", .{ .ansi = .brightCyan });
        }
    }
    for (0..paddedAmount(conf.padding, conf.line_len) - paddedAmount(conf.padding, @rem(year_length, conf.line_len)) + paddedAmount(conf.padding, 1)) |_| {
        printClr(" ", .{ .ansi = .brightCyan });
    }
    printClr("║\n╚", .{ .ansi = .brightCyan });
    for (0..paddedAmount(conf.padding, conf.line_len)) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr("╝\n", .{ .ansi = .brightCyan });
}

fn printWeekly(conf: args.Config, _: u16, contrib_graph: *std.AutoHashMap(u16, u16), allocator: std.mem.Allocator) !void {
    var weeks = [_]u16{0} ** 53;
    var values = contrib_graph.iterator();
    while (values.next()) |item| {
        weeks[@intCast(@as(usize, item.key_ptr.* / 7))] += item.value_ptr.*;
    }
    var max: u16 = 0;
    var max_week: u16 = 0;
    var min: u16 = std.math.maxInt(u16);
    var min_week: u16 = 0;
    for (0..52) |i| {
        const week: u16 = weeks[i];
        if (week > max) {
            max = week;
            max_week = @intCast(i);
        }
        if (week < min and week > 0) {
            min = week;
            min_week = @intCast(i);
        }
    }
    const now = std.time.timestamp();
    const nowgm = ctime.gmtime(&now);
    const yday: f64 = @floatFromInt(nowgm.*.tm_yday);
    var yweek: u16 = @intFromFloat(@ceil(yday / 7.0));
    if (nowgm.*.tm_year + 1900 != conf.year) {
        yweek = 999;
    }
    if (conf.loud) {
        std.debug.print("\nToday is week {d} of year {d}\n", .{ yweek, conf.year });
    }
    const week_num = try std.fmt.allocPrint(allocator, "#{d}", .{max_week});
    const week_contrib_num = try std.fmt.allocPrint(allocator, "{d}", .{max});
    defer allocator.free(week_num);
    defer allocator.free(week_contrib_num);
    printClr("\nBest week ", .{ .ansi = .brightCyan });
    printClr(week_num, .{ .rgb = Github.highest });
    std.debug.print(" with ", .{});
    printClr(week_contrib_num, .{ .rgb = Github.highest });
    std.debug.print(" contributions\n", .{});
    const min_week_num = try std.fmt.allocPrint(allocator, "#{d}", .{min_week});
    const min_week_contrib_num = try std.fmt.allocPrint(allocator, "{d}", .{min});
    defer allocator.free(min_week_num);
    defer allocator.free(min_week_contrib_num);
    printClr("Worst week ", .{ .ansi = .brightCyan });
    printClr(min_week_num, .{ .rgb = Github.highest });
    std.debug.print(" with ", .{});
    printClr(min_week_contrib_num, .{ .rgb = Github.highest });
    std.debug.print(" contributions\n", .{});
    printClr("\n╔", .{ .ansi = .brightCyan });
    for (0..paddedAmount(conf.padding, conf.line_len) / 2 - 4) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr(" HEATMAP ", .{ .ansi = .brightCyan });
    for (0..paddedAmount(conf.padding, conf.line_len) / 2 - 5 + @rem(conf.line_len, 2)) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr("╗\n║", .{ .ansi = .brightCyan });
    for (0..52) |i| {
        if (i != 0 and @rem(i, conf.line_len) == 0) {
            printClr("║\n║", .{ .ansi = .brightCyan });
        }
        const week: u16 = weeks[i];
        const char: []const u8 = if (conf.padding > 0) "█" else "■";
        const now_char: []const u8 = if (conf.padding > 0) "●" else "◆";
        const empty_char: []const u8 = " ";
        if (i == yweek) {
            printPadded(allocator, conf.padding, now_char, .{ .ansi = .red });
            continue;
        }
        if (week == 0) {
            printPadded(allocator, conf.padding, empty_char, .{ .ansi = .brightRed });
        } else {
            const val: f64 = @floatFromInt(week);
            const percent: u16 = @intFromFloat(val / @as(f64, @floatFromInt(max)) * 100.0);
            switch (percent) {
                0...24 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.low });
                },
                25...49 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.medium });
                },
                50...74 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.high });
                },
                75...100 => {
                    printPadded(allocator, conf.padding, char, .{ .rgb = Github.highest });
                },
                else => {
                    printPadded(allocator, conf.padding, empty_char, .{ .rgb = Github.low });
                },
            }
        }
    }
    for (0..paddedAmount(conf.padding, conf.line_len) - paddedAmount(conf.padding, @rem(52, conf.line_len))) |_| {
        printClr(" ", .{ .ansi = .brightCyan });
    }
    printClr("║\n╚", .{ .ansi = .brightCyan });
    for (0..paddedAmount(conf.padding, conf.line_len)) |_| {
        printClr("═", .{ .ansi = .brightCyan });
    }
    printClr("╝\n", .{ .ansi = .brightCyan });
}
