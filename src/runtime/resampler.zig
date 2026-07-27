const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("ffmpeg_c");
const errors = @import("../internal/errors.zig");
const formats = @import("../formats/root.zig");
const frame_mod = @import("frame.zig");

const MediaError = errors.MediaError;
const SampleFormat = formats.SampleFormat;
const ChannelLayout = formats.ChannelLayout;
const AudioFrame = frame_mod.AudioFrame;

fn avSampleFormat(fmt: SampleFormat) c.AVSampleFormat {
    return switch (fmt) {
        .u8 => c.AV_SAMPLE_FMT_U8,
        .s16 => c.AV_SAMPLE_FMT_S16,
        .s32 => c.AV_SAMPLE_FMT_S32,
        .flt => c.AV_SAMPLE_FMT_FLT,
        .dbl => c.AV_SAMPLE_FMT_DBL,
        .u8p => c.AV_SAMPLE_FMT_U8P,
        .s16p => c.AV_SAMPLE_FMT_S16P,
        .s32p => c.AV_SAMPLE_FMT_S32P,
        .fltp => c.AV_SAMPLE_FMT_FLTP,
        .dblp => c.AV_SAMPLE_FMT_DBLP,
        .unknown => c.AV_SAMPLE_FMT_NONE,
    };
}

fn channelCount(layout: ChannelLayout) c_int {
    return switch (layout) {
        .mono => 1,
        .stereo => 2,
        .surround_5_1 => 6,
        .surround_7_1 => 8,
        .unknown => 0,
    };
}

/// Reusable audio resampler (libswresample). Mixing stays in Ember.
pub const AudioResampler = struct {
    swr: ?*c.SwrContext,
    out_rate: u32,
    out_format: SampleFormat,
    out_layout: ChannelLayout,

    pub fn init(
        out_rate: u32,
        out_format: SampleFormat,
        out_layout: ChannelLayout,
        in_rate: u32,
        in_format: SampleFormat,
        in_layout: ChannelLayout,
    ) MediaError!AudioResampler {
        var out_ch: c.AVChannelLayout = undefined;
        var in_ch: c.AVChannelLayout = undefined;
        _ = c.av_channel_layout_default(&out_ch, channelCount(out_layout));
        _ = c.av_channel_layout_default(&in_ch, channelCount(in_layout));

        var swr: ?*c.SwrContext = null;
        const alloc_rc = c.swr_alloc_set_opts2(
            &swr,
            &out_ch,
            avSampleFormat(out_format),
            @intCast(out_rate),
            &in_ch,
            avSampleFormat(in_format),
            @intCast(in_rate),
            0,
            null,
        );
        if (alloc_rc < 0) return errors.fromAvError(alloc_rc);
        errdefer c.swr_free(&swr);

        const init_rc = c.swr_init(swr);
        if (init_rc < 0) return errors.fromAvError(init_rc);

        return .{
            .swr = swr,
            .out_rate = out_rate,
            .out_format = out_format,
            .out_layout = out_layout,
        };
    }

    pub fn deinit(self: *AudioResampler) void {
        if (self.swr) |swr| {
            var tmp: ?*c.SwrContext = swr;
            c.swr_free(&tmp);
            self.swr = null;
        }
        self.* = undefined;
    }

    pub fn convert(
        self: *AudioResampler,
        allocator: Allocator,
        input: *const AudioFrame,
    ) MediaError!AudioFrame {
        const swr = self.swr orelse return error.InvalidArgument;
        const out_channels = channelCount(self.out_layout);
        const bytes_per_sample: usize = @intCast(@max(c.av_get_bytes_per_sample(avSampleFormat(self.out_format)), 0));

        const delay = c.swr_get_delay(swr, @intCast(input.sample_rate));
        const out_samples: i32 = @intCast(c.av_rescale_rnd(
            delay + @as(i64, @intCast(input.sample_count)),
            @intCast(self.out_rate),
            @intCast(input.sample_rate),
            c.AV_ROUND_UP,
        ));
        if (out_samples <= 0) return error.InvalidData;

        const out_bytes: usize = @as(usize, @intCast(out_samples)) * @as(usize, @intCast(out_channels)) * bytes_per_sample;
        const owned = allocator.alloc(u8, out_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(owned);

        var out_planes: [1]?[*]u8 = .{owned.ptr};
        var in_planes: [1]?[*]const u8 = .{input.data.ptr};

        const converted = c.swr_convert(
            swr,
            @ptrCast(&out_planes),
            out_samples,
            @ptrCast(&in_planes),
            @intCast(input.sample_count),
        );
        if (converted < 0) return errors.fromAvError(converted);

        const actual_bytes = @as(usize, @intCast(converted)) * @as(usize, @intCast(out_channels)) * bytes_per_sample;
        const trimmed = allocator.realloc(owned, actual_bytes) catch return error.OutOfMemory;

        return .{
            .format = self.out_format,
            .sample_rate = self.out_rate,
            .channel_layout = self.out_layout,
            .timestamp = input.timestamp,
            .sample_count = @intCast(converted),
            .data = trimmed,
            .storage = .{ .owned_bytes = trimmed },
            .allocator = allocator,
        };
    }
};
