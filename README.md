# ZMedia

Typed FFmpeg wrapper for Zig.

ZMedia wraps the `ffmpeg` and `ffprobe` command-line tools with operation-specific builders, typed options, validation, and structured process results.

Requires **Zig 0.16** and a local FFmpeg/FFprobe installation for process execution.

## Features

- Typed builders for audio extraction, screenshot extraction, and media probing
- Safe argument-list command construction (not shell strings)
- Validation before FFmpeg starts
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

    if (!screenshot_results.succeeded()) {
        return error.ScreenshotExtractionFailed;
    }
}
```

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
  Audio: aac, 44100 Hz, stereo

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
| `screenshotExtraction(path)` | timestamps, format, quality, outputDirectory, prefix, overwrite |
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
