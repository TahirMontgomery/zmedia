const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const command_mod = @import("command.zig");
const executor_mod = @import("executor.zig");

const Command = command_mod.Command;
const RunResult = executor_mod.RunResult;

pub const RuntimeConfig = struct {
    ffmpeg_path: []const u8 = "ffmpeg",
    ffprobe_path: []const u8 = "ffprobe",
    /// ffmpeg typically writes media to files, not stdout.
    capture_stdout: bool = false,
    /// Keep stderr so failures remain diagnosable.
    capture_stderr: bool = true,
};

pub const Runtime = struct {
    io: Io,
    config: RuntimeConfig,

    pub fn init(io: Io, config: RuntimeConfig) Runtime {
        return .{
            .io = io,
            .config = config,
        };
    }

    pub fn run(
        self: Runtime,
        allocator: Allocator,
        command: *const Command,
    ) !RunResult {
        return executor_mod.run(allocator, self.io, self.config, command);
    }
};
