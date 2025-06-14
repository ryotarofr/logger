const std = @import("std");
const Struct = @import("struct.zig");
const Config = @import("config.zig");
const util = @import("util.zig");

const LogLevel = Struct.LogLevel;
const LogEntry = Struct.LogEntry;
const Allocator = std.mem.Allocator;

fn logLevelToString(level: LogLevel) []const u8 {
    return switch (level) {
        .Debug => "debug",
        .Info => "info",
        .Warning => "warning",
        .Error => "error",
        .Critical => "critical",
    };
}

fn logLevelPrefix(level: LogLevel, allocator: Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "logger.{s}(\"", .{logLevelToString(level)});
}

const LogExtractor = struct {
    pyfile: []const u8,
    allocator: Allocator,

    const Self = @This();

    fn extract(self: Self) !std.ArrayList(LogEntry) {
        const source = try util.readJsonFile(self.allocator, self.pyfile);
        var logs = std.ArrayList(LogEntry).init(self.allocator);
        var it = std.mem.tokenizeAny(u8, source, "\n");

        while (it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            const info = @typeInfo(LogLevel);
            inline for (info.@"enum".fields) |field| {
                const level: LogLevel = @enumFromInt(field.value);
                const prefix = try logLevelPrefix(level, self.allocator);
                defer self.allocator.free(prefix);

                if (std.mem.indexOf(u8, trimmed, prefix)) |start| {
                    const msg_start = start + prefix.len;
                    if (std.mem.indexOfScalar(u8, trimmed[msg_start..], '"')) |msg_end| {
                        const msg = trimmed[msg_start .. msg_start + msg_end];
                        try logs.append(.{ .level = level, .message = msg });
                        break;
                    }
                }
            }
        }
        return logs;
    }
};

const JsonFormatter = struct {
    allocator: Allocator,
    logs: []const LogEntry,

    const Self = @This();

    fn init(allocator: Allocator, logs: []const LogEntry) Self {
        return .{ .allocator = allocator, .logs = logs };
    }

    fn format(self: Self, root_id: []const u8, is_lambda: bool) ![]u8 {
        var list = std.ArrayList(u8).init(self.allocator);
        defer list.deinit();
        const writer = list.writer();

        try writer.print("{{\n  \"{s}\": {{\n", .{root_id});

        for (self.logs, 0..) |log, i| {
            const id_buf = try std.fmt.allocPrint(self.allocator, "{d:0>3}", .{i + 1});
            defer self.allocator.free(id_buf);

            if (i > 0) try writer.writeAll(",\n");

            if (is_lambda) {
                try writer.print("    \"{s}\": \"{s}\"", .{ log.message, id_buf });
            } else {
                try writer.print("    \"{s}\": {{\n      \"level\": \"{s}\",\n      \"message\": \"{s}\"\n    }}", .{ id_buf, logLevelToString(log.level), log.message });
            }
        }

        try writer.writeAll("\n  }\n}");
        return list.toOwnedSlice();
    }
};

pub const LoggerRunner = struct {
    pyfile: []const u8,
    root_id: []const u8,
    output_path: []const u8,
    is_lambda: bool,

    const Self = @This();
    const allocator = std.heap.page_allocator;

    pub fn run(self: Self) void {
        var extractor = LogExtractor{
            .pyfile = self.pyfile,
            .allocator = allocator,
        };

        var logs = extractor.extract() catch return;
        if (logs.items.len == 0) {
            std.debug.print("No log entries found. Skipping output.\n", .{});
            logs.deinit();
            return;
        }
        defer logs.deinit();

        const formatter = JsonFormatter.init(allocator, logs.items);
        const json = formatter.format(self.root_id, self.is_lambda) catch return;
        defer allocator.free(json);

        const out_file = std.fs.cwd().createFile(self.output_path, .{ .truncate = true }) catch return;
        defer out_file.close();
        out_file.writeAll(json) catch return;
    }
};
