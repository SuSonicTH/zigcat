const std = @import("std");

const version = "zigcat v0.1\n\n";

fn print_usage(file: std.fs.File) !void {
    const help = @embedFile("USAGE.txt");
    try file.writeAll(version ++ help);
}

fn print_version(file: std.fs.File) !void {
    const license = @embedFile("LICENSE.txt");
    try file.writeAll(version ++ license);
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();

    if (args.len == 1) {
        try copyFile(stdin);
    } else {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help")) {
                try print_usage(stdout);
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg, "--version")) {
                try print_version(stdout);
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg[0..2], "--") or (std.mem.eql(u8, arg[0..1], "-") and arg.len != 1)) {
                try argument_error(gpa, arg);
                std.os.exit(1);
            } else if (std.mem.eql(u8, arg, "-")) {
                try copyFile(stdin);
            } else {
                try copyFileByName(arg);
            }
        }
    }
}

fn argument_error(allocator: std.mem.Allocator, arg: []u8) !void {
    const stderr = std.io.getStdErr();
    try print_usage(stderr);
    const message = std.fmt.allocPrint(allocator, "\nError: argument '{s}' is unknown\n", .{arg}) catch unreachable;
    defer allocator.free(message);
    try stderr.writeAll(message);
}

fn copyFileByName(name: []const u8) !void {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    try copyFile(file);
}

fn copyFile(in: std.fs.File) !void {
    const stdout = std.io.getStdOut();
    var buffer: [1024]u8 = undefined;
    var read = try in.readAll(&buffer);
    while (read > 0) {
        try stdout.writeAll(buffer[0..read]);
        read = try in.readAll(&buffer);
    }
}
