const std = @import("std");
const Allocator = std.mem.Allocator;

const formats = @import("../formats/root.zig");
const Rational = formats.Rational;

pub const StreamKind = enum {
    video,
    audio,
    subtitle,
    data,
    unknown,
};

pub const StreamInfo = struct {
    index: u32,
    kind: StreamKind,
    codec_name: []u8,
    time_base: Rational,
    width: ?u32 = null,
    height: ?u32 = null,
    pixel_format: ?formats.PixelFormat = null,
    sample_rate: ?u32 = null,
    channels: ?u8 = null,
    channel_layout: ?formats.ChannelLayout = null,
    sample_format: ?formats.SampleFormat = null,

    pub fn deinit(self: *StreamInfo, allocator: Allocator) void {
        allocator.free(self.codec_name);
        self.* = undefined;
    }
};
