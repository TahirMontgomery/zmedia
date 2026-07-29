# ZMedia

Typed FFmpeg wrapper for Zig.

ZMedia supports a dual workload model:

1. **Process-backed** — offline jobs spawn `ffmpeg` / `ffprobe` (probe, extract, screenshots; stubs for transcode/trim/remux).
2. **Library-backed** — interactive pipelines use linked libav* (`MediaInput`, decoders, frames).

Requires **Zig 0.16**. Process ops need CLI tools on `PATH`. Library runtime needs FFmpeg 6.x/7.x development libraries (default: `-Dlink-ffmpeg=true`).

See [docs/EMBER_REQUIREMENTS.md](docs/EMBER_REQUIREMENTS.md) and [docs/FFMPEG_POLICY.md](docs/FFMPEG_POLICY.md).

## Features

- Typed builders for audio extraction, screenshot extraction, and media probing
- Native `MediaInput` + `VideoDecoder` / `AudioDecoder` (no process spawn)
- `VideoConverter` (libswscale) for YUV/NV12 → packed RGBA
- Explicit frame ownership ([docs/FRAME_LIFETIME.md](docs/FRAME_LIFETIME.md))
- Safe argument-list command construction (not shell strings)
- Validation before FFmpeg starts
- Single-process multi-output screenshot extraction
- `ProcessRuntime` execution seam with configurable binary paths and stream capture
- Structured stdout/stderr/exit-code/elapsed-time results
- Unit tests; integration + library runtime tests when FFmpeg is available

## Install

Add the dependency with the Zig package manager, then import it:

```zig
const zmedia = @import("zmedia");
```

In your `build.zig`:

```zig
const zmedia = b.dependency("zmedia", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zmedia", zmedia.module("zmedia"));
```

## Quick start (process ops)

Zig 0.16 process execution requires an `std.Io` value. Typical programs receive one from `std.process.Init`.

```zig
const std = @import("std");
const zmedia = @import("zmedia");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var info = try zmedia.probe(allocator, io, "video.mp4", .{});
    defer info.deinit(allocator);

    var audio = zmedia.audioExtraction("video.mp4");
    var audio_result = try audio
        .codec(.mp3)
        .bitrate(.{ .kbps = 192 })
        .overwrite(true)
        .output("output/audio.mp3")
        .run(allocator, io);
    defer audio_result.deinit(allocator);
    try audio_result.expectSuccess();
}
```

## Quick start (library runtime)

```zig
var input = try zmedia.MediaInput.open(allocator, "video.mp4");
defer input.deinit();

const video_index = input.firstStreamOfKind(.video).?;
var decoder = try zmedia.VideoDecoder.init(allocator, &input, video_index);
defer decoder.deinit();

while (try decoder.nextFrame()) |*frame| {
    defer frame.deinit();
    // upload frame.planes to GPU — see docs/FRAME_LIFETIME.md
}
```

## ProcessRuntime and capture defaults

`.run(allocator, io)` uses `ProcessRuntime.init(io, .{})`. For custom binary paths or capture settings, use `.runWith`:

```zig
const runtime = zmedia.ProcessRuntime.init(io, .{
    .ffmpeg_path = "/opt/homebrew/bin/ffmpeg",
    .ffprobe_path = "/opt/homebrew/bin/ffprobe",
    .capture_stdout = false, // default
    .capture_stderr = true,  // default
});

var result = try job.runWith(allocator, runtime);
```

Defaults discard stdout (ffmpeg writes media to files) and keep stderr for diagnostics. Probe and installation checks enable stdout capture automatically.

## Screenshots: one process, many outputs

Screenshot extraction builds a single multi-output ffmpeg command:

```text
ffmpeg -y -i video.mp4 \
  -ss 00:00:05.000 -frames:v 1 -c:v mjpeg -q:v 3 screenshots/frame-001.jpg \
  -ss 00:00:20.000 -frames:v 1 -c:v mjpeg -q:v 3 screenshots/frame-002.jpg
```

The batch result holds one shared `ProcessResult` plus per-frame `written` flags.

## CLI: `zmedia-process`

```text
zig build
zig-out/bin/zmedia-process fixtures/sample.mp4 \
  --audio output/audio.mp3 \
  --screenshots 1s,2s,3s
```

## Testing

```text
zig build test              # unit + module tests (links FFmpeg by default)
zig build ffmpeg-test       # library-backed runtime tests
zig build integration-test  # process CLI + library runtime tests
```

Install FFmpeg libs per [docs/FFMPEG_POLICY.md](docs/FFMPEG_POLICY.md).

## Examples

```text
zig build run-extract_audio -- fixtures/sample.mp4 output/audio.mp3
zig build run-screenshots -- fixtures/sample.mp4 output/screenshots
zig build run-probe -- fixtures/sample.mp4
zig build run-process_video -- fixtures/sample.mp4
zig build run-decode_video -- fixtures/sample.mp4
```

## API overview

| Surface | Notes |
|---|---|
| `audioExtraction` / `screenshotExtraction` | process builders |
| `probe` / `checkInstallation` | process / ffprobe |
| `ProcessRuntime` / `ProcessConfig` | CLI execution seam |
| `MediaInput` / `VideoDecoder` / `AudioDecoder` | library runtime |
| `AudioResampler` | libswresample wrapper |
| `Transcode` / `Trim` / `Remux` | stubs — see [docs/PROCESS_OPS_BACKLOG.md](docs/PROCESS_OPS_BACKLOG.md) |

Custom binary paths:

```zig
const config = zmedia.ProcessConfig{
    .ffmpeg_path = "/opt/homebrew/bin/ffmpeg",
    .ffprobe_path = "/opt/homebrew/bin/ffprobe",
};
```

## Non-goals (near-term)

- Arbitrary filter graphs
- Live RTMP processing
- Hardware acceleration
- Modeling every FFmpeg codec/container
- Full offline transcode/HLS before Ember needs them

## License

MIT
