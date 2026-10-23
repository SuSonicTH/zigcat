const std = @import("std");
const builtin = @import("builtin");

const version = "zigcat v0.2\n\n";

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

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(init.io, &stdin_buffer);
    const stdin = &stdin_reader.interface;

    var options = Options{};

    // Parse all options before processing any operand so that a flag applies to
    // every file, no matter where it appears on the command line.
    for (args[1..]) |arg| {
        if (arg.len == 0 or arg[0] != '-') continue;

        switch (std.meta.stringToEnum(Arguments, arg) orelse {
            try argumentError(init.io, arg);
        }) {
            .@"--help" => try printUsage(stdout, true),
            .@"--version" => try printVersion(stdout),
            .@"--number", .@"-n" => options.outputNumbers = true,
            .@"--number-nonblank", .@"-b" => options.outputNumbersNonEmpty = true,
            .@"--show-ends", .@"-E" => options.showEnds = true,
            .@"--squeeze-blank", .@"-s" => options.squeezeBlank = true,
            .@"--show-tabs", .@"-T" => options.showTabs = true,
            .@"-" => {},
        }
    }

    var operand_seen = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-")) {
            try proccessFile(stdin, stdout, options);
            operand_seen = true;
        } else if (arg.len == 0 or arg[0] != '-') {
            try processFileByName(init.io, arg, stdout, options);
            operand_seen = true;
        }
    }

    // Like cat, read standard input when no file operand is given.
    if (!operand_seen) {
        try proccessFile(stdin, stdout, options);
    }

    try stdout.flush();
}

fn argumentError(io: std.Io, arg: [:0]const u8) !noreturn {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    try printUsage(stderr, false);
    try stderr.print("argument '{s}' is unknown\n", .{arg});
    try stderr.flush();
    std.process.exit(1);
}

fn processFileByName(io: std.Io, name: []const u8, writer: *std.Io.Writer, options: Options) !void {
    const file = try std.Io.Dir.cwd().openFile(io, name, .{});
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    try proccessFile(&reader.interface, writer, options);
}

fn proccessFile(reader: *std.Io.Reader, writer: *std.Io.Writer, options: Options) !void {
    if (@as(u5, @bitCast(options)) == 0) {
        return copyFile(reader, writer);
    }
    return processLines(reader, writer, options);
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

        // End of stream also terminates a line, but has no delimiter to consume.
        const next_byte: ?u8 = reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => return err,
        };
        const has_newline = if (next_byte) |byte| byte == '\n' else false;
        if (has_newline) {
            reader.toss(1);
        }

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

        if (options.showEnds and has_newline) {
            try writer.writeAll("$");
        }
        if (has_newline) {
            try writer.writeAll("\n");
        }
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

test "zigcat last line without trailing newline" {
    try test_processing("no trailing newline", .{ .outputNumbers = true }, "     1\tno trailing newline");
    try test_processing("no trailing newline", .{ .showEnds = true }, "no trailing newline");
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
