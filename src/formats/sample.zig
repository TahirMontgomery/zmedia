pub const SampleFormat = enum {
    unknown,
    u8,
    s16,
    s32,
    flt,
    dbl,
    u8p,
    s16p,
    s32p,
    fltp,
    dblp,

    pub fn name(self: SampleFormat) []const u8 {
        return @tagName(self);
    }
};
