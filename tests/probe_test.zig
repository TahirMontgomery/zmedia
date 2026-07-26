const std = @import("std");
const zmedia = @import("zmedia");

test "rational parsing" {
    const rate = zmedia.Rational.parse("30/1").?;
    try std.testing.expectEqual(@as(u32, 30), rate.numerator);
    try std.testing.expectEqual(@as(u32, 1), rate.denominator);
    try std.testing.expectEqual(@as(f64, 30.0), rate.asFloat().?);
}

test "probe json parsing" {
    const json =
        \\{
        \\  "streams": [
        \\    {
        \\      "index": 0,
        \\      "codec_type": "video",
        \\      "codec_name": "h264",
        \\      "width": 1920,
        \\      "height": 1080,
        \\      "r_frame_rate": "30/1",
        \\      "pix_fmt": "yuv420p"
        \\    },
        \\    {
        \\      "index": 1,
        \\      "codec_type": "audio",
        \\      "codec_name": "aac",
        \\      "sample_rate": "48000",
        \\      "channels": 2,
        \\      "channel_layout": "stereo"
        \\    }
        \\  ],
        \\  "format": {
        \\    "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
        \\    "duration": "222.000000",
        \\    "bit_rate": "5000000"
        \\  }
        \\}
    ;

    var info = try zmedia.probe_mod.parseProbeJson(
        std.testing.allocator,
        "video.mp4",
        json,
    );
    defer info.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("video.mp4", info.path);
    try std.testing.expectEqualStrings("mov,mp4,m4a,3gp,3g2,mj2", info.format_name.?);
    try std.testing.expectEqual(
        zmedia.Timestamp.fromSeconds(222).microseconds,
        info.duration.?.microseconds,
    );
    try std.testing.expectEqual(@as(u64, 5_000_000), info.bitrate_bps.?);
    try std.testing.expectEqual(@as(usize, 1), info.video_streams.len);
    try std.testing.expectEqual(@as(usize, 1), info.audio_streams.len);
    try std.testing.expectEqualStrings("h264", info.video_streams[0].codec_name);
    try std.testing.expectEqual(@as(u32, 1920), info.video_streams[0].width.?);
    try std.testing.expectEqualStrings("aac", info.audio_streams[0].codec_name);
    try std.testing.expectEqual(@as(u32, 48_000), info.audio_streams[0].sample_rate.?);
    try std.testing.expectEqualStrings("stereo", info.audio_streams[0].channel_layout.?);
}
