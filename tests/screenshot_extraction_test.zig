const std = @import("std");
const zmedia = @import("zmedia");

test "image format mappings" {
    try std.testing.expectEqualStrings("jpg", zmedia.ImageFormat.jpeg.extension());
    try std.testing.expectEqualStrings("mjpeg", zmedia.ImageFormat.jpeg.ffmpegCodec());
    try std.testing.expectEqual(@as(u8, 3), zmedia.ImageQuality.high.jpegQScale());
}

test "screenshot output path generation" {
    var job = zmedia.ScreenshotExtraction.init("video.mp4");
    _ = job
        .outputDirectory("screenshots")
        .prefix("frame")
        .format(.jpeg);

    const path = try job.outputPathForIndex(std.testing.allocator, 0);
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("screenshots/frame-001.jpg", path);
}

test "screenshot command includes seek and quality" {
    const stamps = [_]zmedia.Timestamp{
        zmedia.Timestamp.fromSeconds(5),
    };

    var job = zmedia.ScreenshotExtraction.init("video.mp4");
    _ = job
        .timestamps(&stamps)
        .format(.jpeg)
        .quality(.high)
        .outputDirectory("screenshots")
        .prefix("frame")
        .overwrite(true);

    var built = try job.buildForTimestamp(
        std.testing.allocator,
        .{},
        stamps[0],
        "screenshots/frame-001.jpg",
    );
    defer built.deinit();

    try expectArgv(
        &.{
            "-y",
            "-ss",
            "00:00:05.000",
            "-i",
            "video.mp4",
            "-frames:v",
            "1",
            "-c:v",
            "mjpeg",
            "-q:v",
            "3",
            "screenshots/frame-001.jpg",
        },
        built.argv(),
    );
}

fn expectArgv(expected: []const []const u8, actual: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| {
        try std.testing.expectEqualStrings(want, got);
    }
}

test "screenshot validation requires timestamps" {
    var job = zmedia.ScreenshotExtraction.init("video.mp4");
    _ = job.outputDirectory("screenshots");
    try std.testing.expectError(error.NoTimestamps, job.validate());
}
