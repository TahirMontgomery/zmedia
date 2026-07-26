const std = @import("std");
const zmedia = @import("zmedia");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const input: []const u8 = if (args.len > 1) args[1] else "fixtures/sample.mp4";

    var info = try zmedia.probe(allocator, io, input, .{});
    defer info.deinit(allocator);

    try std.Io.Dir.cwd().createDirPath(io, "output");

    var audio = zmedia.audioExtraction(input);
    var audio_result = try audio
        .codec(.mp3)
        .bitrate(.{ .kbps = 192 })
        .overwrite(true)
        .output("output/audio.mp3")
        .run(allocator, io);
    defer audio_result.deinit(allocator);
    try audio_result.expectSuccess();

    const timestamps = [_]zmedia.Timestamp{
        zmedia.Timestamp.fromSeconds(1),
        zmedia.Timestamp.fromSeconds(2),
        zmedia.Timestamp.fromSeconds(3),
    };

    var screenshots = zmedia.screenshotExtraction(input);
    var screenshot_results = try screenshots
        .timestamps(&timestamps)
        .format(.jpeg)
        .quality(.high)
        .outputDirectory("output/screenshots")
        .prefix("frame")
        .overwrite(true)
        .run(allocator, io);
    defer screenshot_results.deinit(allocator);

    if (!screenshot_results.succeeded()) {
        return error.ScreenshotExtractionFailed;
    }

    std.debug.print("Processed {s}\n", .{input});
}
