# ZMedia

Typed FFmpeg wrapper for Zig.

ZMedia wraps the `ffmpeg` and `ffprobe` command-line tools with operation-specific builders, typed options, validation, and structured process results.

Requires **Zig 0.16** and a local FFmpeg/FFprobe installation for process execution.

## Features

- Typed builders for audio extraction, screenshot extraction, and media probing
- Safe argument-list command construction (not shell strings)
- Validation before FFmpeg starts
- Single-process multi-output screenshot extraction
- `Runtime` execution seam with configurable binary paths and stream capture
- Structured stdout/stderr/exit-code/elapsed-time results
- Unit tests that do not require FFmpeg
- Integration tests and a sample video workflow CLI

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

## Quick start

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

    const timestamps = [_]zmedia.Timestamp{
        zmedia.Timestamp.fromSeconds(5),
        zmedia.Timestamp.fromSeconds(20),
        zmedia.Timestamp.fromMinutesSeconds(1, 15),
    };

    var screenshots = zmedia.screenshotExtraction("video.mp4");
    var screenshot_results = try screenshots
        .timestamps(&timestamps)
        .format(.jpeg)
        .quality(.high)
        .outputDirectory("output/screenshots")
        .prefix("frame")
        .overwrite(true)
        .run(allocator, io);
    defer screenshot_results.deinit(allocator);
    try screenshot_results.expectSuccess();
}
```

## Runtime and capture defaults

`.run(allocator, io)` uses `Runtime.init(io, .{})`. For custom binary paths or capture settings, use `.runWith`:

```zig
const runtime = zmedia.Runtime.init(io, .{
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

Example output:

```text
Inspecting fixtures/sample.mp4...

Media
  Duration: 00:00:05.000
  Video: h264, 320x240
  Audio: aac, 44100 Hz, mono

Processing
  ✓ Extracted audio to output/audio.mp3
  ✓ Captured screenshot at 00:00:01.000
  ✓ Captured screenshot at 00:00:02.000
  ✓ Captured screenshot at 00:00:03.000

Completed in 0.42 seconds
```

## Inspect generated commands

```zig
var job = zmedia.audioExtraction("video.mp4");
_ = job.codec(.mp3).bitrate(.{ .kbps = 192 }).output("audio.mp3");

var command = try job.build(allocator, .{});
defer command.deinit();

const rendered = try command.renderAlloc(allocator);
defer allocator.free(rendered);
// e.g. ffmpeg -n -i video.mp4 -vn -c:a libmp3lame -b:a 192k audio.mp3
```

## Check installation

```zig
var info = try zmedia.checkInstallation(allocator, io, .{});
defer info.deinit(allocator);
```

## Testing

```text
zig build test              # unit tests, no FFmpeg required
zig build integration-test  # requires ffmpeg + ffprobe on PATH
```

## Examples

```text
zig build run-extract_audio -- fixtures/sample.mp4 output/audio.mp3
zig build run-screenshots -- fixtures/sample.mp4 output/screenshots
zig build run-probe -- fixtures/sample.mp4
zig build run-process_video -- fixtures/sample.mp4
```

## API overview

| Constructor | Builder |
|---|---|
| `audioExtraction(path)` | codec, bitrate, channels, sampleRate, overwrite, output |
| `screenshotExtraction(path)` | timestamps, format, quality, outputDirectory, prefix, overwrite, rejectDuplicates |
| `probe(allocator, io, path, config)` | returns `MediaInfo` |

Custom binary paths:

```zig
const config = zmedia.RuntimeConfig{
    .ffmpeg_path = "/opt/homebrew/bin/ffmpeg",
    .ffprobe_path = "/opt/homebrew/bin/ffprobe",
};
```

## Non-goals for v0

- Direct libav bindings
- Arbitrary filter graphs
- Live RTMP processing
- Hardware acceleration
- Modeling every FFmpeg codec/container

## License

MIT
