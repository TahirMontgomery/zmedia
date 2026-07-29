# Changelog

## 0.4.0 — 2026-07-28

### Added
- `VideoConverter` (libswscale): `init` / `deinit` / `convert` / `convertInto`, plus
  `dstByteLength` and `convertVideoFrame`.
- Sprint 3 handoff notes under `docs/handoffs/ember-sprint3-video-convert.md`.
- Fixture `fixtures/sample_yuv420p.mp4` for converter tests.

### Fixed
- `VideoFrame` plane byte lengths for yuv422p / yuv444p / packed formats (no longer assumes
  4:2:0 chroma height for every planar format).

### Docs
- `FRAME_LIFETIME.md` documents borrowed decode vs owned convert frames and plane sizing.
