//! Library-backed FFmpeg runtime tests (requires linked libav*).
const std = @import("std");
const zmedia = @import("zmedia");

test "av_version_info smoke" {
    const version = zmedia.runtime.ffmpegVersion();
    try std.testing.expect(version.len > 0);
}

test "MediaInput opens fixture and lists streams" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const streams = input.streamInfos();
    try std.testing.expect(streams.len >= 1);
    try std.testing.expect(input.firstStreamOfKind(.video) != null);
}

test "VideoDecoder yields at least one frame" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const video_index = input.firstStreamOfKind(.video) orelse return error.SkipZigTest;
    var decoder = try zmedia.VideoDecoder.init(std.testing.allocator, &input, video_index);
    defer decoder.deinit();

    var frame = try decoder.nextFrame() orelse return error.TestUnexpectedResult;
    defer frame.deinit();

    try std.testing.expect(frame.width > 0);
    try std.testing.expect(frame.height > 0);
    try std.testing.expect(frame.planes.len > 0);
}

test "AudioDecoder yields at least one frame" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const audio_index = input.firstStreamOfKind(.audio) orelse return error.SkipZigTest;
    var decoder = try zmedia.AudioDecoder.init(std.testing.allocator, &input, audio_index);
    defer decoder.deinit();

    var frame = try decoder.nextFrame() orelse return error.TestUnexpectedResult;
    defer frame.deinit();

    try std.testing.expect(frame.sample_count > 0);
    try std.testing.expect(frame.data.len > 0);
    try std.testing.expect(frame.sample_rate > 0);
}

test "AudioResampler converts decoded audio" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();

    const audio_index = input.firstStreamOfKind(.audio) orelse return error.SkipZigTest;
    var decoder = try zmedia.AudioDecoder.init(std.testing.allocator, &input, audio_index);
    defer decoder.deinit();

    var frame = try decoder.nextFrame() orelse return error.TestUnexpectedResult;
    defer frame.deinit();

    var resampler = try zmedia.AudioResampler.init(
        48_000,
        .s16,
        .stereo,
        frame.sample_rate,
        frame.format,
        frame.channel_layout,
    );
    defer resampler.deinit();

    var converted = try resampler.convert(std.testing.allocator, &frame);
    defer converted.deinit();

    try std.testing.expectEqual(@as(u32, 48_000), converted.sample_rate);
    try std.testing.expect(converted.format == .s16);
    try std.testing.expect(converted.channel_layout == .stereo);
    try std.testing.expect(converted.sample_count > 0);
}

test "openWithOptions pre-cancelled token returns Cancelled" {
    var cancel = zmedia.CancelToken.init();
    cancel.requestCancel();

    const result = zmedia.MediaInput.openWithOptions(std.testing.allocator, "fixtures/sample.mp4", .{
        .cancel = &cancel,
    });
    try std.testing.expectError(error.Cancelled, result);
}

test "openWithOptions cancel during hanging tcp open" {
    const listener = try listenLocalhost();
    defer _ = std.c.close(listener.fd);

    var url_buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "tcp://127.0.0.1:{d}", .{listener.port});

    var cancel = zmedia.CancelToken.init();
    const Ctx = struct {
        path: []const u8,
        cancel: *zmedia.CancelToken,
        err: ?anyerror = null,
    };
    var ctx: Ctx = .{
        .path = url,
        .cancel = &cancel,
    };

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(c: *Ctx) void {
            var input = zmedia.MediaInput.openWithOptions(std.testing.allocator, c.path, .{
                .cancel = c.cancel,
            }) catch |err| {
                c.err = err;
                return;
            };
            input.deinit();
        }
    }.run, .{&ctx});

    sleepMs(100);
    cancel.requestCancel();
    thread.join();

    try std.testing.expect(ctx.err != null);
    try std.testing.expect(ctx.err.? == error.Cancelled);
}

test "openWithOptions timeout during hanging tcp open" {
    const listener = try listenLocalhost();
    defer _ = std.c.close(listener.fd);

    var url_buf: [64]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "tcp://127.0.0.1:{d}", .{listener.port});

    const result = zmedia.MediaInput.openWithOptions(std.testing.allocator, url, .{
        .timeout_ns = 100 * std.time.ns_per_ms,
    });
    try std.testing.expectError(error.TimedOut, result);
}

test "open still works without options" {
    var input = try zmedia.MediaInput.open(std.testing.allocator, "fixtures/sample.mp4");
    defer input.deinit();
    try std.testing.expect(input.streamInfos().len >= 1);
}

const Listener = struct {
    fd: std.c.fd_t,
    port: u16,
};

fn listenLocalhost() !Listener {
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);
    if (fd < 0) return error.SocketError;
    errdefer _ = std.c.close(fd);

    var yes: c_int = 1;
    _ = std.c.setsockopt(
        fd,
        std.c.SOL.SOCKET,
        std.c.SO.REUSEADDR,
        &yes,
        @sizeOf(c_int),
    );

    var addr = std.c.sockaddr.in{
        .port = 0,
        .addr = std.mem.nativeToBig(u32, 0x7f000001),
    };
    if (std.c.bind(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr))) != 0) {
        return error.BindFailed;
    }
    if (std.c.listen(fd, 1) != 0) return error.ListenFailed;

    var len: std.c.socklen_t = @sizeOf(std.c.sockaddr.in);
    if (std.c.getsockname(fd, @ptrCast(&addr), &len) != 0) return error.GetSockNameFailed;

    return .{
        .fd = fd,
        .port = std.mem.bigToNative(u16, addr.port),
    };
}

fn sleepMs(ms: u64) void {
    const ts = std.c.timespec{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    _ = std.c.nanosleep(&ts, null);
}
