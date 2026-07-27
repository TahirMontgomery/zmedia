//! ZMedia — typed FFmpeg wrapper for Zig.
//!
//! Dual workload model:
//! - Process-backed ops (ffmpeg/ffprobe CLI) for offline jobs
//! - Library-backed runtime APIs (libav*) for interactive pipelines
const std = @import("std");

pub const audio = @import("audio.zig");
pub const image = @import("image.zig");
pub const time = @import("time.zig");
pub const validation = @import("validation.zig");
pub const probe_mod = @import("probe.zig");

pub const process = struct {
    pub const command = @import("process/command.zig");
    pub const executor = @import("process/executor.zig");
    pub const runtime = @import("process/runtime.zig");
};

pub const formats = @import("formats/root.zig");
pub const runtime = @import("runtime/root.zig");

pub const operations = struct {
    pub const common = @import("operations/common.zig");
    pub const audio_extraction = @import("operations/audio_extraction.zig");
    pub const screenshot_extraction = @import("operations/screenshot_extraction.zig");
    pub const transcode = @import("operations/transcode.zig");
    pub const trim = @import("operations/trim.zig");
    pub const remux = @import("operations/remux.zig");
};

pub const AudioCodec = audio.AudioCodec;
pub const AudioBitrate = audio.AudioBitrate;
pub const AudioChannels = audio.AudioChannels;
pub const SampleRate = audio.SampleRate;

pub const ImageFormat = image.ImageFormat;
pub const ImageQuality = image.ImageQuality;

pub const Timestamp = time.Timestamp;

pub const AudioExtraction = operations.audio_extraction.AudioExtraction;
pub const ScreenshotExtraction = operations.screenshot_extraction.ScreenshotExtraction;
pub const ScreenshotResult = operations.screenshot_extraction.ScreenshotResult;
pub const ScreenshotBatchResult = operations.screenshot_extraction.ScreenshotBatchResult;
pub const Transcode = operations.transcode.Transcode;
pub const Trim = operations.trim.Trim;
pub const Remux = operations.remux.Remux;

pub const MediaInfo = probe_mod.MediaInfo;
pub const VideoStream = probe_mod.VideoStream;
pub const AudioStream = probe_mod.AudioStream;
pub const Rational = formats.Rational;
pub const InstallationInfo = probe_mod.InstallationInfo;
pub const Tool = probe_mod.Tool;

pub const RunResult = process.executor.RunResult;
pub const ProcessResult = process.executor.ProcessResult;
pub const Executor = process.executor.Executor;
pub const Command = process.command.Command;
pub const ProcessRuntime = process.runtime.ProcessRuntime;
pub const ProcessConfig = process.runtime.ProcessConfig;

pub const MediaInput = runtime.MediaInput;
pub const StreamInfo = runtime.StreamInfo;
pub const StreamKind = runtime.StreamKind;
pub const Packet = runtime.Packet;
pub const VideoFrame = runtime.VideoFrame;
pub const AudioFrame = runtime.AudioFrame;
pub const VideoDecoder = runtime.VideoDecoder;
pub const AudioDecoder = runtime.AudioDecoder;
pub const AudioResampler = runtime.AudioResampler;
pub const PixelFormat = formats.PixelFormat;
pub const SampleFormat = formats.SampleFormat;
pub const ChannelLayout = formats.ChannelLayout;
pub const MediaError = @import("internal/errors.zig").MediaError;

pub fn audioExtraction(input_path: []const u8) AudioExtraction {
    return AudioExtraction.init(input_path);
}

pub fn screenshotExtraction(input_path: []const u8) ScreenshotExtraction {
    return ScreenshotExtraction.init(input_path);
}

pub fn timestampSeconds(value: u64) Timestamp {
    return Timestamp.fromSeconds(value);
}

pub fn probe(
    allocator: std.mem.Allocator,
    io: std.Io,
    input_path: []const u8,
    config: ProcessConfig,
) !MediaInfo {
    return probe_mod.probe(allocator, io, input_path, config);
}

pub fn checkInstallation(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: ProcessConfig,
) !InstallationInfo {
    return probe_mod.checkInstallation(allocator, io, config);
}

test {
    _ = audio;
    _ = image;
    _ = time;
    _ = validation;
    _ = probe_mod;
    _ = process.command;
    _ = process.executor;
    _ = process.runtime;
    _ = formats;
    _ = runtime;
    _ = operations.common;
    _ = operations.audio_extraction;
    _ = operations.screenshot_extraction;
    _ = operations.transcode;
    _ = operations.trim;
    _ = operations.remux;
}
