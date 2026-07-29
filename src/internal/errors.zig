const std = @import("std");

const build_options = @import("build_options");

/// Public media errors. Raw FFmpeg AVERROR codes never leave this package.
pub const MediaError = error{
    OutOfMemory,
    InvalidArgument,
    InvalidData,
    NotFound,
    PermissionDenied,
    EndOfStream,
    DecoderNotFound,
    EncoderNotFound,
    DemuxerNotFound,
    MuxerNotFound,
    ProtocolNotFound,
    StreamNotFound,
    Unsupported,
    BufferTooSmall,
    /// Codec/filter backpressure (`AVERROR(EAGAIN)`): drain via `receiveFrame` / consume
    /// output, then retry the send. Distinct from open-time `TimedOut` / `Cancelled`.
    WouldBlock,
    /// FFmpeg AVERROR(ETIMEDOUT) / network timeout from demuxer.
    Timeout,
    /// OpenOptions.timeout_ns fired during MediaInput.openWithOptions.
    TimedOut,
    /// CancelToken was signaled during MediaInput.openWithOptions.
    Cancelled,
    Exit,
    Bug,
    Unknown,
};

/// Zig translate-c breaks FFmpeg's FFERRTAG/MKTAG macros; compute tags locally.
fn mkTag(a: u32, b: u32, c: u32, d: u32) u32 {
    return a | (b << 8) | (c << 16) | (d << 24);
}

fn ffErrTag(a: u32, b: u32, c: u32, d: u32) c_int {
    return -@as(c_int, @bitCast(mkTag(a, b, c, d)));
}

pub const averror_eof = ffErrTag('E', 'O', 'F', ' ');
pub const averror_invaliddata = ffErrTag('I', 'N', 'D', 'A');
pub const averror_decoder_not_found = ffErrTag(0xF8, 'D', 'E', 'C');
pub const averror_encoder_not_found = ffErrTag(0xF8, 'E', 'N', 'C');
pub const averror_demuxer_not_found = ffErrTag(0xF8, 'D', 'E', 'M');
pub const averror_muxer_not_found = ffErrTag(0xF8, 'M', 'U', 'X');
pub const averror_protocol_not_found = ffErrTag(0xF8, 'P', 'R', 'O');
pub const averror_stream_not_found = ffErrTag(0xF8, 'S', 'T', 'R');
pub const averror_patchwelcome = ffErrTag('P', 'A', 'W', 'E');
pub const averror_buffer_too_small = ffErrTag('B', 'U', 'F', 'S');
pub const averror_exit = ffErrTag('E', 'X', 'I', 'T');
pub const averror_bug = ffErrTag('B', 'U', 'G', '!');
pub const averror_bug2 = ffErrTag('B', 'U', 'G', ' ');

pub fn fromAvError(errnum: c_int) MediaError {
    if (!build_options.link_ffmpeg) return error.Unknown;
    const c = @import("ffmpeg_c");
    if (errnum >= 0) return error.Unknown;
    return switch (errnum) {
        c.AVERROR(c.ENOMEM) => error.OutOfMemory,
        c.AVERROR(c.EINVAL) => error.InvalidArgument,
        averror_invaliddata => error.InvalidData,
        c.AVERROR(c.ENOENT) => error.NotFound,
        c.AVERROR(c.EACCES), c.AVERROR(c.EPERM) => error.PermissionDenied,
        averror_eof => error.EndOfStream,
        averror_decoder_not_found => error.DecoderNotFound,
        averror_encoder_not_found => error.EncoderNotFound,
        averror_demuxer_not_found => error.DemuxerNotFound,
        averror_muxer_not_found => error.MuxerNotFound,
        averror_protocol_not_found => error.ProtocolNotFound,
        averror_stream_not_found => error.StreamNotFound,
        c.AVERROR(c.ENOSYS), averror_patchwelcome => error.Unsupported,
        averror_buffer_too_small => error.BufferTooSmall,
        c.AVERROR(c.EAGAIN) => error.WouldBlock,
        c.AVERROR(c.ETIMEDOUT) => error.Timeout,
        averror_exit => error.Exit,
        averror_bug, averror_bug2 => error.Bug,
        else => error.Unknown,
    };
}

pub fn formatAvError(errnum: c_int, buffer: []u8) []const u8 {
    if (!build_options.link_ffmpeg) return "ffmpeg disabled";
    const c = @import("ffmpeg_c");
    _ = c.av_strerror(errnum, buffer.ptr, buffer.len);
    return std.mem.sliceTo(buffer, 0);
}
