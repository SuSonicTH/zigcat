const std = @import("std");

const version = "zigcat v0.1\n\n";

fn print_usage(file: std.fs.File) !void {
    const help = @embedFile("USAGE.txt");
    try file.writeAll(version ++ help);
}

fn print_version(file: std.fs.File) !void {
    const licence = @embedFile("LICENSE.txt");
    try file.writeAll(version ++ licence);
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();

    if (args.len == 1) {
        try copy(stdin, stdout);
    } else {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help")) {
                try print_usage(stdout);
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg, "--version")) {
                try print_version(stdout);
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg[0..2], "--")) {
                try argument_error(arg);
                std.os.exit(1);
            } else if (std.mem.eql(u8, arg, "-")) {
                try copy(stdin, stdout);
            } else {
                try copy_file(arg, stdout);
            }
        }
    }
}

fn argument_error(arg: []u8) !void {
    const stderr = std.io.getStdErr();
    try print_usage(stderr);
    try stderr.writeAll("Error: argument '");
    try stderr.writeAll(arg);
    try stderr.writeAll("' is unknown\n");
}

fn copy_file(name: []const u8, out: std.fs.File) !void {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    try copy(file, out);
}

fn copy(in: std.fs.File, out: std.fs.File) !void {
    var buffer: [1024]u8 = undefined;
    var read = try in.readAll(&buffer);
    while (read > 0) {
        try out.writeAll(buffer[0..read]);
        read = try in.readAll(&buffer);
    }
}
