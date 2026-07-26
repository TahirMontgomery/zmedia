pub const ImageFormat = enum {
    jpeg,
    png,
    webp,

    pub fn extension(self: ImageFormat) []const u8 {
        return switch (self) {
            .jpeg => "jpg",
            .png => "png",
            .webp => "webp",
        };
    }

    pub fn ffmpegCodec(self: ImageFormat) []const u8 {
        return switch (self) {
            .jpeg => "mjpeg",
            .png => "png",
            .webp => "libwebp",
        };
    }
};

pub const ImageQuality = enum {
    low,
    medium,
    high,
    maximum,

    /// FFmpeg JPEG quality scale: lower is better.
    pub fn jpegQScale(self: ImageQuality) u8 {
        return switch (self) {
            .low => 12,
            .medium => 7,
            .high => 3,
            .maximum => 1,
        };
    }

    /// Rough WebP quality mapping (0-100, higher is better).
    pub fn webpQuality(self: ImageQuality) u8 {
        return switch (self) {
            .low => 40,
            .medium => 65,
            .high => 85,
            .maximum => 95,
        };
    }
};
