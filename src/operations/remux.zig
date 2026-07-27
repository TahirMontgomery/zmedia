//! Stub: process-backed remux / container copy (e.g. MP4 faststart).
//! Implement when Ember needs offline remux. See docs/PROCESS_OPS_BACKLOG.md.
const std = @import("std");
const command_mod = @import("../process/command.zig");
const common = @import("common.zig");
const runtime_mod = @import("../process/runtime.zig");
const validation = @import("../validation.zig");

const Command = command_mod.Command;
const ProcessRuntime = runtime_mod.ProcessRuntime;
const ProcessConfig = runtime_mod.ProcessConfig;
const ValidationError = validation.ValidationError;

pub const Remux = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,
    overwrite_existing: bool = false,

    pub fn init(input_path: []const u8) Remux {
        return .{ .input_path = input_path };
    }

    pub fn output(self: *Remux, path: []const u8) *Remux {
        self.output_path = path;
        return self;
    }

    pub fn overwrite(self: *Remux, enabled: bool) *Remux {
        self.overwrite_existing = enabled;
        return self;
    }

    pub fn validate(self: *const Remux) ValidationError!void {
        try common.requireNonEmptyInput(self.input_path);
        const output_path = self.output_path orelse return error.MissingOutputPath;
        if (output_path.len == 0) return error.EmptyOutputPath;
    }

    pub fn build(self: *const Remux, allocator: std.mem.Allocator, config: ProcessConfig) !Command {
        try self.validate();
        _ = allocator;
        _ = config;
        return error.NotImplemented;
    }

    pub fn run(self: *Remux, allocator: std.mem.Allocator, io: std.Io) !void {
        const runtime = ProcessRuntime.init(io, .{});
        return self.runWith(allocator, runtime);
    }

    pub fn runWith(self: *Remux, allocator: std.mem.Allocator, runtime: ProcessRuntime) !void {
        _ = self;
        _ = allocator;
        _ = runtime;
        return error.NotImplemented;
    }
};
