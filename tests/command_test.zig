const std = @import("std");
const zmedia = @import("zmedia");

test "command owns duplicated arguments" {
    var command = zmedia.Command.init(std.testing.allocator, "ffmpeg");
    defer command.deinit();

    try command.append("-y");
    try command.append("-b:a");
    try command.append("192k");

    try std.testing.expectEqual(@as(usize, 3), command.argv().len);
    try std.testing.expectEqualStrings("-y", command.argv()[0]);
    try std.testing.expectEqualStrings("192k", command.argv()[2]);
}

test "command render quotes spaced arguments" {
    var command = zmedia.Command.init(std.testing.allocator, "ffmpeg");
    defer command.deinit();

    try command.append("-i");
    try command.append("input video.mp4");
    try command.append("out.mp3");

    const rendered = try command.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings(
        "ffmpeg -i \"input video.mp4\" out.mp3",
        rendered,
    );
}
