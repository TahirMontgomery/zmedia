const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("ffmpeg_c");
const errors = @import("../internal/errors.zig");
const formats = @import("../formats/root.zig");
const frame_mod = @import("frame.zig");

const MediaError = errors.MediaError;
const PixelFormat = formats.PixelFormat;
const VideoFrame = frame_mod.VideoFrame;
const Plane = frame_mod.Plane;

/// Tightly packed destination buffer size for convert / convertInto.
pub fn dstByteLength(width: u32, height: u32, format: PixelFormat) usize {
    const bpp: usize = switch (format) {
        .rgba, .bgra => 4,
        .rgb24, .bgr24 => 3,
        .gray8 => 1,
        .yuv420p, .yuv422p, .yuv444p, .nv12, .unknown => 0,
    };
    return @as(usize, width) * @as(usize, height) * bpp;
}

pub fn pixelToAv(fmt: PixelFormat) ?c_int {
    return switch (fmt) {
        .yuv420p => c.AV_PIX_FMT_YUV420P,
        .yuv422p => c.AV_PIX_FMT_YUV422P,
        .yuv444p => c.AV_PIX_FMT_YUV444P,
        .nv12 => c.AV_PIX_FMT_NV12,
        .rgba => c.AV_PIX_FMT_RGBA,
        .bgra => c.AV_PIX_FMT_BGRA,
        .rgb24 => c.AV_PIX_FMT_RGB24,
        .bgr24 => c.AV_PIX_FMT_BGR24,
        .gray8 => c.AV_PIX_FMT_GRAY8,
        .unknown => null,
    };
}

fn isPackedRgb(fmt: PixelFormat) bool {
    return switch (fmt) {
        .rgba, .bgra, .rgb24, .bgr24, .gray8 => true,
        else => false,
    };
}

/// Reusable video pixel converter (libswscale).
///
/// Single-threaded: one instance must not be used concurrently from multiple
/// threads. Recreate or rebuild if source size/format changes mid-stream.
///
/// Color: v1 uses swscale defaults (limited-range **BT.601** for YUV→RGB when
/// the source does not carry usable color metadata through this public API).
/// Destination RGBA/BGRA is packed non-premultiplied; opaque YUV sources get
/// alpha = 255.
pub const VideoConverter = struct {
    allocator: Allocator,
    sws: ?*c.SwsContext,
    src_format: PixelFormat,
    dst_format: PixelFormat,
    width: u32,
    height: u32,

    pub fn init(
        allocator: Allocator,
        src_format: PixelFormat,
        width: u32,
        height: u32,
        dst_format: PixelFormat,
    ) MediaError!VideoConverter {
        if (width == 0 or height == 0) return error.InvalidArgument;
        if (!isPackedRgb(dst_format)) return error.Unsupported;
        const src_av = pixelToAv(src_format) orelse return error.Unsupported;
        const dst_av = pixelToAv(dst_format) orelse return error.Unsupported;

        const sws = c.sws_getContext(
            @intCast(width),
            @intCast(height),
            src_av,
            @intCast(width),
            @intCast(height),
            dst_av,
            c.SWS_BILINEAR,
            null,
            null,
            null,
        );
        if (sws == null) return error.Unsupported;

        return .{
            .allocator = allocator,
            .sws = sws,
            .src_format = src_format,
            .dst_format = dst_format,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *VideoConverter) void {
        if (self.sws) |sws| {
            c.sws_freeContext(sws);
            self.sws = null;
        }
        self.* = undefined;
    }

    /// Allocate and return an owned frame in `dst_format`.
    /// Output remains valid after `frame.deinit()`.
    pub fn convert(self: *VideoConverter, frame: *const VideoFrame) MediaError!VideoFrame {
        const needed = dstByteLength(self.width, self.height, self.dst_format);
        if (needed == 0) return error.Unsupported;
        const owned = self.allocator.alloc(u8, needed) catch return error.OutOfMemory;
        errdefer self.allocator.free(owned);

        try self.convertInto(frame, owned);

        const planes = self.allocator.alloc(Plane, 1) catch return error.OutOfMemory;
        errdefer self.allocator.free(planes);
        const stride = needed / @as(usize, self.height);
        planes[0] = .{
            .data = owned,
            .line_size = stride,
        };

        return .{
            .format = self.dst_format,
            .width = self.width,
            .height = self.height,
            .timestamp = frame.timestamp,
            .planes = planes,
            .storage = .{ .owned_bytes = owned },
            .allocator = self.allocator,
        };
    }

    /// Write tightly packed destination pixels into `out`.
    /// `out.len` must equal `dstByteLength(width, height, dst_format)`.
    pub fn convertInto(
        self: *VideoConverter,
        frame: *const VideoFrame,
        out: []u8,
    ) MediaError!void {
        const sws = self.sws orelse return error.InvalidArgument;
        if (frame.width != self.width or frame.height != self.height) return error.InvalidArgument;
        if (frame.format != self.src_format) return error.InvalidArgument;

        const needed = dstByteLength(self.width, self.height, self.dst_format);
        if (needed == 0) return error.Unsupported;
        if (out.len != needed) return error.InvalidArgument;

        var src_data: [4][*]const u8 = .{ undefined, undefined, undefined, undefined };
        var src_stride: [4]c_int = .{ 0, 0, 0, 0 };
        if (frame.planes.len == 0) return error.InvalidData;

        var pi: usize = 0;
        while (pi < frame.planes.len and pi < 4) : (pi += 1) {
            if (frame.planes[pi].data.len == 0) return error.InvalidData;
            src_data[pi] = frame.planes[pi].data.ptr;
            src_stride[pi] = @intCast(frame.planes[pi].line_size);
        }

        var dst_data: [4][*]u8 = .{ out.ptr, undefined, undefined, undefined };
        const dst_stride: [4]c_int = .{
            @intCast(needed / @as(usize, self.height)),
            0,
            0,
            0,
        };

        const scaled = c.sws_scale(
            sws,
            @ptrCast(&src_data),
            &src_stride,
            0,
            @intCast(self.height),
            @ptrCast(&dst_data),
            &dst_stride,
        );
        if (scaled < 0) return errors.fromAvError(scaled);
        if (scaled == 0) return error.InvalidData;
    }
};

/// One-shot convert helper (allocates a temporary `VideoConverter`).
pub fn convertVideoFrame(
    allocator: Allocator,
    frame: *const VideoFrame,
    dst_format: PixelFormat,
) MediaError!VideoFrame {
    var converter = try VideoConverter.init(
        allocator,
        frame.format,
        frame.width,
        frame.height,
        dst_format,
    );
    defer converter.deinit();
    return converter.convert(frame);
}
