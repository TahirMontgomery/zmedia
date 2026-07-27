pub const ChannelLayout = enum {
    unknown,
    mono,
    stereo,
    surround_5_1,
    surround_7_1,

    pub fn channelCount(self: ChannelLayout) u8 {
        return switch (self) {
            .unknown => 0,
            .mono => 1,
            .stereo => 2,
            .surround_5_1 => 6,
            .surround_7_1 => 8,
        };
    }

    pub fn name(self: ChannelLayout) []const u8 {
        return @tagName(self);
    }
};
