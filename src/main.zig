const std = @import("std");
const Io = std.Io;
const zmedia = @import("zmedia");

const CliOptions = struct {
    input_path: []const u8,
    audio_output: ?[]const u8 = null,
    screenshot_spec: ?[]const u8 = null,
    screenshot_directory: []const u8 = "output/screenshots",
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const options = parseArgs(args) catch |err| {
        try printUsage(stderr);
        try stderr.flush();
        return err;
    };

    const started = Io.Timestamp.now(io, .awake);

    try stdout.print("Inspecting {s}...\n\n", .{options.input_path});
    try stdout.flush();

    var info = try zmedia.probe(allocator, io, options.input_path, .{});
    defer info.deinit(allocator);

    try printMediaSummary(stdout, &info);
    try stdout.print("\nProcessing\n", .{});
    try stdout.flush();

    if (options.audio_output) |audio_output| {
        if (std.fs.path.dirname(audio_output)) |directory| {
            try Io.Dir.cwd().createDirPath(io, directory);
        }

        var extraction = zmedia.audioExtraction(options.input_path);
        var result = try extraction
            .codec(.mp3)
            .bitrate(.{ .kbps = 192 })
            .overwrite(true)
            .output(audio_output)
            .run(allocator, io);
        defer result.deinit(allocator);

        if (result.succeeded()) {
            try stdout.print("  ✓ Extracted audio to {s}\n", .{audio_output});
        } else {
            try stdout.print("  ✗ Failed to extract audio to {s}\n", .{audio_output});
            const process = result.process();
            if (process.stderr.len > 0) {
                try stderr.print("{s}\n", .{process.stderr});
            }
        }
        try stdout.flush();
        try stderr.flush();
    }

    if (options.screenshot_spec) |spec| {
        const timestamps = try parseTimestampList(allocator, spec);
        defer allocator.free(timestamps);

        var screenshots = zmedia.screenshotExtraction(options.input_path);
        var batch = try screenshots
            .timestamps(timestamps)
            .format(.jpeg)
            .quality(.high)
            .outputDirectory(options.screenshot_directory)
            .prefix("frame")
            .overwrite(true)
            .run(allocator, io);
        defer batch.deinit(allocator);

        for (batch.items) |item| {
            const formatted = try item.timestamp.formatAlloc(allocator);
            defer allocator.free(formatted);

            if (item.process.succeeded()) {
                try stdout.print("  ✓ Captured screenshot at {s}\n", .{formatted});
            } else {
                try stdout.print("  ✗ Failed screenshot at {s}\n", .{formatted});
            }
        }
        try stdout.flush();
    }

    const finished = Io.Timestamp.now(io, .awake);
    const elapsed = started.durationTo(finished);
    const seconds = @as(f64, @floatFromInt(elapsed.nanoseconds)) /
        @as(f64, @floatFromInt(std.time.ns_per_s));

    try stdout.print("\nCompleted in {d:.2} seconds\n", .{seconds});
    try stdout.flush();
}

fn parseArgs(args: []const []const u8) !CliOptions {
    if (args.len < 2) {
        return error.MissingInputPath;
    }

    var options = CliOptions{
        .input_path = args[1],
    };

    var index: usize = 2;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--audio")) {
            index += 1;
            if (index >= args.len) return error.MissingAudioOutput;
            options.audio_output = args[index];
        } else if (std.mem.eql(u8, arg, "--screenshots")) {
            index += 1;
            if (index >= args.len) return error.MissingScreenshotSpec;
            options.screenshot_spec = args[index];
        } else if (std.mem.eql(u8, arg, "--screenshot-dir")) {
            index += 1;
            if (index >= args.len) return error.MissingScreenshotDirectory;
            options.screenshot_directory = args[index];
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.HelpRequested;
        } else {
            return error.UnknownArgument;
        }
    }

    if (options.audio_output == null and options.screenshot_spec == null) {
        return error.NoOperationsRequested;
    }

    return options;
}

fn printUsage(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\Usage: zmedia-process <input> --audio <output.mp3> --screenshots 5s,20s,1m15s
        \\
        \\Options:
        \\  --audio <path>           Extract audio to the given path
        \\  --screenshots <list>     Comma-separated timestamps (5s, 1m15s, 1h2m3s)
        \\  --screenshot-dir <path>  Screenshot output directory (default: output/screenshots)
        \\
    );
}

fn printMediaSummary(writer: *Io.Writer, info: *const zmedia.MediaInfo) !void {
    try writer.writeAll("Media\n");

    if (info.duration) |duration| {
        // formatAlloc needs an allocator; print components manually for the CLI summary.
        const total_seconds = duration.microseconds / std.time.us_per_s;
        const remainder_us = duration.microseconds % std.time.us_per_s;
        const hours = total_seconds / 3600;
        const minutes = (total_seconds % 3600) / 60;
        const seconds = total_seconds % 60;
        const milliseconds = remainder_us / std.time.us_per_ms;
        try writer.print(
            "  Duration: {d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}\n",
            .{ hours, minutes, seconds, milliseconds },
        );
    } else {
        try writer.writeAll("  Duration: unknown\n");
    }

    if (info.video_streams.len > 0) {
        const video = info.video_streams[0];
        if (video.width) |width| {
            if (video.height) |height| {
                try writer.print("  Video: {s}, {d}x{d}\n", .{ video.codec_name, width, height });
            } else {
                try writer.print("  Video: {s}\n", .{video.codec_name});
            }
        } else {
            try writer.print("  Video: {s}\n", .{video.codec_name});
        }
    } else {
        try writer.writeAll("  Video: none\n");
    }

    if (info.audio_streams.len > 0) {
        const audio_stream = info.audio_streams[0];
        try writer.print("  Audio: {s}", .{audio_stream.codec_name});
        if (audio_stream.sample_rate) |sample_rate| {
            try writer.print(", {d} Hz", .{sample_rate});
        }
        if (audio_stream.channel_layout) |layout| {
            try writer.print(", {s}", .{layout});
        } else if (audio_stream.channels) |channels| {
            const label = switch (channels) {
                1 => "mono",
                2 => "stereo",
                else => "channels",
            };
            if (channels == 1 or channels == 2) {
                try writer.print(", {s}", .{label});
            } else {
                try writer.print(", {d} channels", .{channels});
            }
        }
        try writer.writeAll("\n");
    } else {
        try writer.writeAll("  Audio: none\n");
    }
}

fn parseTimestampList(allocator: std.mem.Allocator, spec: []const u8) ![]zmedia.Timestamp {
    var list: std.ArrayList(zmedia.Timestamp) = .empty;
    errdefer list.deinit(allocator);

    var iterator = std.mem.splitScalar(u8, spec, ',');
    while (iterator.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;
        try list.append(allocator, try parseTimestampToken(trimmed));
    }

    if (list.items.len == 0) {
        return error.NoTimestamps;
    }

    return try list.toOwnedSlice(allocator);
}

fn parseTimestampToken(token: []const u8) !zmedia.Timestamp {
    if (std.mem.endsWith(u8, token, "ms")) {
        const number = try std.fmt.parseInt(u64, token[0 .. token.len - 2], 10);
        return zmedia.Timestamp.fromMilliseconds(number);
    }

    var hours: u64 = 0;
    var minutes: u64 = 0;
    var seconds: u64 = 0;
    var rest = token;

    if (std.mem.indexOfScalar(u8, rest, 'h')) |h_index| {
        hours = try std.fmt.parseInt(u64, rest[0..h_index], 10);
        rest = rest[h_index + 1 ..];
    }

    if (std.mem.indexOfScalar(u8, rest, 'm')) |m_index| {
        minutes = try std.fmt.parseInt(u64, rest[0..m_index], 10);
        rest = rest[m_index + 1 ..];
    }

    if (rest.len == 0) {
        return zmedia.Timestamp.fromHoursMinutesSeconds(hours, minutes, 0);
    }

    if (std.mem.endsWith(u8, rest, "s")) {
        seconds = try std.fmt.parseInt(u64, rest[0 .. rest.len - 1], 10);
    } else {
        seconds = try std.fmt.parseInt(u64, rest, 10);
    }

    return zmedia.Timestamp.fromHoursMinutesSeconds(hours, minutes, seconds);
}
