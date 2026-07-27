const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const command_mod = @import("command.zig");
const executor_mod = @import("executor.zig");

const Command = command_mod.Command;
const RunResult = executor_mod.RunResult;

/// Configuration for spawning ffmpeg / ffprobe processes.
pub const ProcessConfig = struct {
    ffmpeg_path: []const u8 = "ffmpeg",
    ffprobe_path: []const u8 = "ffprobe",
    /// ffmpeg typically writes media to files, not stdout.
    capture_stdout: bool = false,
    /// Keep stderr so failures remain diagnosable.
    capture_stderr: bool = true,
};

/// Process-backed execution seam (CLI ffmpeg/ffprobe).
/// Library-backed APIs live under `zmedia.runtime` and must not share this name.
pub const ProcessRuntime = struct {
    io: Io,
    config: ProcessConfig,

    pub fn init(io: Io, config: ProcessConfig) ProcessRuntime {
        return .{
            .io = io,
            .config = config,
        };
    }

    pub fn run(
        self: ProcessRuntime,
        allocator: Allocator,
        command: *const Command,
    ) !RunResult {
        return executor_mod.run(allocator, self.io, self.config, command);
    }
};
