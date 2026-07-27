const std = @import("std");

pub const Rational = struct {
    numerator: i32,
    denominator: i32,

    pub const one: Rational = .{ .numerator = 1, .denominator = 1 };

    pub fn asFloat(self: Rational) ?f64 {
        if (self.denominator == 0) return null;
        return @as(f64, @floatFromInt(self.numerator)) /
            @as(f64, @floatFromInt(self.denominator));
    }

    pub fn parse(value: []const u8) ?Rational {
        const slash = std.mem.indexOfScalar(u8, value, '/') orelse {
            const number = std.fmt.parseInt(i32, value, 10) catch return null;
            return .{ .numerator = number, .denominator = 1 };
        };
        const numerator = std.fmt.parseInt(i32, value[0..slash], 10) catch return null;
        const denominator = std.fmt.parseInt(i32, value[slash + 1 ..], 10) catch return null;
        return .{ .numerator = numerator, .denominator = denominator };
    }

    pub fn fromUnsigned(numerator: u32, denominator: u32) Rational {
        return .{
            .numerator = @intCast(numerator),
            .denominator = @intCast(denominator),
        };
    }
};
