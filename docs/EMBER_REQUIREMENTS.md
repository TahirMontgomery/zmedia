# Ember Studio Requirements for zmedia

Consumer-driven requirements extracted from Ember Studio PRD v0.2.
This is not a full zmedia design doc — it records what Ember needs from this library.

## Boundary

**zmedia owns** all FFmpeg interaction: process ops, library bindings, frames/packets,
decode/encode/mux, capture abstractions, timestamps, media errors, capability discovery.

**Ember owns** GPU composition, UI, mixer policy (gain/mute/metering), project state.

```text
Ember Studio
      ↓
zmedia public API
      ↓
FFmpeg libraries and CLI tools
```

## Dual workload model

1. **Process-backed** — offline jobs spawn `ffmpeg` / `ffprobe` (probe, extract, screenshots, later transcode/remux/HLS).
2. **Library-backed** — interactive pipelines use libav* (`MediaInput`, decoders, frames).

## Phased deliverables (zmedia)

| Phase | Focus |
|---|---|
| 0 | Foundation: process ops stable, FFmpeg link, package boundaries |
| 1 | Native `MediaInput` + stream discovery (no process spawn) |
| 2 | Video decode → owned/borrowed `VideoFrame` (Ember GPU upload milestone) |
| 3 | Audio decode + resampler APIs |
| 4+ | Capture, encode, record, stream — only as Ember vertical slices demand |

## Constraints

1. zmedia owns all FFmpeg interaction.
2. Support both process-backed and library-backed APIs.
3. Prefer process-backed for offline jobs.
4. Require library-backed APIs for interactive pipelines.
5. Do not leak FFmpeg C types into the public API.
6. Grow the API from real Ember needs, not a full media graph upfront.
7. Keep frame/packet ownership explicit and documented.

## Immediate joint milestone

Open a media file through zmedia’s native FFmpeg runtime and decode video frames with
clear ownership and timestamps so Ember can upload them to a GPU texture.
