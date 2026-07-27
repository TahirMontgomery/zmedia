//! Library-backed FFmpeg runtime APIs (interactive / real-time pipelines).
//! Process-backed CLI ops live under `zmedia.process`.
//!
//! When built with `-Dlink-ffmpeg=false`, these symbols are unavailable.

const std = @import("std");
const build_options = @import("build_options");

comptime {
    if (!build_options.link_ffmpeg) {
        @compileError("zmedia.runtime requires -Dlink-ffmpeg=true (default)");
    }
}

pub const MediaInput = @import("input.zig").MediaInput;
pub const StreamInfo = @import("stream.zig").StreamInfo;
pub const StreamKind = @import("stream.zig").StreamKind;
pub const Packet = @import("packet.zig").Packet;
pub const VideoFrame = @import("frame.zig").VideoFrame;
pub const AudioFrame = @import("frame.zig").AudioFrame;
pub const Plane = @import("frame.zig").Plane;
pub const FrameStorage = @import("frame.zig").FrameStorage;
pub const VideoDecoder = @import("decoder.zig").VideoDecoder;
pub const AudioDecoder = @import("decoder.zig").AudioDecoder;
pub const AudioResampler = @import("resampler.zig").AudioResampler;

/// Linked libavutil version string (never exposes C types).
pub fn ffmpegVersion() []const u8 {
    const c = @import("ffmpeg_c");
    return std.mem.span(c.av_version_info());
}
