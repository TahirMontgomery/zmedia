const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const audio = @import("../audio.zig");
const command_mod = @import("../command.zig");
const executor_mod = @import("../executor.zig");
const runtime_mod = @import("../runtime.zig");
const validation = @import("../validation.zig");

const AudioBitrate = audio.AudioBitrate;
const AudioChannels = audio.AudioChannels;
const AudioCodec = audio.AudioCodec;
const SampleRate = audio.SampleRate;
const Command = command_mod.Command;
const Executor = executor_mod.Executor;
const RunResult = executor_mod.RunResult;
const RuntimeConfig = runtime_mod.RuntimeConfig;
const ValidationError = validation.ValidationError;

pub const AudioExtraction = struct {
    input_path: []const u8,
    output_path: ?[]const u8 = null,

    codec_value: AudioCodec = .copy,
    bitrate_value: ?AudioBitrate = null,
    channels_value: ?AudioChannels = null,
    sample_rate_value: ?SampleRate = null,

    overwrite_existing: bool = false,

    pub fn init(input_path: []const u8) AudioExtraction {
        return .{
            .input_path = input_path,
        };
    }

    pub fn codec(self: *AudioExtraction, value: AudioCodec) *AudioExtraction {
        self.codec_value = value;
        return self;
    }

    pub fn bitrate(self: *AudioExtraction, value: AudioBitrate) *AudioExtraction {
        self.bitrate_value = value;
        return self;
    }

    pub fn channels(self: *AudioExtraction, value: AudioChannels) *AudioExtraction {
        self.channels_value = value;
        return self;
    }

    pub fn sampleRate(self: *AudioExtraction, value: SampleRate) *AudioExtraction {
        self.sample_rate_value = value;
        return self;
    }

    pub fn overwrite(self: *AudioExtraction, enabled: bool) *AudioExtraction {
        self.overwrite_existing = enabled;
        return self;
    }

    pub fn output(self: *AudioExtraction, path: []const u8) *AudioExtraction {
        self.output_path = path;
        return self;
    }

    pub fn validate(self: *const AudioExtraction) ValidationError!void {
        if (self.input_path.len == 0) {
            return error.EmptyInputPath;
        }

        const output_path = self.output_path orelse {
            return error.MissingOutputPath;
        };

        if (output_path.len == 0) {
            return error.EmptyOutputPath;
        }

        if (std.mem.eql(u8, self.input_path, output_path)) {
            return error.InputEqualsOutput;
        }

        if (self.bitrate_value) |bitrate_value| {
            if (!bitrate_value.isValid()) {
                return error.InvalidBitrate;
            }
        }

        if (self.sample_rate_value) |sample_rate_value| {
            if (!sample_rate_value.isValid()) {
                return error.InvalidSampleRate;
            }
        }

        if (self.codec_value == .copy) {
            if (self.bitrate_value != null) {
                return error.BitrateNotAllowedWithCopy;
            }
            if (self.sample_rate_value != null) {
                return error.SampleRateNotAllowedWithCopy;
            }
            if (self.channels_value != null) {
                return error.ChannelsNotAllowedWithCopy;
            }
        }
    }

    pub fn build(
        self: *const AudioExtraction,
        allocator: Allocator,
        config: RuntimeConfig,
    ) !Command {
        try self.validate();

        var command = Command.init(allocator, config.ffmpeg_path);
        errdefer command.deinit();

        if (self.overwrite_existing) {
            try command.append("-y");
        } else {
            try command.append("-n");
        }

        try command.append("-i");
        try command.append(self.input_path);
        try command.append("-vn");
        try command.append("-c:a");
        try command.append(self.codec_value.ffmpegName());

        if (self.bitrate_value) |bitrate_value| {
            const value = try bitrate_value.format(allocator);
            defer allocator.free(value);
            try command.append("-b:a");
            try command.append(value);
        }

        if (self.channels_value) |channels_value| {
            try command.append("-ac");
            try command.appendFormat("{d}", .{channels_value.count()});
        }

        if (self.sample_rate_value) |sample_rate_value| {
            try command.append("-ar");
            try command.appendFormat("{d}", .{sample_rate_value.hz});
        }

        try command.append(self.output_path.?);
        return command;
    }

    pub fn run(
        self: *const AudioExtraction,
        allocator: Allocator,
        io: Io,
    ) !RunResult {
        return self.runWithConfig(allocator, io, .{});
    }

    pub fn runWithConfig(
        self: *const AudioExtraction,
        allocator: Allocator,
        io: Io,
        config: RuntimeConfig,
    ) !RunResult {
        var built = try self.build(allocator, config);
        defer built.deinit();
        return Executor.init(config).run(allocator, io, &built);
    }

    pub fn printCommand(
        self: *const AudioExtraction,
        allocator: Allocator,
        writer: *Io.Writer,
        config: RuntimeConfig,
    ) !void {
        var built = try self.build(allocator, config);
        defer built.deinit();
        try built.render(writer);
    }
};
