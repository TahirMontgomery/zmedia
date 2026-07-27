const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("ffmpeg_c");
const errors = @import("../internal/errors.zig");
const formats = @import("../formats/root.zig");
const frame_mod = @import("frame.zig");
const input_mod = @import("input.zig");

const MediaError = errors.MediaError;
const MediaInput = input_mod.MediaInput;
const Rational = formats.Rational;
const VideoFrame = frame_mod.VideoFrame;
const AudioFrame = frame_mod.AudioFrame;

fn freeFrame(frame: *c.AVFrame) void {
    var tmp: [*c]c.AVFrame = frame;
    c.av_frame_free(&tmp);
}

fn freePacket(packet: *c.AVPacket) void {
    var tmp: [*c]c.AVPacket = packet;
    c.av_packet_free(&tmp);
}

fn freeCodecContext(ctx: *c.AVCodecContext) void {
    var tmp: [*c]c.AVCodecContext = ctx;
    c.avcodec_free_context(&tmp);
}

pub const VideoDecoder = struct {
    allocator: Allocator,
    input: *MediaInput,
    stream_index: u32,
    time_base: Rational,
    codec_ctx: ?*c.AVCodecContext,
    packet: ?*c.AVPacket,
    flushing: bool = false,
    eof: bool = false,

    pub fn init(allocator: Allocator, input: *MediaInput, stream_index: u32) MediaError!VideoDecoder {
        if (stream_index >= input.streams.len) return error.StreamNotFound;
        if (input.streams[stream_index].kind != .video) return error.InvalidArgument;

        const st = input.formatContext().streams[stream_index].*;
        const params = st.codecpar;
        const codec = c.avcodec_find_decoder(params.*.codec_id);
        if (codec == null) return error.DecoderNotFound;

        const codec_ctx = c.avcodec_alloc_context3(codec) orelse return error.OutOfMemory;
        errdefer freeCodecContext(codec_ctx);

        const param_rc = c.avcodec_parameters_to_context(codec_ctx, params);
        if (param_rc < 0) return errors.fromAvError(param_rc);

        const open_rc = c.avcodec_open2(codec_ctx, codec, null);
        if (open_rc < 0) return errors.fromAvError(open_rc);

        const packet = c.av_packet_alloc() orelse return error.OutOfMemory;

        return .{
            .allocator = allocator,
            .input = input,
            .stream_index = stream_index,
            .time_base = .{
                .numerator = st.time_base.num,
                .denominator = st.time_base.den,
            },
            .codec_ctx = codec_ctx,
            .packet = packet,
        };
    }

    pub fn deinit(self: *VideoDecoder) void {
        if (self.packet) |pkt| {
            freePacket(pkt);
            self.packet = null;
        }
        if (self.codec_ctx) |ctx| {
            freeCodecContext(ctx);
            self.codec_ctx = null;
        }
        self.* = undefined;
    }

    /// Returns the next decoded video frame, or null at end of stream.
    pub fn nextFrame(self: *VideoDecoder) MediaError!?VideoFrame {
        if (self.eof) return null;
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;
        const packet = self.packet orelse return error.InvalidArgument;
        const format_ctx = self.input.formatContext();

        while (true) {
            const frame = c.av_frame_alloc() orelse return error.OutOfMemory;
            errdefer freeFrame(frame);

            const receive_rc = c.avcodec_receive_frame(codec_ctx, frame);
            if (receive_rc == 0) {
                return try frame_mod.videoFromAv(self.allocator, frame, self.time_base);
            }
            if (receive_rc == errors.averror_eof) {
                freeFrame(frame);
                self.eof = true;
                return null;
            }
            if (receive_rc != c.AVERROR(c.EAGAIN)) {
                freeFrame(frame);
                return errors.fromAvError(receive_rc);
            }
            freeFrame(frame);

            if (self.flushing) {
                const flush_rc = c.avcodec_send_packet(codec_ctx, null);
                if (flush_rc < 0 and flush_rc != errors.averror_eof) {
                    return errors.fromAvError(flush_rc);
                }
                continue;
            }

            c.av_packet_unref(packet);
            const read_rc = c.av_read_frame(format_ctx, packet);
            if (read_rc == errors.averror_eof) {
                self.flushing = true;
                const flush_rc = c.avcodec_send_packet(codec_ctx, null);
                if (flush_rc < 0 and flush_rc != errors.averror_eof) {
                    return errors.fromAvError(flush_rc);
                }
                continue;
            }
            if (read_rc < 0) return errors.fromAvError(read_rc);

            if (@as(u32, @intCast(packet.stream_index)) != self.stream_index) {
                continue;
            }

            const send_rc = c.avcodec_send_packet(codec_ctx, packet);
            if (send_rc < 0) return errors.fromAvError(send_rc);
        }
    }
};

pub const AudioDecoder = struct {
    allocator: Allocator,
    input: *MediaInput,
    stream_index: u32,
    time_base: Rational,
    codec_ctx: ?*c.AVCodecContext,
    packet: ?*c.AVPacket,
    flushing: bool = false,
    eof: bool = false,

    pub fn init(allocator: Allocator, input: *MediaInput, stream_index: u32) MediaError!AudioDecoder {
        if (stream_index >= input.streams.len) return error.StreamNotFound;
        if (input.streams[stream_index].kind != .audio) return error.InvalidArgument;

        const st = input.formatContext().streams[stream_index].*;
        const params = st.codecpar;
        const codec = c.avcodec_find_decoder(params.*.codec_id);
        if (codec == null) return error.DecoderNotFound;

        const codec_ctx = c.avcodec_alloc_context3(codec) orelse return error.OutOfMemory;
        errdefer freeCodecContext(codec_ctx);

        const param_rc = c.avcodec_parameters_to_context(codec_ctx, params);
        if (param_rc < 0) return errors.fromAvError(param_rc);

        const open_rc = c.avcodec_open2(codec_ctx, codec, null);
        if (open_rc < 0) return errors.fromAvError(open_rc);

        const packet = c.av_packet_alloc() orelse return error.OutOfMemory;

        return .{
            .allocator = allocator,
            .input = input,
            .stream_index = stream_index,
            .time_base = .{
                .numerator = st.time_base.num,
                .denominator = st.time_base.den,
            },
            .codec_ctx = codec_ctx,
            .packet = packet,
        };
    }

    pub fn deinit(self: *AudioDecoder) void {
        if (self.packet) |pkt| {
            freePacket(pkt);
            self.packet = null;
        }
        if (self.codec_ctx) |ctx| {
            freeCodecContext(ctx);
            self.codec_ctx = null;
        }
        self.* = undefined;
    }

    pub fn nextFrame(self: *AudioDecoder) MediaError!?AudioFrame {
        if (self.eof) return null;
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;
        const packet = self.packet orelse return error.InvalidArgument;
        const format_ctx = self.input.formatContext();

        while (true) {
            const frame = c.av_frame_alloc() orelse return error.OutOfMemory;
            errdefer freeFrame(frame);

            const receive_rc = c.avcodec_receive_frame(codec_ctx, frame);
            if (receive_rc == 0) {
                return try frame_mod.audioFromAv(self.allocator, frame, self.time_base);
            }
            if (receive_rc == errors.averror_eof) {
                freeFrame(frame);
                self.eof = true;
                return null;
            }
            if (receive_rc != c.AVERROR(c.EAGAIN)) {
                freeFrame(frame);
                return errors.fromAvError(receive_rc);
            }
            freeFrame(frame);

            if (self.flushing) {
                const flush_rc = c.avcodec_send_packet(codec_ctx, null);
                if (flush_rc < 0 and flush_rc != errors.averror_eof) {
                    return errors.fromAvError(flush_rc);
                }
                continue;
            }

            c.av_packet_unref(packet);
            const read_rc = c.av_read_frame(format_ctx, packet);
            if (read_rc == errors.averror_eof) {
                self.flushing = true;
                const flush_rc = c.avcodec_send_packet(codec_ctx, null);
                if (flush_rc < 0 and flush_rc != errors.averror_eof) {
                    return errors.fromAvError(flush_rc);
                }
                continue;
            }
            if (read_rc < 0) return errors.fromAvError(read_rc);

            if (@as(u32, @intCast(packet.stream_index)) != self.stream_index) {
                continue;
            }

            const send_rc = c.avcodec_send_packet(codec_ctx, packet);
            if (send_rc < 0) return errors.fromAvError(send_rc);
        }
    }
};
