pub const Config = struct { author: []const u8, path: []const u8, padding: u16, loud: bool, top: u16, year: u16, weekly: bool, line_len: u16, no_intro: bool };

const usage =
    \\Usage: glance AUTHOR [OPTIONS]
    \\Options:
    \\  --year=NUM         The year to track progress for
    \\  --padding=NUM      Set the padding on each side of point in heatmap
    \\  --top=NUM          Set how many most contributed to show
    \\  --line-len=NUM     Set the length of each line in heatmap
    \\  --weekly           Group heatmap by week
    \\  --loud             Output error and debug info
    \\  --no-intro         Do not print welcome message
    \\  --help             Print this help page
    \\
;

const ArgType = enum {
    path,
    padding,
    top,
    line_len,
    no_intro,
    loud,
    year,
    weekly,
    help,
    unknown,
};

pub fn printUsage() void {
    std.io.getStdOut().writer().print("{s}", .{usage}) catch @panic("Could not print usage.");
}

fn getArgType(arg: []const u8) ArgType {
    if (std.mem.startsWith(u8, arg, "--path=")) return .path;
    if (std.mem.startsWith(u8, arg, "--year=")) return .year;
    if (std.mem.startsWith(u8, arg, "--padding=")) return .padding;
    if (std.mem.startsWith(u8, arg, "--top=")) return .top;
    if (std.mem.startsWith(u8, arg, "--line-len=")) return .line_len;
    if (std.mem.eql(u8, "--no-intro", arg)) return .no_intro;
    if (std.mem.eql(u8, "--loud", arg)) return .loud;
    if (std.mem.eql(u8, "--weekly", arg)) return .weekly;
    if (std.mem.eql(u8, "--help", arg)) return .help;
    if (std.mem.startsWith(u8, arg, "--")) return .unknown;
    return .unknown;
}

pub fn parseArgs(arguments: [][*:0]u8) Config {
    const now = std.time.timestamp();
    const nowgm = ctime.gmtime(&now);
    var config = Config{ .author = "", .path = ".", .padding = 0, .loud = false, .top = 3, .year = @intCast(nowgm.*.tm_year + 1900), .weekly = false, .line_len = 31, .no_intro = false };
    const args = arguments[1..];

    if (args.len == 0) {
        printUsage();
        std.process.exit(1);
    } else {
        const author: []const u8 = std.mem.span(args[0]);
        config.author = author;
    }

    var line_len_not_default = false;
    for (args[1..]) |argument| {
        const arg = std.mem.span(argument);
        switch (getArgType(arg)) {
            .path => {
                config.path = arg[7..];
            },
            .padding => {
                config.padding = std.fmt.parseInt(u16, arg[10..], 10) catch {
                    printUsage();
                    std.process.exit(1);
                };
            },
            .top => {
                config.top = std.fmt.parseInt(u16, arg[6..], 10) catch {
                    printUsage();
                    std.process.exit(1);
                };
            },
            .loud => {
                config.loud = true;
            },
            .weekly => {
                config.weekly = true;
            },
            .no_intro => {
                config.no_intro = true;
            },
            .year => {
                config.year = std.fmt.parseInt(u16, arg[7..], 10) catch {
                    printUsage();
                    std.process.exit(1);
                };
            },
            .line_len => {
                const line_len = std.fmt.parseInt(u16, arg[11..], 10) catch {
                    printUsage();
                    std.process.exit(1);
                };
                if (line_len < 10) {
                    std.debug.print("Line length must not be less than 10 characters. Use --weekly if you want compact output.\n", .{});
                    std.process.exit(1);
                } else if (line_len > 130) {
                    std.debug.print("Line length must not be more than 130 characters.\n", .{});
                    std.process.exit(1);
                }
                line_len_not_default = true;
                config.line_len = line_len;
            },
            .help => {
                printUsage();
                std.process.exit(0);
            },
            .unknown => {
                if (std.mem.startsWith(u8, arg, "--")) {
                    printUsage();
                    std.process.exit(1);
                }
            },
        }
    }
    if (config.weekly and !line_len_not_default) {
        config.line_len = 12;
    }

    return config;
}

const std = @import("std");
const ctime = @cImport({
    @cInclude("time.h");
});
