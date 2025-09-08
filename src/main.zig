const std = @import("std");
const builtin = @import("builtin");

const version = "zigcat v0.1\n\n";

fn printUsage(writer: *std.Io.Writer, exit: bool) !void {
    const help = @embedFile("USAGE.txt");
    try writer.writeAll(version ++ help);
    try writer.flush();
    if (exit) {
        std.process.exit(0);
    }
}

fn printVersion(writer: *std.Io.Writer) !void {
    const license = @embedFile("LICENSE.txt");
    try writer.writeAll(version ++ license);
    try writer.flush();
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

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    if (args.len == 1) {
        try proccessFile(stdin, stdout, options);
    } else {
        for (args[1..]) |arg| {
            if (arg[0] == '-') {
                switch (std.meta.stringToEnum(Arguments, arg) orelse {
                    try argumentError(arg);
                }) {
                    .@"--help" => try printUsage(stdout, true),
                    .@"--version" => try printVersion(stdout),
                    .@"--number", .@"-n" => options.outputNumbers = true,
                    .@"--number-nonblank", .@"-b" => options.outputNumbersNonEmpty = true,
                    .@"--show-ends", .@"-E" => options.showEnds = true,
                    .@"--squeeze-blank", .@"-s" => options.squeezeBlank = true,
                    .@"--show-tabs", .@"-T" => options.showTabs = true,
                    .@"-" => try proccessFile(stdin, stdout, options),
                }
            } else {
                try processFileByName(arg, stdout, options);
            }
        }
    }
}

fn argumentError(arg: []u8) !noreturn {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    const stderr = &stderr_writer.interface;

    try printUsage(stderr, false);
    try stderr.print("argument '{s}' is unknown\n", .{arg});
    try stderr.flush();
    std.process.exit(1);
}

fn processFileByName(name: []const u8, writer: *std.Io.Writer, options: Options) !void {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fs.realpath(name, &path_buffer);
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(&buffer);
    try proccessFile(&reader.interface, writer, options);
}

fn proccessFile(reader: *std.Io.Reader, writer: *std.Io.Writer, options: Options) !void {
    if (@as(u5, @bitCast(options)) > 0) {
        return processLines(reader, writer, options);
    }
    return copyFile(reader, writer);
}

fn copyFile(reader: *std.Io.Reader, writer: *std.Io.Writer) !void {
    _ = try reader.streamRemaining(writer);
    try writer.flush();
}

var line_number: u32 = 0;

fn processLines(reader: *std.Io.Reader, writer: *std.Io.Writer, options: Options) !void {
    var last_was_blank: bool = false;

    while (true) {
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };

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
                try writer.print("{d: >6}\t", .{line_number});
            }
        } else if (options.outputNumbers) {
            line_number += 1;
            try writer.print("{d: >6}\t", .{line_number});
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
    var reader = std.Io.Reader.fixed(input);

    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    try copyFile(&reader, &writer);

    try std.testing.expectEqualStrings(input, buffer[0..writer.end]);
}

fn test_processing(input: []const u8, options: Options, expected_output: []const u8) !void {
    var reader = std.Io.Reader.fixed(input);

    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    line_number = 0;
    try processLines(&reader, &writer, options);
    try std.testing.expectEqualStrings(expected_output, buffer[0..writer.end]);
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
