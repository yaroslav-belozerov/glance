pub const Config = struct { author: []const u8, path: []const u8, padding: u16, loud: bool, top: u16 };

const usage =
    \\Usage: glance AUTHOR [OPTIONS]
    \\Options:
    \\  --padding=NUM      Set the padding on each side of point in heatmap
    \\  --top=NUM          Set how many most contributed to show
    \\  --loud             Output error messages
    \\  --help             Print this help page
    \\
;

const ArgType = enum {
    path,
    padding,
    top,
    loud,
    help,
    unknown,
};

pub fn printUsage() void {
    std.io.getStdOut().writer().print("{s}", .{usage}) catch @panic("Could not print usage.");
}

fn getArgType(arg: []const u8) ArgType {
    if (std.mem.startsWith(u8, arg, "--path=")) return .path;
    if (std.mem.startsWith(u8, arg, "--padding=")) return .padding;
    if (std.mem.startsWith(u8, arg, "--top=")) return .top;
    if (std.mem.eql(u8, "--loud", arg)) return .loud;
    if (std.mem.eql(u8, "--help", arg)) return .help;
    if (std.mem.startsWith(u8, arg, "--")) return .unknown;
    return .unknown;
}

pub fn parseArgs(arguments: [][*:0]u8) Config {
    var config = Config{ .author = "", .path = ".", .padding = 0, .loud = false, .top = 3 };
    const args = arguments[1..];

    if (args.len == 0) {
        printUsage();
        std.process.exit(1);
    } else {
        const author: []const u8 = std.mem.span(args[0]);
        config.author = author;
    }

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

    return config;
}

const std = @import("std");
