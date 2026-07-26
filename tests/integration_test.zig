const std = @import("std");
const zmedia = @import("zmedia");

const fixture_path = "fixtures/sample.mp4";

test "ffmpeg and ffprobe are installed" {
    const io = std.testing.io;
    var info = try zmedia.checkInstallation(std.testing.allocator, io, .{});
    defer info.deinit(std.testing.allocator);

    try std.testing.expect(info.ffmpeg_available);
    try std.testing.expect(info.ffprobe_available);
}

test "probe fixture media" {
    const io = std.testing.io;
    var info = try zmedia.probe(std.testing.allocator, io, fixture_path, .{});
    defer info.deinit(std.testing.allocator);

    try std.testing.expect(info.video_streams.len >= 1);
    try std.testing.expect(info.audio_streams.len >= 1);
    try std.testing.expect(info.duration != null);
}

test "extract audio from fixture" {
    const io = std.testing.io;
    const output = "zig-out/tmp/integration-audio.mp3";

    var job = zmedia.audioExtraction(fixture_path);
    var result = try job
        .codec(.mp3)
        .bitrate(.{ .kbps = 128 })
        .overwrite(true)
        .output(output)
        .run(std.testing.allocator, io);
    defer result.deinit(std.testing.allocator);

    try result.expectSuccess();
}

test "extract screenshots from fixture" {
    const io = std.testing.io;
    const output_dir = "zig-out/tmp/integration-screenshots";

    const stamps = [_]zmedia.Timestamp{
        zmedia.Timestamp.fromSeconds(1),
        zmedia.Timestamp.fromSeconds(2),
    };

    var job = zmedia.screenshotExtraction(fixture_path);
    var result = try job
        .timestamps(&stamps)
        .format(.jpeg)
        .quality(.medium)
        .outputDirectory(output_dir)
        .prefix("shot")
        .overwrite(true)
        .run(std.testing.allocator, io);
    defer result.deinit(std.testing.allocator);

    try result.expectSuccess();
    try std.testing.expectEqual(@as(usize, 2), result.items.len);
}
