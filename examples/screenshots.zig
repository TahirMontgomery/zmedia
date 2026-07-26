const std = @import("std");
const zmedia = @import("zmedia");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 3) {
        std.debug.print("Usage: screenshots <input> <output-dir>\n", .{});
        return error.MissingArguments;
    }

    const timestamps = [_]zmedia.Timestamp{
        zmedia.Timestamp.fromSeconds(1),
        zmedia.Timestamp.fromSeconds(2),
        zmedia.Timestamp.fromSeconds(3),
    };

    var job = zmedia.screenshotExtraction(args[1]);
    var result = try job
        .timestamps(&timestamps)
        .format(.jpeg)
        .quality(.high)
        .outputDirectory(args[2])
        .prefix("frame")
        .overwrite(true)
        .run(allocator, io);
    defer result.deinit(allocator);

    try result.expectSuccess();
    std.debug.print("Wrote {d} screenshots to {s}\n", .{ result.items.len, args[2] });
}
