//! Stub: process-backed video+audio re-encode builder.
//! Implement when Ember needs offline transcode. See docs/PROCESS_OPS_BACKLOG.md.
const std = @import("std");
const command_mod = @import("../process/command.zig");
const common = @import("common.zig");
const runtime_mod = @import("../process/runtime.zig");
const validation = @import("../validation.zig");

const Command = command_mod.Command;
const ProcessRuntime = runtime_mod.ProcessRuntime;
const ProcessConfig = runtime_mod.ProcessConfig;
const ValidationError = validation.ValidationError;

pub const Transcode = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    overwrite_existing: bool = false,

    pub fn init(input_path: []const u8) Transcode {
        return .{ .input_path = input_path };
    }

    pub fn output(self: *Transcode, path: []const u8) *Transcode {
        self.output_path = path;
        return self;
    }

    pub fn overwrite(self: *Transcode, enabled: bool) *Transcode {
        self.overwrite_existing = enabled;
        return self;
    }

    pub fn validate(self: *const Transcode) ValidationError!void {
        try common.requireNonEmptyInput(self.input_path);
        const output_path = self.output_path orelse return error.MissingOutputPath;
        if (output_path.len == 0) return error.EmptyOutputPath;
    }

    pub fn build(self: *const Transcode, allocator: std.mem.Allocator, config: ProcessConfig) !Command {
        try self.validate();
        _ = allocator;
        _ = config;
        return error.NotImplemented;
    }

    pub fn run(self: *Transcode, allocator: std.mem.Allocator, io: std.Io) !void {
        const runtime = ProcessRuntime.init(io, .{});
        return self.runWith(allocator, runtime);
    }

    pub fn runWith(self: *Transcode, allocator: std.mem.Allocator, runtime: ProcessRuntime) !void {
        _ = self;
        _ = allocator;
        _ = runtime;
        return error.NotImplemented;
    }
};
