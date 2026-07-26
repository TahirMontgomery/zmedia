const std = @import("std");
const zmedia = @import("zmedia");

test "timestamp constructors" {
    try std.testing.expectEqual(
        @as(u64, 5 * std.time.us_per_s),
        zmedia.Timestamp.fromSeconds(5).microseconds,
    );
    try std.testing.expectEqual(
        @as(u64, 1500 * std.time.us_per_ms),
        zmedia.Timestamp.fromMilliseconds(1500).microseconds,
    );
    try std.testing.expectEqual(
        zmedia.Timestamp.fromSeconds(75).microseconds,
        zmedia.Timestamp.fromMinutesSeconds(1, 15).microseconds,
    );
}

test "timestamp formatting preserves milliseconds" {
    const stamp = zmedia.Timestamp.fromMilliseconds(75_500);
    const formatted = try stamp.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("00:01:15.500", formatted);
}
