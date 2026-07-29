const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("ffmpeg_c");
const cancel_mod = @import("cancel.zig");
const errors = @import("../internal/errors.zig");
const formats = @import("../formats/root.zig");
const frame_mod = @import("frame.zig");
const input_mod = @import("input.zig");
const packet_mod = @import("packet.zig");

const MediaError = errors.MediaError;
const MediaInput = input_mod.MediaInput;
const Rational = formats.Rational;
const VideoFrame = frame_mod.VideoFrame;
const AudioFrame = frame_mod.AudioFrame;
const Packet = packet_mod.Packet;
const CancelToken = cancel_mod.CancelToken;
const InterruptState = cancel_mod.InterruptState;

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

fn installInterrupt(input: *MediaInput, state: *InterruptState) void {
    const ctx = input.formatContext();
    ctx.interrupt_callback = .{
        .callback = interruptCallback,
        .@"opaque" = state,
    };
}

fn clearInterrupt(input: *MediaInput) void {
    if (input.format_ctx == null) return;
    const ctx = input.formatContext();
    ctx.interrupt_callback = .{
        .callback = null,
        .@"opaque" = null,
    };
}

fn interruptCallback(opaque_ptr: ?*anyopaque) callconv(.c) c_int {
    if (opaque_ptr == null) return 0;
    const state: *InterruptState = @ptrCast(@alignCast(opaque_ptr));
    return if (state.shouldAbort()) 1 else 0;
}

fn interruptError(reason: cancel_mod.InterruptReason) MediaError {
    return switch (reason) {
        .cancelled => error.Cancelled,
        .timed_out => error.TimedOut,
        .none => error.Unknown,
    };
}

/// Video decoder. Prefer packet-driven APIs for A/V on one `MediaInput`.
///
/// `nextFrame` is a **single-consumer** convenience: it demuxes and drops packets
/// for other streams. Do not run two `nextFrame` consumers (or a `Demuxer` plus
/// `nextFrame`) on the same open input.
pub const VideoDecoder = struct {
    allocator: Allocator,
    input: *MediaInput,
    stream_index: u32,
    time_base: Rational,
    codec_ctx: ?*c.AVCodecContext,
    /// Internal packet used only by `nextFrame`.
    packet: ?*c.AVPacket,
    cancel: ?*CancelToken = null,
    interrupt_state: InterruptState = .{},
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

    pub fn setCancel(self: *VideoDecoder, cancel: ?*CancelToken) void {
        self.cancel = cancel;
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

    /// Borrow `packet` for the duration of this call. Caller retains `Packet.deinit`.
    pub fn sendPacket(self: *VideoDecoder, packet: *const Packet) MediaError!void {
        if (packet.stream_index != self.stream_index) return error.InvalidArgument;
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;
        const raw = packet.raw orelse return error.InvalidArgument;
        const send_rc = c.avcodec_send_packet(codec_ctx, raw);
        if (send_rc < 0) return errors.fromAvError(send_rc);
    }

    pub fn sendFlush(self: *VideoDecoder) MediaError!void {
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;
        const send_rc = c.avcodec_send_packet(codec_ctx, null);
        if (send_rc < 0 and send_rc != errors.averror_eof) {
            return errors.fromAvError(send_rc);
        }
        self.flushing = true;
    }

    /// Returns a decoded frame, or null on EAGAIN / EOF (need more input or drained).
    pub fn receiveFrame(self: *VideoDecoder) MediaError!?VideoFrame {
        if (self.eof) return null;
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;

        const frame = c.av_frame_alloc() orelse return error.OutOfMemory;
        errdefer freeFrame(frame);

        const receive_rc = c.avcodec_receive_frame(codec_ctx, frame);
        if (receive_rc == 0) {
            return try frame_mod.videoFromAv(self.allocator, frame, self.time_base);
        }
        freeFrame(frame);
        if (receive_rc == c.AVERROR(c.EAGAIN)) return null;
        if (receive_rc == errors.averror_eof) {
            self.eof = true;
            return null;
        }
        return errors.fromAvError(receive_rc);
    }

    /// Single-stream convenience (demux + filter + decode). Unsupported alongside
    /// another `nextFrame` / `Demuxer` on the same `MediaInput`.
    pub fn nextFrame(self: *VideoDecoder) MediaError!?VideoFrame {
        if (self.eof) return null;

        while (true) {
            if (try self.receiveFrame()) |frame| return frame;
            if (self.eof) return null;

            if (self.flushing) {
                // Drain codec until EOF; do not demux further.
                continue;
            }

            self.interrupt_state = .{
                .cancel = self.cancel,
                .reason = .none,
            };
            if (self.interrupt_state.shouldAbort()) return interruptError(self.interrupt_state.reason);

            const packet = self.packet orelse return error.InvalidArgument;
            installInterrupt(self.input, &self.interrupt_state);
            defer clearInterrupt(self.input);

            c.av_packet_unref(packet);
            const read_rc = c.av_read_frame(self.input.formatContext(), packet);
            if (read_rc == errors.averror_eof) {
                try self.sendFlush();
                continue;
            }
            if (read_rc < 0) {
                if (self.interrupt_state.reason != .none) return interruptError(self.interrupt_state.reason);
                return errors.fromAvError(read_rc);
            }

            if (@as(u32, @intCast(packet.stream_index)) != self.stream_index) {
                continue;
            }

            const send_rc = c.avcodec_send_packet(self.codec_ctx.?, packet);
            if (send_rc < 0) return errors.fromAvError(send_rc);
        }
    }
};

/// Audio decoder. Prefer packet-driven APIs for A/V on one `MediaInput`.
///
/// `nextFrame` is single-consumer-only (see `VideoDecoder`).
pub const AudioDecoder = struct {
    allocator: Allocator,
    input: *MediaInput,
    stream_index: u32,
    time_base: Rational,
    codec_ctx: ?*c.AVCodecContext,
    packet: ?*c.AVPacket,
    cancel: ?*CancelToken = null,
    interrupt_state: InterruptState = .{},
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

    pub fn setCancel(self: *AudioDecoder, cancel: ?*CancelToken) void {
        self.cancel = cancel;
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

    /// Borrow `packet` for the duration of this call. Caller retains `Packet.deinit`.
    pub fn sendPacket(self: *AudioDecoder, packet: *const Packet) MediaError!void {
        if (packet.stream_index != self.stream_index) return error.InvalidArgument;
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;
        const raw = packet.raw orelse return error.InvalidArgument;
        const send_rc = c.avcodec_send_packet(codec_ctx, raw);
        if (send_rc < 0) return errors.fromAvError(send_rc);
    }

    pub fn sendFlush(self: *AudioDecoder) MediaError!void {
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;
        const send_rc = c.avcodec_send_packet(codec_ctx, null);
        if (send_rc < 0 and send_rc != errors.averror_eof) {
            return errors.fromAvError(send_rc);
        }
        self.flushing = true;
    }

    pub fn receiveFrame(self: *AudioDecoder) MediaError!?AudioFrame {
        if (self.eof) return null;
        const codec_ctx = self.codec_ctx orelse return error.InvalidArgument;

        const frame = c.av_frame_alloc() orelse return error.OutOfMemory;
        errdefer freeFrame(frame);

        const receive_rc = c.avcodec_receive_frame(codec_ctx, frame);
        if (receive_rc == 0) {
            return try frame_mod.audioFromAv(self.allocator, frame, self.time_base);
        }
        freeFrame(frame);
        if (receive_rc == c.AVERROR(c.EAGAIN)) return null;
        if (receive_rc == errors.averror_eof) {
            self.eof = true;
            return null;
        }
        return errors.fromAvError(receive_rc);
    }

    pub fn nextFrame(self: *AudioDecoder) MediaError!?AudioFrame {
        if (self.eof) return null;

        while (true) {
            if (try self.receiveFrame()) |frame| return frame;
            if (self.eof) return null;

            if (self.flushing) {
                // Drain codec until EOF; do not demux further.
                continue;
            }

            self.interrupt_state = .{
                .cancel = self.cancel,
                .reason = .none,
            };
            if (self.interrupt_state.shouldAbort()) return interruptError(self.interrupt_state.reason);

            const packet = self.packet orelse return error.InvalidArgument;
            installInterrupt(self.input, &self.interrupt_state);
            defer clearInterrupt(self.input);

            c.av_packet_unref(packet);
            const read_rc = c.av_read_frame(self.input.formatContext(), packet);
            if (read_rc == errors.averror_eof) {
                try self.sendFlush();
                continue;
            }
            if (read_rc < 0) {
                if (self.interrupt_state.reason != .none) return interruptError(self.interrupt_state.reason);
                return errors.fromAvError(read_rc);
            }

            if (@as(u32, @intCast(packet.stream_index)) != self.stream_index) {
                continue;
            }

            const send_rc = c.avcodec_send_packet(self.codec_ctx.?, packet);
            if (send_rc < 0) return errors.fromAvError(send_rc);
        }
    }
};
