# FFmpeg Policy

## Supported versions

zmedia targets **FFmpeg 6.x and 7.x** libraries (`libavformat`, `libavcodec`, `libavutil`, `libswresample`).

Development is validated against Homebrew FFmpeg 7.1 on macOS. CI installs distro FFmpeg
development packages on Ubuntu and Homebrew FFmpeg on macOS runners.

## Installation (macOS)

```bash
brew install ffmpeg pkg-config
pkg-config --modversion libavformat
```

## Installation (Ubuntu / Debian)

```bash
sudo apt-get install -y \
  ffmpeg \
  libavformat-dev \
  libavcodec-dev \
  libavutil-dev \
  libswresample-dev \
  pkg-config
```

## Build options

```bash
zig build                          # link FFmpeg (default)
zig build -Dlink-ffmpeg=true
zig build -Dffmpeg-include=/path/to/include -Dffmpeg-lib=/path/to/lib
zig build ffmpeg-test              # library-backed runtime tests
zig build integration-test         # CLI + library tests
```

Paths are auto-detected via `pkg-config`, then common Homebrew/system prefixes.

## Bindings

C headers are translated through [`src/internal/bindings/ffmpeg.h`](../src/internal/bindings/ffmpeg.h).
The generated module is imported as `ffmpeg_c` and must never be re-exported from the public API.
