const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Timestamp = struct {
    microseconds: u64,

    pub fn fromSeconds(seconds: u64) Timestamp {
        return .{
            .microseconds = seconds * std.time.us_per_s,
        };
    }

    pub fn fromMilliseconds(milliseconds: u64) Timestamp {
        return .{
            .microseconds = milliseconds * std.time.us_per_ms,
        };
    }

    pub fn fromMinutesSeconds(minutes: u64, seconds: u64) Timestamp {
        return fromSeconds(minutes * 60 + seconds);
    }

    pub fn fromHoursMinutesSeconds(
        hours: u64,
        minutes: u64,
        seconds: u64,
    ) Timestamp {
        return fromSeconds(hours * 3600 + minutes * 60 + seconds);
    }

    pub fn fromFloatSeconds(seconds: f64) Timestamp {
        if (seconds <= 0) {
            return .{ .microseconds = 0 };
        }
        const micros = seconds * @as(f64, @floatFromInt(std.time.us_per_s));
        return .{
            .microseconds = @intFromFloat(@min(micros, @as(f64, @floatFromInt(std.math.maxInt(u64))))),
        };
    }

    pub fn format(self: Timestamp, writer: *Io.Writer) !void {
        const split = self.parts();
        try writer.print(
            "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}",
            .{
                split.hours,
                split.minutes,
                split.seconds,
                split.milliseconds,
            },
        );
    }

    pub fn formatBuf(self: Timestamp, buffer: []u8) ![]u8 {
        var fixed = Io.Writer.fixed(buffer);
        try self.format(&fixed);
        return fixed.buffered();
    }

    pub fn formatAlloc(self: Timestamp, allocator: Allocator) ![]u8 {
        var buffer: [32]u8 = undefined;
        const formatted = try self.formatBuf(&buffer);
        return try allocator.dupe(u8, formatted);
    }

    pub fn eql(self: Timestamp, other: Timestamp) bool {
        return self.microseconds == other.microseconds;
    }

    const Parts = struct {
        hours: u64,
        minutes: u64,
        seconds: u64,
        milliseconds: u64,
    };

    fn parts(self: Timestamp) Parts {
        const total_seconds = self.microseconds / std.time.us_per_s;
        const remainder_us = self.microseconds % std.time.us_per_s;
        return .{
            .hours = total_seconds / 3600,
            .minutes = (total_seconds % 3600) / 60,
            .seconds = total_seconds % 60,
            .milliseconds = remainder_us / std.time.us_per_ms,
        };
    }
};
