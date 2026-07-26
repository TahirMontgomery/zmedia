const std = @import("std");
const Allocator = std.mem.Allocator;

pub const AudioCodec = enum {
    copy,
    aac,
    mp3,
    flac,
    opus,
    pcm_s16le,

    pub fn ffmpegName(self: AudioCodec) []const u8 {
        return switch (self) {
            .copy => "copy",
            .aac => "aac",
            .mp3 => "libmp3lame",
            .flac => "flac",
            .opus => "libopus",
            .pcm_s16le => "pcm_s16le",
        };
    }

    pub fn parse(value: []const u8) ?AudioCodec {
        return std.meta.stringToEnum(AudioCodec, value);
    }
};

pub const AudioBitrate = union(enum) {
    kbps: u32,
    mbps: f32,

    pub fn format(self: AudioBitrate, allocator: Allocator) ![]u8 {
        return switch (self) {
            .kbps => |value| std.fmt.allocPrint(allocator, "{d}k", .{value}),
            .mbps => |value| std.fmt.allocPrint(allocator, "{d:.2}M", .{value}),
        };
    }

    pub fn isValid(self: AudioBitrate) bool {
        return switch (self) {
            .kbps => |value| value > 0,
            .mbps => |value| value > 0,
        };
    }
};

pub const AudioChannels = enum(u8) {
    mono = 1,
    stereo = 2,

    pub fn count(self: AudioChannels) u8 {
        return @intFromEnum(self);
    }
};

pub const SampleRate = union(enum) {
    hz: u32,

    pub const hz_44100: SampleRate = .{ .hz = 44_100 };
    pub const hz_48000: SampleRate = .{ .hz = 48_000 };
    pub const hz_96000: SampleRate = .{ .hz = 96_000 };

    pub fn isValid(self: SampleRate) bool {
        return self.hz > 0;
    }
};
