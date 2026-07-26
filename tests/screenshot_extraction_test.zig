const std = @import("std");
const zmedia = @import("zmedia");
const helpers = @import("test_helpers.zig");

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

test "screenshot build emits one multi-output command" {
    const stamps = [_]zmedia.Timestamp{
        zmedia.Timestamp.fromSeconds(5),
        zmedia.Timestamp.fromSeconds(20),
    };

    var job = zmedia.ScreenshotExtraction.init("video.mp4");
    _ = job
        .timestamps(&stamps)
        .format(.jpeg)
        .quality(.high)
        .outputDirectory("screenshots")
        .prefix("frame")
        .overwrite(true);

    var built = try job.build(std.testing.allocator, .{});
    defer built.deinit();

    try helpers.expectArgv(
        &.{
            "-y",
            "-i",
            "video.mp4",
            "-ss",
            "00:00:05.000",
            "-frames:v",
            "1",
            "-c:v",
            "mjpeg",
            "-q:v",
            "3",
            "screenshots/frame-001.jpg",
            "-ss",
            "00:00:20.000",
            "-frames:v",
            "1",
            "-c:v",
            "mjpeg",
            "-q:v",
            "3",
            "screenshots/frame-002.jpg",
        },
        built.argv(),
    );
}

test "screenshot validation requires timestamps" {
    var job = zmedia.ScreenshotExtraction.init("video.mp4");
    _ = job.outputDirectory("screenshots");
    try std.testing.expectError(error.NoTimestamps, job.validate());
}

test "rejectDuplicates setter validates duplicates" {
    const stamps = [_]zmedia.Timestamp{
        zmedia.Timestamp.fromSeconds(5),
        zmedia.Timestamp.fromSeconds(5),
    };

    var job = zmedia.ScreenshotExtraction.init("video.mp4");
    _ = job
        .timestamps(&stamps)
        .outputDirectory("screenshots")
        .rejectDuplicates(true);

    try std.testing.expectError(error.DuplicateTimestamp, job.validate());
}
