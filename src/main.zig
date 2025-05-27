const std = @import("std");
const builtin = @import("builtin");

const version = "zigcat v0.1\n\n";

fn printUsage(file: std.fs.File, exit: bool) !void {
    const help = @embedFile("USAGE.txt");
    try file.writeAll(version ++ help);
    if (exit) {
        std.process.exit(0);
    }
}

fn printVersion(file: std.fs.File) !void {
    const license = @embedFile("LICENSE.txt");
    try file.writeAll(version ++ license);
    std.process.exit(0);
}

const Options = packed struct {
    outputNumbers: bool = false,
    outputNumbersNonEmpty: bool = false,
    showEnds: bool = false,
    squeezeBlank: bool = false,
    showTabs: bool = false,
};

const Arguments = enum {
    @"--help",
    @"--version",
    @"--number",
    @"-n",
    @"--number-nonblank",
    @"-b",
    @"--show-ends",
    @"-E",
    @"--squeeze-blank",
    @"-s",
    @"--show-tabs",
    @"-T",
    @"-",
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var options = Options{};

    if (args.len == 1) {
        try proccessFile(std.io.getStdIn().reader(), std.io.getStdOut().writer(), options);
    } else {
        for (args[1..]) |arg| {
            if (arg[0] == '-') {
                switch (std.meta.stringToEnum(Arguments, arg) orelse {
                    try argumentError(arg);
                }) {
                    .@"--help" => try printUsage(std.io.getStdOut(), true),
                    .@"--version" => try printVersion(std.io.getStdOut()),
                    .@"--number", .@"-n" => options.outputNumbers = true,
                    .@"--number-nonblank", .@"-b" => options.outputNumbersNonEmpty = true,
                    .@"--show-ends", .@"-E" => options.showEnds = true,
                    .@"--squeeze-blank", .@"-s" => options.squeezeBlank = true,
                    .@"--show-tabs", .@"-T" => options.showTabs = true,
                    .@"-" => try proccessFile(std.io.getStdIn().reader(), std.io.getStdOut().writer(), options),
                }
            } else {
                try processFileByName(arg, options);
            }
        }
    }
}

fn argumentError(arg: []u8) !noreturn {
    try printUsage(std.io.getStdErr(), false);
    std.log.err("argument '{s}' is unknown\n", .{arg});
    std.process.exit(1);
}

fn processFileByName(name: []const u8, options: Options) !void {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    try proccessFile(file.reader(), std.io.getStdOut().writer(), options);
}

fn proccessFile(reader: std.fs.File.Reader, writer: std.fs.File.Writer, options: Options) !void {
    if (@as(u5, @bitCast(options)) > 0) {
        return processLines(reader, writer, options);
    }
    return copyFile(reader, writer);
}

fn copyFile(reader: anytype, writer: anytype) !void {
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = std.heap.page_size_max }).init();
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

test "options check" {
    var opts = Options{};
    try std.testing.expect(@as(u5, @bitCast(opts)) == 0);
    opts.showTabs = true;
    try std.testing.expect(@as(u5, @bitCast(opts)) != 0);
}

test "copyFile" {
    const input = @embedFile("tests/input.txt");
    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    const writer = source.writer();

    try copyFile(reader, writer);

    try std.testing.expectEqualStrings(input, source.buffer.getWritten());
}

fn test_processing(input: []const u8, options: Options, expected_output: []const u8) !void {
    var input_stream = std.io.fixedBufferStream(input);
    const reader = input_stream.reader();

    var buffer: [512]u8 = undefined;
    var source = std.io.StreamSource{ .buffer = std.io.fixedBufferStream(&buffer) };
    const writer = source.writer();

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
