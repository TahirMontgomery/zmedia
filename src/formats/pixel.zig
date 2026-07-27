pub const PixelFormat = enum {
    unknown,
    yuv420p,
    yuv422p,
    yuv444p,
    nv12,
    rgba,
    bgra,
    rgb24,
    bgr24,
    gray8,

    pub fn name(self: PixelFormat) []const u8 {
        return @tagName(self);
    }
};
