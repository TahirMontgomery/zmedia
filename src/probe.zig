const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const audio = @import("audio.zig");
const command_mod = @import("command.zig");
const executor_mod = @import("executor.zig");
const runtime_mod = @import("runtime.zig");
const time = @import("time.zig");

const AudioCodec = audio.AudioCodec;
const Command = command_mod.Command;
const Executor = executor_mod.Executor;
const RuntimeConfig = runtime_mod.RuntimeConfig;
const Timestamp = time.Timestamp;

pub const Rational = struct {
    numerator: u32,
    denominator: u32,

    pub fn asFloat(self: Rational) ?f64 {
        if (self.denominator == 0) {
            return null;
        }
        return @as(f64, @floatFromInt(self.numerator)) /
            @as(f64, @floatFromInt(self.denominator));
    }

    pub fn parse(value: []const u8) ?Rational {
        const slash = std.mem.indexOfScalar(u8, value, '/') orelse {
            const number = std.fmt.parseInt(u32, value, 10) catch return null;
            return .{ .numerator = number, .denominator = 1 };
        };

        const numerator = std.fmt.parseInt(u32, value[0..slash], 10) catch return null;
        const denominator = std.fmt.parseInt(u32, value[slash + 1 ..], 10) catch return null;
        return .{ .numerator = numerator, .denominator = denominator };
    }
};

pub const VideoStream = struct {
    index: u32,
    codec_name: []u8,
    width: ?u32,
    height: ?u32,
    frame_rate: ?Rational,
    pixel_format: ?[]u8,

    pub fn deinit(self: *VideoStream, allocator: Allocator) void {
        allocator.free(self.codec_name);
        if (self.pixel_format) |pixel_format| {
            allocator.free(pixel_format);
        }
        self.* = undefined;
    }
};

pub const AudioStream = struct {
    index: u32,
    codec_name: []u8,
    sample_rate: ?u32,
    channels: ?u8,
    channel_layout: ?[]u8,
    known_codec: ?AudioCodec = null,

    pub fn deinit(self: *AudioStream, allocator: Allocator) void {
        allocator.free(self.codec_name);
        if (self.channel_layout) |channel_layout| {
            allocator.free(channel_layout);
        }
        self.* = undefined;
    }
};

pub const MediaInfo = struct {
    path: []u8,
    format_name: ?[]u8,
    duration: ?Timestamp,
    bitrate_bps: ?u64,

    video_streams: []VideoStream,
    audio_streams: []AudioStream,

    pub fn deinit(self: *MediaInfo, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.format_name) |format_name| {
            allocator.free(format_name);
        }
        for (self.video_streams) |*stream| {
            stream.deinit(allocator);
        }
        allocator.free(self.video_streams);
        for (self.audio_streams) |*stream| {
            stream.deinit(allocator);
        }
        allocator.free(self.audio_streams);
        self.* = undefined;
    }
};

const ProbeFormatJson = struct {
    filename: ?[]const u8 = null,
    format_name: ?[]const u8 = null,
    duration: ?[]const u8 = null,
    bit_rate: ?[]const u8 = null,
};

const ProbeStreamJson = struct {
    index: u32,
    codec_type: ?[]const u8 = null,
    codec_name: ?[]const u8 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    r_frame_rate: ?[]const u8 = null,
    pix_fmt: ?[]const u8 = null,
    sample_rate: ?[]const u8 = null,
    channels: ?u8 = null,
    channel_layout: ?[]const u8 = null,
};

const ProbeJson = struct {
    format: ?ProbeFormatJson = null,
    streams: []ProbeStreamJson = &.{},
};

pub fn probe(
    allocator: Allocator,
    io: Io,
    input_path: []const u8,
    config: RuntimeConfig,
) !MediaInfo {
    if (input_path.len == 0) {
        return error.EmptyInputPath;
    }

    var command = Command.init(allocator, config.ffprobe_path);
    defer command.deinit();

    try command.append("-v");
    try command.append("error");
    try command.append("-show_format");
    try command.append("-show_streams");
    try command.append("-of");
    try command.append("json");
    try command.append(input_path);

    var run_result = try Executor.init(config).run(allocator, io, &command);
    defer run_result.deinit(allocator);

    const process = run_result.process();
    if (!process.succeeded()) {
        return error.FfprobeProcessFailed;
    }

    return try parseProbeJson(allocator, input_path, process.stdout);
}

pub fn parseProbeJson(
    allocator: Allocator,
    input_path: []const u8,
    json_text: []const u8,
) !MediaInfo {
    var parsed = try std.json.parseFromSlice(ProbeJson, allocator, json_text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const value = parsed.value;

    var video_list: std.ArrayList(VideoStream) = .empty;
    errdefer {
        for (video_list.items) |*stream| {
            stream.deinit(allocator);
        }
        video_list.deinit(allocator);
    }

    var audio_list: std.ArrayList(AudioStream) = .empty;
    errdefer {
        for (audio_list.items) |*stream| {
            stream.deinit(allocator);
        }
        audio_list.deinit(allocator);
    }

    for (value.streams) |stream| {
        const codec_type = stream.codec_type orelse continue;
        const codec_name = stream.codec_name orelse "unknown";

        if (std.mem.eql(u8, codec_type, "video")) {
            try video_list.append(allocator, .{
                .index = stream.index,
                .codec_name = try allocator.dupe(u8, codec_name),
                .width = stream.width,
                .height = stream.height,
                .frame_rate = if (stream.r_frame_rate) |rate|
                    Rational.parse(rate)
                else
                    null,
                .pixel_format = if (stream.pix_fmt) |pix_fmt|
                    try allocator.dupe(u8, pix_fmt)
                else
                    null,
            });
        } else if (std.mem.eql(u8, codec_type, "audio")) {
            try audio_list.append(allocator, .{
                .index = stream.index,
                .codec_name = try allocator.dupe(u8, codec_name),
                .sample_rate = if (stream.sample_rate) |rate|
                    std.fmt.parseInt(u32, rate, 10) catch null
                else
                    null,
                .channels = stream.channels,
                .channel_layout = if (stream.channel_layout) |layout|
                    try allocator.dupe(u8, layout)
                else
                    null,
                .known_codec = AudioCodec.parse(codec_name),
            });
        }
    }

    var format_name: ?[]u8 = null;
    errdefer if (format_name) |name| allocator.free(name);

    var duration: ?Timestamp = null;
    var bitrate_bps: ?u64 = null;

    if (value.format) |format| {
        if (format.format_name) |name| {
            format_name = try allocator.dupe(u8, name);
        }
        if (format.duration) |duration_text| {
            const seconds = std.fmt.parseFloat(f64, duration_text) catch null;
            if (seconds) |value_seconds| {
                duration = Timestamp.fromFloatSeconds(value_seconds);
            }
        }
        if (format.bit_rate) |bitrate_text| {
            bitrate_bps = std.fmt.parseInt(u64, bitrate_text, 10) catch null;
        }
    }

    return .{
        .path = try allocator.dupe(u8, input_path),
        .format_name = format_name,
        .duration = duration,
        .bitrate_bps = bitrate_bps,
        .video_streams = try video_list.toOwnedSlice(allocator),
        .audio_streams = try audio_list.toOwnedSlice(allocator),
    };
}

pub const InstallationInfo = struct {
    ffmpeg_available: bool,
    ffprobe_available: bool,
    ffmpeg_version: ?[]u8,
    ffprobe_version: ?[]u8,

    pub fn deinit(self: *InstallationInfo, allocator: Allocator) void {
        if (self.ffmpeg_version) |version| {
            allocator.free(version);
        }
        if (self.ffprobe_version) |version| {
            allocator.free(version);
        }
        self.* = undefined;
    }
};

pub fn checkInstallation(
    allocator: Allocator,
    io: Io,
    config: RuntimeConfig,
) !InstallationInfo {
    var info = InstallationInfo{
        .ffmpeg_available = false,
        .ffprobe_available = false,
        .ffmpeg_version = null,
        .ffprobe_version = null,
    };
    errdefer info.deinit(allocator);

    info.ffmpeg_version = try probeBinaryVersion(allocator, io, config.ffmpeg_path);
    info.ffmpeg_available = info.ffmpeg_version != null;

    info.ffprobe_version = try probeBinaryVersion(allocator, io, config.ffprobe_path);
    info.ffprobe_available = info.ffprobe_version != null;

    return info;
}

fn probeBinaryVersion(
    allocator: Allocator,
    io: Io,
    binary_path: []const u8,
) !?[]u8 {
    var command = Command.init(allocator, binary_path);
    defer command.deinit();
    try command.append("-version");

    var run_result = Executor.init(.{}).run(allocator, io, &command) catch {
        return null;
    };
    defer run_result.deinit(allocator);

    const process = run_result.process();
    if (!process.succeeded()) {
        return null;
    }

    const source = if (process.stdout.len > 0) process.stdout else process.stderr;
    const line_end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
    const line = std.mem.trim(u8, source[0..line_end], " \t\r");
    if (line.len == 0) {
        return null;
    }
    return try allocator.dupe(u8, line);
}
