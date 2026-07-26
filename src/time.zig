const std = @import("std");
const Allocator = std.mem.Allocator;

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

    pub fn formatAlloc(self: Timestamp, allocator: Allocator) ![]u8 {
        const total_seconds = self.microseconds / std.time.us_per_s;
        const remainder_us = self.microseconds % std.time.us_per_s;

        const hours = total_seconds / 3600;
        const minutes = (total_seconds % 3600) / 60;
        const seconds = total_seconds % 60;
        const milliseconds = remainder_us / std.time.us_per_ms;

        return std.fmt.allocPrint(
            allocator,
            "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}",
            .{
                hours,
                minutes,
                seconds,
                milliseconds,
            },
        );
    }

    pub fn eql(self: Timestamp, other: Timestamp) bool {
        return self.microseconds == other.microseconds;
    }
};
