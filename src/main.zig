const std = @import("std");

const version = "zigcat v0.1\n\n";

fn printUsage(file: std.fs.File, exit: bool) !void {
    const help = @embedFile("USAGE.txt");
    try file.writeAll(version ++ help);
    if (exit) {
        std.os.exit(0);
    }
}

fn printVersion(file: std.fs.File) !void {
    const license = @embedFile("LICENSE.txt");
    try file.writeAll(version ++ license);
    std.os.exit(0);
}

const Options = struct {
    outputNumbers: bool = false,
    outputNumbersNonEmpty: bool = false,
    showEnds: bool = false,
    squeezeBlank: bool = false,
    showTabs: bool = false,
};

const Arguments = enum {
    help,
    version,
    number,
    @"number-nonblank",
    @"show-ends",
    @"squeeze-blank",
    @"show-tabs",
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
            if (std.mem.startsWith(u8, arg, "--")) {
                switch (std.meta.stringToEnum(Arguments, arg[2..]) orelse {
                    try argumentError(arg);
                }) {
                    .help => try printUsage(std.io.getStdOut(), true),
                    .version => try printVersion(std.io.getStdOut()),
                    .number => options.outputNumbers = true,
                    .@"number-nonblank" => options.outputNumbersNonEmpty = true,
                    .@"show-ends" => options.showEnds = true,
                    .@"squeeze-blank" => options.squeezeBlank = true,
                    .@"show-tabs" => options.showTabs = true,
                }
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
                            try argumentError(&optArg);
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

fn argumentError(arg: []u8) !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("argument '{s}' is unknown\n", .{arg});
    std.os.exit(1);
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
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = std.mem.page_size }).init();
    try fifo.pump(reader, writer);
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

test "copyFile" {
    const input = @embedFile("tests/input.txt");
    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    var writer = source.writer();

    try copyFile(reader, writer);

    try std.testing.expectEqualStrings(input, source.buffer.getWritten());
}

fn test_processing(input: []const u8, options: Options, expected_output: []const u8) !void {
    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    var writer = source.writer();

    line_number = 0;
    try processLines(reader, writer, options);
    try std.testing.expectEqualStrings(expected_output, source.buffer.getWritten());
}

test "zigcat" {
    const input = @embedFile("tests/input.txt");

    try test_processing(input, .{}, input);
}

test "zigcat --number" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_number.txt");

    try test_processing(input, .{ .outputNumbers = true }, expected_output);
}

test "zigcat --number-nonblank" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_number-nonblank.txt");

    try test_processing(input, .{ .outputNumbersNonEmpty = true }, expected_output);
}

test "zigcat --number --number-nonblank" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_number-nonblank.txt");

    try test_processing(input, .{ .outputNumbers = true, .outputNumbersNonEmpty = true }, expected_output);
}

test "zigcat --show-ends" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_show-ends.txt");

    try test_processing(input, .{ .showEnds = true }, expected_output);
}

test "zigcat --squeeze-blank" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_squeeze-blank.txt");

    try test_processing(input, .{ .squeezeBlank = true }, expected_output);
}

test "zigcat --show-tabs" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_show-tabs.txt");

    try test_processing(input, .{ .showTabs = true }, expected_output);
}

test "zigcat --number-nonblank --show-ends --squeeze-blank --show-tabs" {
    const input = @embedFile("tests/input.txt");
    const expected_output = @embedFile("tests/expected_number-nonblank_show-ends_squeeze-blank_show-tabs.txt");

    const options = Options{
        .outputNumbersNonEmpty = true,
        .showEnds = true,
        .squeezeBlank = true,
        .showTabs = true,
    };

    try test_processing(input, options, expected_output);
}
