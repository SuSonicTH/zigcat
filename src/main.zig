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
    outputNumbers: bool = false,
    outputNumbersNonEmpty: bool = false,
    showEnds: bool = false,
    squeezeBlank: bool = false,
    showTabs: bool = false,
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var options = Options{};

    if (args.len == 1) {
        try proccessFile(std.io.getStdIn().reader(), std.io.getStdOut().writer(), options);
    } else {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help")) {
                try print_usage(std.io.getStdOut());
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg, "--version")) {
                try print_version(std.io.getStdOut());
                std.os.exit(0);
            } else if (std.mem.eql(u8, arg, "--number")) {
                options.outputNumbers = true;
            } else if (std.mem.eql(u8, arg, "--number-nonblank")) {
                options.outputNumbersNonEmpty = true;
            } else if (std.mem.eql(u8, arg, "--show-ends")) {
                options.outputNumbersNonEmpty = true;
            } else if (std.mem.eql(u8, arg, "--squeeze-blank")) {
                options.squeezeBlank = true;
            } else if (std.mem.eql(u8, arg, "--show-tabs")) {
                options.showTabs = true;
            } else if (std.mem.eql(u8, arg[0..2], "--")) {
                try argument_error(gpa, arg);
                std.os.exit(1);
            } else if (arg[0] == '-' and arg.len > 1) {
                for (arg[1..]) |opt| {
                    switch (opt) {
                        'n' => options.outputNumbers = true,
                        'b' => options.outputNumbersNonEmpty = true,
                        'E' => options.showEnds = true,
                        's' => options.squeezeBlank = true,
                        'T' => options.showTabs = true,
                        else => {
                            var optArg = [_]u8{ '-', opt };
                            try argument_error(gpa, &optArg);
                            std.os.exit(1);
                        },
                    }
                }
            } else if (arg[0] == '-') {
                try proccessFile(std.io.getStdIn().reader(), std.io.getStdOut().writer(), options);
            } else {
                try processFileByName(arg, options);
            }
        }
    }
}

fn argument_error(allocator: std.mem.Allocator, arg: []u8) !void {
    const message = std.fmt.allocPrint(allocator, "\nError: argument '{s}' is unknown\n", .{arg}) catch unreachable;
    defer allocator.free(message);
}

fn processFileByName(name: []const u8, options: Options) !void {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    try proccessFile(file.reader(), std.io.getStdOut().writer(), options);
}

fn proccessFile(reader: std.fs.File.Reader, writer: std.fs.File.Writer, options: Options) !void {
    if (options.outputNumbers or options.outputNumbersNonEmpty or options.showEnds or options.squeezeBlank or options.showTabs) {
        return processLines(reader, writer, options);
    }
    return copyFile(reader, writer);
}

fn copyFile(reader: anytype, writer: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var read = try reader.readAll(&buffer);
    while (read > 0) {
        try writer.writeAll(buffer[0..read]);
        read = try reader.readAll(&buffer);
    }
}

var line_number: u32 = 0;

fn processLines(reader: anytype, writer: anytype, options: Options) !void {
    var buffered_reader = std.io.bufferedReader(reader);
    var buffer: [1024]u8 = undefined;
    var last_was_blank: bool = false;

    while (try buffered_reader.reader().readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        if (options.squeezeBlank) {
            if (line.len == 0) {
                if (last_was_blank) {
                    continue;
                }
                last_was_blank = true;
            } else {
                last_was_blank = false;
            }
        }

        if (options.outputNumbersNonEmpty) {
            if (line.len > 0) {
                line_number += 1;
                try std.fmt.format(writer, "{d: >6}\t", .{line_number});
            }
        } else if (options.outputNumbers) {
            line_number += 1;
            try std.fmt.format(writer, "{d: >6}\t", .{line_number});
        }

        if (options.showTabs) {
            var add_tab: bool = false;
            var iter = std.mem.splitSequence(u8, line, "\t");
            while (iter.next()) |part| {
                if (add_tab) {
                    try writer.writeAll("^I");
                }
                try writer.writeAll(part);
                add_tab = true;
            }
        } else {
            try writer.writeAll(line);
        }

        if (options.showEnds) {
            try writer.writeAll("$");
        }
        try writer.writeAll("\n");
    }
}

test "copyFile unmodifyed" {
    const input = @embedFile("tests/input.txt");
    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    var writer = source.writer();

    try copyFile(reader, writer);

    try std.testing.expectEqualStrings(input, source.buffer.getWritten());
}

test "processLines unmodifyed" {
    const input = @embedFile("tests/input.txt");
    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    var writer = source.writer();

    var options = Options{};
    try processLines(reader, writer, options);

    try std.testing.expectEqualStrings(input, source.buffer.getWritten());
}

test "processLines --number" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_number.txt");

    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    var writer = source.writer();

    var options = Options{ .outputNumbers = true };
    line_number = 0;
    try processLines(reader, writer, options);

    try std.testing.expectEqualStrings(expected_output, source.buffer.getWritten());
}

test "processLines --number-nonblank" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_number-nonblank.txt");

    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    var writer = source.writer();

    var options = Options{ .outputNumbersNonEmpty = true };
    line_number = 0;
    try processLines(reader, writer, options);

    try std.testing.expectEqualStrings(expected_output, source.buffer.getWritten());
}
