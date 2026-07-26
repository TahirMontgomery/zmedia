const std = @import("std");
const zmedia = @import("zmedia");
const helpers = @import("test_helpers.zig");

test "audio codec ffmpeg names" {
    try std.testing.expectEqualStrings("copy", zmedia.AudioCodec.copy.ffmpegName());
    try std.testing.expectEqualStrings("libmp3lame", zmedia.AudioCodec.mp3.ffmpegName());
    try std.testing.expectEqualStrings("aac", zmedia.AudioCodec.aac.ffmpegName());
}

test "audio bitrate formatting" {
    const kbps_value: zmedia.AudioBitrate = .{ .kbps = 192 };
    const kbps = try kbps_value.format(std.testing.allocator);
    defer std.testing.allocator.free(kbps);
    try std.testing.expectEqualStrings("192k", kbps);

    const mbps_value: zmedia.AudioBitrate = .{ .mbps = 1.5 };
    const mbps = try mbps_value.format(std.testing.allocator);
    defer std.testing.allocator.free(mbps);
    try std.testing.expectEqualStrings("1.50M", mbps);
}

test "mp3 audio extraction builds expected arguments" {
    var job = zmedia.AudioExtraction.init("video.mp4");

    _ = job
        .codec(.mp3)
        .bitrate(.{ .kbps = 192 })
        .overwrite(true)
        .output("audio.mp3");

    var built = try job.build(std.testing.allocator, .{});
    defer built.deinit();

    try std.testing.expectEqualStrings("ffmpeg", built.executable);
    try helpers.expectArgv(
        &.{
            "-y",
            "-i",
            "video.mp4",
            "-vn",
            "-c:a",
            "libmp3lame",
            "-b:a",
            "192k",
            "audio.mp3",
        },
        built.argv(),
    );
}

test "copy codec rejects bitrate" {
    var job = zmedia.AudioExtraction.init("video.mp4");
    _ = job.codec(.copy).bitrate(.{ .kbps = 128 }).output("audio.aac");
    try std.testing.expectError(error.BitrateNotAllowedWithCopy, job.validate());
}

test "missing output fails validation" {
    var job = zmedia.AudioExtraction.init("video.mp4");
    try std.testing.expectError(error.MissingOutputPath, job.validate());
}
