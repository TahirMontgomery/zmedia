const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("ffmpeg_c");
const errors = @import("../internal/errors.zig");
const formats = @import("../formats/root.zig");
const stream_mod = @import("stream.zig");

const MediaError = errors.MediaError;
const StreamInfo = stream_mod.StreamInfo;
const StreamKind = stream_mod.StreamKind;

/// Open media file via libavformat. FFmpeg types stay private.
pub const MediaInput = struct {
    allocator: Allocator,
    path: []u8,
    format_ctx: ?*c.AVFormatContext,
    streams: []StreamInfo,

    pub fn open(allocator: Allocator, path: []const u8) MediaError!MediaInput {
        if (path.len == 0) return error.InvalidArgument;

        const path_z = allocator.dupeZ(u8, path) catch return error.OutOfMemory;
        defer allocator.free(path_z);

        var format_ctx: ?*c.AVFormatContext = null;
        const open_rc = c.avformat_open_input(&format_ctx, path_z.ptr, null, null);
        if (open_rc < 0) return errors.fromAvError(open_rc);
        errdefer {
            var tmp: [*c]c.AVFormatContext = format_ctx;
            c.avformat_close_input(&tmp);
            format_ctx = null;
        }

        const find_rc = c.avformat_find_stream_info(format_ctx, null);
        if (find_rc < 0) return errors.fromAvError(find_rc);

        const ctx = format_ctx.?;
        const count: usize = ctx.nb_streams;
        var list: std.ArrayList(StreamInfo) = .empty;
        errdefer {
            for (list.items) |*s| s.deinit(allocator);
            list.deinit(allocator);
        }

        list.ensureTotalCapacity(allocator, count) catch return error.OutOfMemory;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const st = ctx.streams[i].*;
            const params = st.codecpar.*;
            const codec = c.avcodec_find_decoder(params.codec_id);
            const codec_name = if (codec != null)
                std.mem.span(codec.*.name)
            else
                "unknown";

            const owned_name = allocator.dupe(u8, codec_name) catch return error.OutOfMemory;
            errdefer allocator.free(owned_name);

            const info = StreamInfo{
                .index = @intCast(i),
                .kind = kindFrom(params.codec_type),
                .codec_name = owned_name,
                .time_base = .{
                    .numerator = st.time_base.num,
                    .denominator = st.time_base.den,
                },
                .width = if (params.codec_type == c.AVMEDIA_TYPE_VIDEO and params.width > 0)
                    @intCast(params.width)
                else
                    null,
                .height = if (params.codec_type == c.AVMEDIA_TYPE_VIDEO and params.height > 0)
                    @intCast(params.height)
                else
                    null,
                .pixel_format = if (params.codec_type == c.AVMEDIA_TYPE_VIDEO)
                    pixelFromAv(params.format)
                else
                    null,
                .sample_rate = if (params.codec_type == c.AVMEDIA_TYPE_AUDIO and params.sample_rate > 0)
                    @intCast(params.sample_rate)
                else
                    null,
                .channels = if (params.codec_type == c.AVMEDIA_TYPE_AUDIO)
                    @intCast(params.ch_layout.nb_channels)
                else
                    null,
                .channel_layout = if (params.codec_type == c.AVMEDIA_TYPE_AUDIO)
                    channelLayoutFromCount(@intCast(params.ch_layout.nb_channels))
                else
                    null,
                .sample_format = if (params.codec_type == c.AVMEDIA_TYPE_AUDIO)
                    sampleFromAv(params.format)
                else
                    null,
            };
            list.append(allocator, info) catch return error.OutOfMemory;
        }

        const owned_path = allocator.dupe(u8, path) catch return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .path = owned_path,
            .format_ctx = format_ctx,
            .streams = list.toOwnedSlice(allocator) catch return error.OutOfMemory,
        };
    }

    pub fn deinit(self: *MediaInput) void {
        if (self.format_ctx != null) {
            var tmp: [*c]c.AVFormatContext = self.format_ctx;
            c.avformat_close_input(&tmp);
            self.format_ctx = null;
        }
        for (self.streams) |*s| {
            s.deinit(self.allocator);
        }
        self.allocator.free(self.streams);
        self.allocator.free(self.path);
        self.* = undefined;
    }

    pub fn streamInfos(self: *const MediaInput) []const StreamInfo {
        return self.streams;
    }

    pub fn firstStreamOfKind(self: *const MediaInput, kind: StreamKind) ?u32 {
        for (self.streams) |s| {
            if (s.kind == kind) return s.index;
        }
        return null;
    }

    /// Internal: raw format context pointer for sibling runtime modules.
    pub fn formatContext(self: *MediaInput) *c.AVFormatContext {
        return self.format_ctx.?;
    }
};

fn kindFrom(codec_type: c.AVMediaType) StreamKind {
    return switch (codec_type) {
        c.AVMEDIA_TYPE_VIDEO => .video,
        c.AVMEDIA_TYPE_AUDIO => .audio,
        c.AVMEDIA_TYPE_SUBTITLE => .subtitle,
        c.AVMEDIA_TYPE_DATA => .data,
        else => .unknown,
    };
}

pub fn pixelFromAv(fmt: c_int) formats.PixelFormat {
    return switch (fmt) {
        c.AV_PIX_FMT_YUV420P => .yuv420p,
        c.AV_PIX_FMT_YUV422P => .yuv422p,
        c.AV_PIX_FMT_YUV444P => .yuv444p,
        c.AV_PIX_FMT_NV12 => .nv12,
        c.AV_PIX_FMT_RGBA => .rgba,
        c.AV_PIX_FMT_BGRA => .bgra,
        c.AV_PIX_FMT_RGB24 => .rgb24,
        c.AV_PIX_FMT_BGR24 => .bgr24,
        c.AV_PIX_FMT_GRAY8 => .gray8,
        else => .unknown,
    };
}

pub fn sampleFromAv(fmt: c_int) formats.SampleFormat {
    return switch (fmt) {
        c.AV_SAMPLE_FMT_U8 => .u8,
        c.AV_SAMPLE_FMT_S16 => .s16,
        c.AV_SAMPLE_FMT_S32 => .s32,
        c.AV_SAMPLE_FMT_FLT => .flt,
        c.AV_SAMPLE_FMT_DBL => .dbl,
        c.AV_SAMPLE_FMT_U8P => .u8p,
        c.AV_SAMPLE_FMT_S16P => .s16p,
        c.AV_SAMPLE_FMT_S32P => .s32p,
        c.AV_SAMPLE_FMT_FLTP => .fltp,
        c.AV_SAMPLE_FMT_DBLP => .dblp,
        else => .unknown,
    };
}

fn channelLayoutFromCount(count: u8) formats.ChannelLayout {
    return switch (count) {
        1 => .mono,
        2 => .stereo,
        6 => .surround_5_1,
        8 => .surround_7_1,
        else => .unknown,
    };
}
