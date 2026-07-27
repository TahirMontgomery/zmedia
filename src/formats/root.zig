//! Shared typed format / time abstractions used by process and library runtimes.
pub const Rational = @import("rational.zig").Rational;
pub const PixelFormat = @import("pixel.zig").PixelFormat;
pub const SampleFormat = @import("sample.zig").SampleFormat;
pub const ChannelLayout = @import("channel.zig").ChannelLayout;
