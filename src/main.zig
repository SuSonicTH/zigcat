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
    var showEnds: bool = false;
    var squeezeBlank: bool = false;
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
            } else if (std.mem.eql(u8, arg, "--show-ends")) {
                Options.outputNumbersNonEmpty = true;
            } else if (std.mem.eql(u8, arg, "--squeeze-blank")) {
                Options.squeezeBlank = true;
            } else if (std.mem.eql(u8, arg[0..2], "--")) {
                try argument_error(gpa, arg);
                std.os.exit(1);
            } else if (arg[0] == '-' and arg.len > 1) {
                for (arg[1..]) |opt| {
                    switch (opt) {
                        'n' => Options.outputNumbers = true,
                        'b' => Options.outputNumbersNonEmpty = true,
                        'E' => Options.showEnds = true,
                        's' => Options.squeezeBlank = true,
                        else => {
                            var optArg = [_]u8{ '-', opt };
                            try argument_error(gpa, &optArg);
                            std.os.exit(1);
                        },
                    }
                }
            } else if (arg[0] == '-') {
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
    if (Options.outputNumbers or Options.outputNumbersNonEmpty or Options.showEnds or Options.squeezeBlank) {
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
    var last_was_blank: bool = false;

    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        if (Options.squeezeBlank) {
            if (line.len == 0) {
                if (last_was_blank) {
                    continue;
                }
                last_was_blank = true;
            } else {
                last_was_blank = false;
            }
        }

        if (Options.outputNumbersNonEmpty) {
            if (line.len > 0) {
                line_number += 1;
                try std.fmt.format(File.stdout.writer(), "{d: >6}\t{s}", .{ line_number, line });
            }
        } else if (Options.outputNumbers) {
            line_number += 1;
            try std.fmt.format(File.stdout.writer(), "{d: >6}\t{s}", .{ line_number, line });
        } else {
            try File.stdout.writeAll(line);
        }

        if (Options.showEnds) {
            try File.stdout.writeAll("$");
        }
        try File.stdout.writeAll("\n");
    }
}
