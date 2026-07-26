const std = @import("std");
const zmedia = @import("zmedia");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        std.debug.print("Usage: probe <input>\n", .{});
        return error.MissingArguments;
    }

    var info = try zmedia.probe(allocator, io, args[1], .{});
    defer info.deinit(allocator);

    if (info.duration) |duration| {
        const formatted = try duration.formatAlloc(allocator);
        defer allocator.free(formatted);
        std.debug.print("Duration: {s}\n", .{formatted});
    }

    if (info.format_name) |format_name| {
        std.debug.print("Format: {s}\n", .{format_name});
    }

    std.debug.print("Video streams: {d}\n", .{info.video_streams.len});
    std.debug.print("Audio streams: {d}\n", .{info.audio_streams.len});
}
