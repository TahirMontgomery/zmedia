//! Library-backed FFmpeg runtime tests (requires linked libav*).
const std = @import("std");
const zmedia = @import("zmedia");

test "av_version_info smoke" {
    const version = zmedia.runtime.ffmpegVersion();
    try std.testing.expect(version.len > 0);
}

test "MediaInput opens fixture and lists streams" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const streams = input.streamInfos();
    try std.testing.expect(streams.len >= 1);
    try std.testing.expect(input.firstStreamOfKind(.video) != null);
}

test "VideoDecoder yields at least one frame" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const video_index = input.firstStreamOfKind(.video) orelse return error.SkipZigTest;
    var decoder = try zmedia.VideoDecoder.init(std.testing.allocator, &input, video_index);
    defer decoder.deinit();

    var frame = try decoder.nextFrame() orelse return error.TestUnexpectedResult;
    defer frame.deinit();

    try std.testing.expect(frame.width > 0);
    try std.testing.expect(frame.height > 0);
    try std.testing.expect(frame.planes.len > 0);
}

test "AudioDecoder yields at least one frame" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const audio_index = input.firstStreamOfKind(.audio) orelse return error.SkipZigTest;
    var decoder = try zmedia.AudioDecoder.init(std.testing.allocator, &input, audio_index);
    defer decoder.deinit();

    var frame = try decoder.nextFrame() orelse return error.TestUnexpectedResult;
    defer frame.deinit();

    try std.testing.expect(frame.sample_count > 0);
    try std.testing.expect(frame.data.len > 0);
    try std.testing.expect(frame.sample_rate > 0);
}

test "AudioResampler converts decoded audio" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const audio_index = input.firstStreamOfKind(.audio) orelse return error.SkipZigTest;
    var decoder = try zmedia.AudioDecoder.init(std.testing.allocator, &input, audio_index);
    defer decoder.deinit();

    var frame = try decoder.nextFrame() orelse return error.TestUnexpectedResult;
    defer frame.deinit();

    var resampler = try zmedia.AudioResampler.init(
        48_000,
        .s16,
        .stereo,
        frame.sample_rate,
        frame.format,
        frame.channel_layout,
    );
    defer resampler.deinit();

    var converted = try resampler.convert(std.testing.allocator, &frame);
    defer converted.deinit();

    try std.testing.expectEqual(@as(u32, 48_000), converted.sample_rate);
    try std.testing.expect(converted.format == .s16);
    try std.testing.expect(converted.channel_layout == .stereo);
    try std.testing.expect(converted.sample_count > 0);
}
