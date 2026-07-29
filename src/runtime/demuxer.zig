const std = @import("std");

const c = @import("ffmpeg_c");
const cancel_mod = @import("cancel.zig");
const errors = @import("../internal/errors.zig");
const formats = @import("../formats/root.zig");
const input_mod = @import("input.zig");
const packet_mod = @import("packet.zig");

const MediaError = errors.MediaError;
const MediaInput = input_mod.MediaInput;
const CancelToken = cancel_mod.CancelToken;
const InterruptState = cancel_mod.InterruptState;
const Packet = packet_mod.Packet;
const Rational = formats.Rational;

pub const DemuxerOptions = struct {
    cancel: ?*CancelToken = null,
};

/// Single demux cursor over an open `MediaInput`.
///
/// One demuxer (and its packet-driven decoders) is single-threaded.
/// Do not also call `VideoDecoder.nextFrame` / `AudioDecoder.nextFrame` on the
/// same input while this demuxer is active — those helpers advance the same
/// format-context read cursor.
pub const Demuxer = struct {
    input: *MediaInput,
    cancel: ?*CancelToken = null,
    /// Stable storage for FFmpeg interrupt opaque (must outlive `av_read_frame`).
    interrupt_state: InterruptState = .{},
    eof: bool = false,

    pub fn init(input: *MediaInput) Demuxer {
        return initWithOptions(input, .{});
    }

    pub fn initWithOptions(input: *MediaInput, options: DemuxerOptions) Demuxer {
        return .{
            .input = input,
            .cancel = options.cancel,
        };
    }

    pub fn deinit(self: *Demuxer) void {
        clearInterrupt(self.input);
        self.* = undefined;
    }

    /// Next compressed packet, or null at EOF.
    /// Caller must `Packet.deinit`. Cancel → `error.Cancelled`.
    pub fn nextPacket(self: *Demuxer) MediaError!?Packet {
        if (self.eof) return null;

        self.interrupt_state = .{
            .cancel = self.cancel,
            .reason = .none,
        };
        if (self.interrupt_state.shouldAbort()) {
            return interruptError(self.interrupt_state.reason);
        }

        installInterrupt(self.input, &self.interrupt_state);
        defer clearInterrupt(self.input);

        const pkt = c.av_packet_alloc() orelse return error.OutOfMemory;
        errdefer {
            var tmp: [*c]c.AVPacket = pkt;
            c.av_packet_free(&tmp);
        }

        const read_rc = c.av_read_frame(self.input.formatContext(), pkt);
        if (read_rc == errors.averror_eof) {
            var tmp: [*c]c.AVPacket = pkt;
            c.av_packet_free(&tmp);
            self.eof = true;
            return null;
        }
        if (read_rc < 0) {
            // errdefer owns cleanup on error returns — do not free here.
            if (self.interrupt_state.reason != .none) {
                return interruptError(self.interrupt_state.reason);
            }
            return errors.fromAvError(read_rc);
        }

        const stream_index: u32 = @intCast(pkt.*.stream_index);
        const time_base: Rational = if (stream_index < self.input.streams.len)
            self.input.streams[stream_index].time_base
        else
            Rational.one;

        return Packet.fromAv(pkt, time_base);
    }
};

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
