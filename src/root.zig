//! ZMedia — typed FFmpeg wrapper for Zig.
const std = @import("std");

pub const audio = @import("audio.zig");
pub const image = @import("image.zig");
pub const time = @import("time.zig");
pub const command = @import("command.zig");
pub const executor = @import("executor.zig");
pub const runtime = @import("runtime.zig");
pub const validation = @import("validation.zig");
pub const probe_mod = @import("probe.zig");

pub const operations = struct {
    pub const common = @import("operations/common.zig");
    pub const audio_extraction = @import("operations/audio_extraction.zig");
    pub const screenshot_extraction = @import("operations/screenshot_extraction.zig");
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

pub const MediaInfo = probe_mod.MediaInfo;
pub const VideoStream = probe_mod.VideoStream;
pub const AudioStream = probe_mod.AudioStream;
pub const Rational = probe_mod.Rational;
pub const InstallationInfo = probe_mod.InstallationInfo;
pub const Tool = probe_mod.Tool;

pub const RunResult = executor.RunResult;
pub const ProcessResult = executor.ProcessResult;
pub const Executor = executor.Executor;
pub const Command = command.Command;
pub const Runtime = runtime.Runtime;
pub const RuntimeConfig = runtime.RuntimeConfig;
pub const ValidationError = validation.ValidationError;

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
    config: RuntimeConfig,
) !MediaInfo {
    return probe_mod.probe(allocator, io, input_path, config);
}

pub fn checkInstallation(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RuntimeConfig,
) !InstallationInfo {
    return probe_mod.checkInstallation(allocator, io, config);
}

test {
    _ = audio;
    _ = image;
    _ = time;
    _ = command;
    _ = executor;
    _ = runtime;
    _ = validation;
    _ = probe_mod;
    _ = operations.common;
    _ = operations.audio_extraction;
    _ = operations.screenshot_extraction;
}
