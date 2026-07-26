const std = @import("std");
const Io = std.Io;

pub const RuntimeConfig = struct {
    ffmpeg_path: []const u8 = "ffmpeg",
    ffprobe_path: []const u8 = "ffprobe",
    capture_stdout: bool = true,
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
};
