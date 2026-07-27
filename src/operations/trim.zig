//! Stub: process-backed trim/clip by timestamps.
//! Implement when Ember needs offline trim. See docs/PROCESS_OPS_BACKLOG.md.
const std = @import("std");
const command_mod = @import("../process/command.zig");
const common = @import("common.zig");
const runtime_mod = @import("../process/runtime.zig");
const time = @import("../time.zig");
const validation = @import("../validation.zig");

const Command = command_mod.Command;
const ProcessRuntime = runtime_mod.ProcessRuntime;
const ProcessConfig = runtime_mod.ProcessConfig;
const Timestamp = time.Timestamp;
const ValidationError = validation.ValidationError;

pub const Trim = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    start_value: ?Timestamp = null,
    end_value: ?Timestamp = null,
    overwrite_existing: bool = false,

    pub fn init(input_path: []const u8) Trim {
        return .{ .input_path = input_path };
    }

    pub fn start(self: *Trim, value: Timestamp) *Trim {
        self.start_value = value;
        return self;
    }

    pub fn end(self: *Trim, value: Timestamp) *Trim {
        self.end_value = value;
        return self;
    }

    pub fn output(self: *Trim, path: []const u8) *Trim {
        self.output_path = path;
        return self;
    }

    pub fn overwrite(self: *Trim, enabled: bool) *Trim {
        self.overwrite_existing = enabled;
        return self;
    }

    pub fn validate(self: *const Trim) ValidationError!void {
        try common.requireNonEmptyInput(self.input_path);
        const output_path = self.output_path orelse return error.MissingOutputPath;
        if (output_path.len == 0) return error.EmptyOutputPath;
    }

    pub fn build(self: *const Trim, allocator: std.mem.Allocator, config: ProcessConfig) !Command {
        try self.validate();
        _ = allocator;
        _ = config;
        return error.NotImplemented;
    }

    pub fn run(self: *Trim, allocator: std.mem.Allocator, io: std.Io) !void {
        const runtime = ProcessRuntime.init(io, .{});
        return self.runWith(allocator, runtime);
    }

    pub fn runWith(self: *Trim, allocator: std.mem.Allocator, runtime: ProcessRuntime) !void {
        _ = self;
        _ = allocator;
        _ = runtime;
        return error.NotImplemented;
    }
};
