const std = @import("std");
const zmedia = @import("zmedia");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 3) {
        std.debug.print("Usage: extract_audio <input> <output.mp3>\n", .{});
        return error.MissingArguments;
    }

    var job = zmedia.audioExtraction(args[1]);
    var result = try job
        .codec(.mp3)
        .bitrate(.{ .kbps = 192 })
        .overwrite(true)
        .output(args[2])
        .run(allocator, io);
    defer result.deinit(allocator);

    try result.expectSuccess();
    std.debug.print("Wrote {s}\n", .{args[2]});
}
