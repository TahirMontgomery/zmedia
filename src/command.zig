const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Owned argument list for an external process.
/// Every argument is duplicated into command-owned memory.
pub const Command = struct {
    allocator: Allocator,
    executable: []const u8,
    arguments: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator, executable: []const u8) Command {
        return .{
            .allocator = allocator,
            .executable = executable,
            .arguments = .empty,
        };
    }

    pub fn deinit(self: *Command) void {
        for (self.arguments.items) |argument| {
            self.allocator.free(argument);
        }
        self.arguments.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn append(self: *Command, value: []const u8) !void {
        const owned = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned);
        try self.arguments.append(self.allocator, owned);
    }

    pub fn appendFormat(
        self: *Command,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const owned = try std.fmt.allocPrint(self.allocator, fmt, args);
        errdefer self.allocator.free(owned);
        try self.arguments.append(self.allocator, owned);
    }

    /// Returns the argument list without the executable.
    pub fn argv(self: *const Command) []const []const u8 {
        return self.arguments.items;
    }

    /// Builds a full argv including the executable as argv[0].
    /// Caller owns the returned slice (but not the string contents).
    pub fn fullArgv(self: *const Command, allocator: Allocator) ![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        errdefer list.deinit(allocator);

        try list.append(allocator, self.executable);
        try list.appendSlice(allocator, self.arguments.items);
        return try list.toOwnedSlice(allocator);
    }

    /// Renders a shell-like string for debugging only.
    /// Do not use the result to execute the process.
    pub fn render(self: *const Command, writer: *Io.Writer) !void {
        try writer.writeAll(self.executable);
        for (self.arguments.items) |argument| {
            try writer.writeAll(" ");
            try writeQuoted(writer, argument);
        }
    }

    pub fn renderAlloc(self: *const Command, allocator: Allocator) ![]u8 {
        var allocating: Io.Writer.Allocating = .init(allocator);
        errdefer allocating.deinit();
        try self.render(&allocating.writer);
        return try allocating.toOwnedSlice();
    }
};

fn writeQuoted(writer: *Io.Writer, value: []const u8) !void {
    const needs_quotes = for (value) |byte| {
        switch (byte) {
            ' ', '\t', '\n', '"', '\'' => break true,
            else => {},
        }
    } else false;

    if (!needs_quotes) {
        try writer.writeAll(value);
        return;
    }

    try writer.writeAll("\"");
    for (value) |byte| {
        if (byte == '"') {
            try writer.writeAll("\\\"");
        } else {
            try writer.writeByte(byte);
        }
    }
    try writer.writeAll("\"");
}
