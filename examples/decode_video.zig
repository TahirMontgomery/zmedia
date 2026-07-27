const std = @import("std");
const zmedia = @import("zmedia");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        std.debug.print("Usage: decode_video <input> [max_frames]\n", .{});
        return error.MissingArguments;
    }

    const max_frames: usize = if (args.len >= 3)
        try std.fmt.parseInt(usize, args[2], 10)
    else
        5;

    var input = try zmedia.MediaInput.open(allocator, args[1]);
    defer input.deinit();

    const video_index = input.firstStreamOfKind(.video) orelse {
        std.debug.print("No video stream found\n", .{});
        return error.StreamNotFound;
    };

    var decoder = try zmedia.VideoDecoder.init(allocator, &input, video_index);
    defer decoder.deinit();

    var count: usize = 0;
    while (count < max_frames) : (count += 1) {
        var frame = try decoder.nextFrame() orelse break;
        defer frame.deinit();

        const ts = try frame.timestamp.formatAlloc(allocator);
        defer allocator.free(ts);

        std.debug.print(
            "frame {d}: {d}x{d} format={s} ts={s} planes={d}\n",
            .{
                count,
                frame.width,
                frame.height,
                @tagName(frame.format),
                ts,
                frame.planes.len,
            },
        );
    }

    std.debug.print("Decoded {d} frame(s)\n", .{count});
}
