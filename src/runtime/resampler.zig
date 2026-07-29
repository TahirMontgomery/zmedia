const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("ffmpeg_c");
const errors = @import("../internal/errors.zig");
const formats = @import("../formats/root.zig");
const frame_mod = @import("frame.zig");
const time = @import("../time.zig");

const MediaError = errors.MediaError;
const SampleFormat = formats.SampleFormat;
const ChannelLayout = formats.ChannelLayout;
const AudioFrame = frame_mod.AudioFrame;
const Timestamp = time.Timestamp;

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

pub const ConvertIntoResult = struct {
    sample_count: u32,
    /// Bytes written into `out` (tightly packed for the configured layout/format).
    bytes_written: usize,
};

/// Reusable audio resampler (libswresample). Mixing stays in Ember.
///
/// Single-threaded. Call `flush` / `flushInto` after the last input (EOS or Stop)
/// to drain delayed samples. Flushed frames use the **last input PTS**.
pub const AudioResampler = struct {
    swr: ?*c.SwrContext,
    out_rate: u32,
    out_format: SampleFormat,
    out_layout: ChannelLayout,
    in_rate: u32,
    last_timestamp: Timestamp = .{ .microseconds = 0 },
    drained: bool = false,

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
            .in_rate = in_rate,
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

    /// Upper bound on packed output bytes for `sample_count` output samples.
    pub fn byteLengthForSamples(self: *const AudioResampler, sample_count: u32) usize {
        const out_channels: usize = @intCast(channelCount(self.out_layout));
        const bytes_per_sample: usize = @intCast(@max(c.av_get_bytes_per_sample(avSampleFormat(self.out_format)), 0));
        return @as(usize, sample_count) * out_channels * bytes_per_sample;
    }

    pub fn convert(
        self: *AudioResampler,
        allocator: Allocator,
        input: *const AudioFrame,
    ) MediaError!AudioFrame {
        const needed_samples = try self.estimateOutSamples(input.sample_count);
        const out_bytes = self.byteLengthForSamples(@intCast(needed_samples));
        const owned = allocator.alloc(u8, out_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(owned);

        const result = try self.convertInto(input, owned);
        const trimmed = allocator.realloc(owned, result.bytes_written) catch return error.OutOfMemory;

        return .{
            .format = self.out_format,
            .sample_rate = self.out_rate,
            .channel_layout = self.out_layout,
            .timestamp = input.timestamp,
            .sample_count = result.sample_count,
            .data = trimmed,
            .storage = .{ .owned_bytes = trimmed },
            .allocator = allocator,
        };
    }

    pub fn convertInto(
        self: *AudioResampler,
        input: *const AudioFrame,
        out: []u8,
    ) MediaError!ConvertIntoResult {
        const swr = self.swr orelse return error.InvalidArgument;
        self.drained = false;
        self.last_timestamp = input.timestamp;

        const needed_samples = try self.estimateOutSamples(input.sample_count);
        const needed_bytes = self.byteLengthForSamples(@intCast(needed_samples));
        if (out.len < needed_bytes) return error.BufferTooSmall;

        var out_planes: [1]?[*]u8 = .{out.ptr};
        var in_planes: [1]?[*]const u8 = .{input.data.ptr};

        const converted = c.swr_convert(
            swr,
            @ptrCast(&out_planes),
            needed_samples,
            @ptrCast(&in_planes),
            @intCast(input.sample_count),
        );
        if (converted < 0) return errors.fromAvError(converted);

        const bytes_written = self.byteLengthForSamples(@intCast(converted));
        return .{
            .sample_count = @intCast(converted),
            .bytes_written = bytes_written,
        };
    }

    /// Drain delayed samples after the last input. Returns null when empty.
    /// Call repeatedly until null. Timestamp = last input PTS.
    pub fn flush(self: *AudioResampler, allocator: Allocator) MediaError!?AudioFrame {
        if (self.drained) return null;

        const delay_samples = self.pendingOutSamples();
        if (delay_samples <= 0) {
            self.drained = true;
            return null;
        }

        const out_bytes = self.byteLengthForSamples(@intCast(delay_samples));
        const owned = allocator.alloc(u8, out_bytes) catch return error.OutOfMemory;
        errdefer allocator.free(owned);

        const result = try self.flushInto(owned);
        if (result.sample_count == 0) {
            allocator.free(owned);
            return null;
        }

        const trimmed = allocator.realloc(owned, result.bytes_written) catch return error.OutOfMemory;
        return .{
            .format = self.out_format,
            .sample_rate = self.out_rate,
            .channel_layout = self.out_layout,
            .timestamp = self.last_timestamp,
            .sample_count = result.sample_count,
            .data = trimmed,
            .storage = .{ .owned_bytes = trimmed },
            .allocator = allocator,
        };
    }

    pub fn flushInto(self: *AudioResampler, out: []u8) MediaError!ConvertIntoResult {
        const swr = self.swr orelse return error.InvalidArgument;
        if (self.drained) {
            return .{ .sample_count = 0, .bytes_written = 0 };
        }

        const delay_samples = self.pendingOutSamples();
        if (delay_samples <= 0) {
            self.drained = true;
            return .{ .sample_count = 0, .bytes_written = 0 };
        }

        const needed_bytes = self.byteLengthForSamples(@intCast(delay_samples));
        if (out.len < needed_bytes) return error.BufferTooSmall;

        var out_planes: [1]?[*]u8 = .{out.ptr};
        const converted = c.swr_convert(
            swr,
            @ptrCast(&out_planes),
            delay_samples,
            null,
            0,
        );
        if (converted < 0) return errors.fromAvError(converted);
        if (converted == 0) {
            self.drained = true;
            return .{ .sample_count = 0, .bytes_written = 0 };
        }

        // If delay remains, caller may flush again; otherwise mark drained.
        if (self.pendingOutSamples() <= 0) {
            self.drained = true;
        }

        return .{
            .sample_count = @intCast(converted),
            .bytes_written = self.byteLengthForSamples(@intCast(converted)),
        };
    }

    fn estimateOutSamples(self: *const AudioResampler, in_samples: u32) MediaError!i32 {
        const swr = self.swr orelse return error.InvalidArgument;
        const delay = c.swr_get_delay(swr, @intCast(self.in_rate));
        const out_samples: i32 = @intCast(c.av_rescale_rnd(
            delay + @as(i64, @intCast(in_samples)),
            @intCast(self.out_rate),
            @intCast(self.in_rate),
            c.AV_ROUND_UP,
        ));
        if (out_samples <= 0) return error.InvalidData;
        return out_samples;
    }

    fn pendingOutSamples(self: *const AudioResampler) i32 {
        const swr = self.swr orelse return 0;
        const delay = c.swr_get_delay(swr, @intCast(self.out_rate));
        if (delay <= 0) return 0;
        return @intCast(delay);
    }
};
