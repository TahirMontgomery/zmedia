const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("ffmpeg_c");
const formats = @import("../formats/root.zig");
const time = @import("../time.zig");

const PixelFormat = formats.PixelFormat;
const SampleFormat = formats.SampleFormat;
const ChannelLayout = formats.ChannelLayout;
const Timestamp = time.Timestamp;
const Rational = formats.Rational;

pub const Plane = struct {
    data: []const u8,
    line_size: usize,
};

pub const FrameStorage = union(enum) {
    /// Frame memory owned by an AVFrame; valid until `deinit`.
    borrowed_avframe: *c.AVFrame,
    /// Contiguous owned sample buffer for converted audio.
    owned_bytes: []u8,
};

/// Decoded video frame suitable for GPU upload.
///
/// Lifetime: after `deinit`, plane pointers are invalid.
/// See docs/FRAME_LIFETIME.md.
pub const VideoFrame = struct {
    format: PixelFormat,
    width: u32,
    height: u32,
    timestamp: Timestamp,
    planes: []Plane,
    storage: FrameStorage,
    allocator: Allocator,

    pub fn deinit(self: *VideoFrame) void {
        switch (self.storage) {
            .borrowed_avframe => |frame| {
                var tmp: [*c]c.AVFrame = frame;
                c.av_frame_free(&tmp);
            },
            .owned_bytes => |bytes| {
                self.allocator.free(bytes);
            },
        }
        self.allocator.free(self.planes);
        self.* = undefined;
    }
};

pub const AudioFrame = struct {
    format: SampleFormat,
    sample_rate: u32,
    channel_layout: ChannelLayout,
    timestamp: Timestamp,
    sample_count: u32,
    data: []const u8,
    storage: FrameStorage,
    allocator: Allocator,

    pub fn deinit(self: *AudioFrame) void {
        switch (self.storage) {
            .borrowed_avframe => |frame| {
                var tmp: [*c]c.AVFrame = frame;
                c.av_frame_free(&tmp);
            },
            .owned_bytes => |bytes| {
                self.allocator.free(bytes);
            },
        }
        self.* = undefined;
    }
};

pub fn videoFromAv(
    allocator: Allocator,
    frame: *c.AVFrame,
    time_base: Rational,
) !VideoFrame {
    const width: u32 = @intCast(frame.width);
    const height: u32 = @intCast(frame.height);
    const pix = @import("input.zig").pixelFromAv(frame.format);
    const pts = frame.best_effort_timestamp;

    const plane_count: usize = @intCast(@max(c.av_pix_fmt_count_planes(frame.format), 1));
    var planes = try allocator.alloc(Plane, plane_count);
    errdefer allocator.free(planes);

    var i: usize = 0;
    while (i < plane_count) : (i += 1) {
        const line_size: usize = @intCast(@max(frame.linesize[i], 0));
        const plane_height: usize = if (i == 0) height else @max(height / 2, 1);
        const len = line_size * plane_height;
        const ptr = frame.data[i];
        planes[i] = .{
            .data = if (ptr != null and len > 0) ptr[0..len] else &.{},
            .line_size = line_size,
        };
    }

    return .{
        .format = pix,
        .width = width,
        .height = height,
        .timestamp = Timestamp.fromPts(pts, time_base),
        .planes = planes,
        .storage = .{ .borrowed_avframe = frame },
        .allocator = allocator,
    };
}

pub fn audioFromAv(
    allocator: Allocator,
    frame: *c.AVFrame,
    time_base: Rational,
) !AudioFrame {
    const sample_fmt = @import("input.zig").sampleFromAv(frame.format);
    const channels: u8 = @intCast(frame.ch_layout.nb_channels);
    const sample_count: u32 = @intCast(frame.nb_samples);
    const sample_rate: u32 = @intCast(frame.sample_rate);
    const pts = frame.best_effort_timestamp;
    const bytes_per_sample: usize = @intCast(@max(c.av_get_bytes_per_sample(frame.format), 0));
    const planar = c.av_sample_fmt_is_planar(frame.format) != 0;
    const total_bytes: usize = bytes_per_sample * @as(usize, sample_count) * @as(usize, channels);

    const owned = try allocator.alloc(u8, total_bytes);
    errdefer allocator.free(owned);

    if (planar) {
        var offset: usize = 0;
        var ch: usize = 0;
        while (ch < channels) : (ch += 1) {
            const plane_len = bytes_per_sample * sample_count;
            const src = frame.data[ch];
            if (src != null) {
                @memcpy(owned[offset..][0..plane_len], src[0..plane_len]);
            } else {
                @memset(owned[offset..][0..plane_len], 0);
            }
            offset += plane_len;
        }
    } else if (total_bytes > 0) {
        const src = frame.data[0];
        if (src != null) {
            @memcpy(owned[0..total_bytes], src[0..total_bytes]);
        }
    }

    var tmp: [*c]c.AVFrame = frame;
    c.av_frame_free(&tmp);

    return .{
        .format = sample_fmt,
        .sample_rate = sample_rate,
        .channel_layout = switch (channels) {
            1 => .mono,
            2 => .stereo,
            6 => .surround_5_1,
            8 => .surround_7_1,
            else => .unknown,
        },
        .timestamp = Timestamp.fromPts(pts, time_base),
        .sample_count = sample_count,
        .data = owned,
        .storage = .{ .owned_bytes = owned },
        .allocator = allocator,
    };
}
