const c = @import("ffmpeg_c");
const formats = @import("../formats/root.zig");
const time = @import("../time.zig");

const Rational = formats.Rational;
const Timestamp = time.Timestamp;

/// Owned compressed packet. Caller must `deinit`.
pub const Packet = struct {
    stream_index: u32,
    pts: Timestamp,
    dts: Timestamp,
    is_key_frame: bool,
    raw: ?*c.AVPacket,

    pub fn deinit(self: *Packet) void {
        if (self.raw) |pkt| {
            var tmp: [*c]c.AVPacket = pkt;
            c.av_packet_free(&tmp);
            self.raw = null;
        }
        self.* = undefined;
    }

    pub fn fromAv(pkt: *c.AVPacket, time_base: Rational) Packet {
        return .{
            .stream_index = @intCast(pkt.stream_index),
            .pts = Timestamp.fromPts(pkt.pts, time_base),
            .dts = Timestamp.fromPts(pkt.dts, time_base),
            .is_key_frame = (pkt.flags & c.AV_PKT_FLAG_KEY) != 0,
            .raw = pkt,
        };
    }
};
