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

const Options = struct {
    var outputNumbers: bool = false;
    var outputNumbersNonEmpty: bool = false;
};

var line_number: u32 = 0;

const File = struct {
    var stdout: std.fs.File = undefined;
    var stdin: std.fs.File = undefined;
    var stderr: std.fs.File = undefined;
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    File.stdout = std.io.getStdOut();
    File.stdin = std.io.getStdIn();
    File.stderr = std.io.getStdErr();

    if (args.len == 1) {
        try proccessFile(File.stdin);
    } else {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help")) {
                try print_usage(File.stdout);
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg, "--version")) {
                try print_version(File.stdout);
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg, "--number")) {
                Options.outputNumbers = true;
            } else if (std.mem.eql(u8, arg, "--number-nonblank")) {
                Options.outputNumbersNonEmpty = true;
            } else if (std.mem.eql(u8, arg[0..1], "-") and !std.mem.eql(u8, arg[1..1], "-")) {
                for (arg[1..]) |opt| {
                    if (opt == 'n') {
                        Options.outputNumbers = true;
                    } else if (opt == 'b') {
                        Options.outputNumbersNonEmpty = true;
                    }
                }
            } else if (std.mem.eql(u8, arg[0..2], "--") or (std.mem.eql(u8, arg[0..1], "-") and arg.len != 1)) {
                try argument_error(gpa, arg);
                std.os.exit(1);
            } else if (std.mem.eql(u8, arg, "-")) {
                try proccessFile(File.stdin);
            } else {
                try processFileByName(arg);
            }
        }
    }
}

fn argument_error(allocator: std.mem.Allocator, arg: []u8) !void {
    try print_usage(File.stderr);
    const message = std.fmt.allocPrint(allocator, "\nError: argument '{s}' is unknown\n", .{arg}) catch unreachable;
    defer allocator.free(message);
    try File.stderr.writeAll(message);
}

fn processFileByName(name: []const u8) !void {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    try proccessFile(file);
}

fn proccessFile(in: std.fs.File) !void {
    if (Options.outputNumbers or Options.outputNumbersNonEmpty) {
        return processLines(in);
    }
    return copyFile(in);
}

fn copyFile(in: std.fs.File) !void {
    var buffer: [1024]u8 = undefined;
    var read = try in.readAll(&buffer);
    while (read > 0) {
        try File.stdout.writeAll(buffer[0..read]);
        read = try in.readAll(&buffer);
    }
}

fn processLines(in: std.fs.File) !void {
    var buffered_Reader = std.io.bufferedReader(in.reader());
    var reader = buffered_Reader.reader();
    var buffer: [1024]u8 = undefined;

    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        if (Options.outputNumbersNonEmpty) {
            if (line.len > 0) {
                line_number += 1;
                try std.fmt.format(File.stdout.writer(), "{d: >6}\t{s}\n", .{ line_number, line });
            } else {
                try File.stdout.writeAll("\n");
            }
        } else if (Options.outputNumbers) {
            line_number += 1;
            try std.fmt.format(File.stdout.writer(), "{d: >6}\t{s}\n", .{ line_number, line });
        }
    }
}
