# Ember handoff — Sprint 3 video convert + frame planes

**From:** Ember Studio (`montgomery_labs/ember/studio`)  
**To:** zmedia  
**zmedia baseline:** `v0.3.0`  
**Date:** 2026-07-28  
**Priority:** P0 converter; P1 plane-size correctness

Cancel/open APIs are out of scope (already in 0.3.0).

## Shipped

1. **Plane sizes** — `videoFromAv` uses `av_image_fill_plane_sizes` / pixfmt chroma logs so yuv420p / yuv422p / yuv444p / nv12 / packed RGB lengths are correct.
2. **`VideoConverter`** — libswscale wrapper: `init` / `deinit` / `convert` / `convertInto` / `dstByteLength` / `convertVideoFrame`.
3. Destination for Ember: packed non-premultiplied **RGBA8**, `line_size == width * 4`, alpha 255 from opaque YUV.
4. Color default: limited-range **BT.601** via swscale defaults (documented on the type).

## Ember pipeline

```text
MediaInput.openWithOptions → VideoDecoder.nextFrame → VideoConverter.convert(Into) → preview upload
```

Ember deletes `src/yuv_rgba.zig` after depending on this release.
