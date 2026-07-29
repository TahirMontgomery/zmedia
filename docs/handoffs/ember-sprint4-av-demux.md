# Ember handoff — Sprint 4 A/V demux + audio drain

**From:** Ember Studio  
**To:** zmedia  
**Baseline:** v0.4.0  
**Date:** 2026-07-28

## Shipped

1. **`Demuxer`** — single `av_read_frame` cursor; optional `CancelToken`
2. **Packet-driven decode** — `sendPacket` (borrow) / `sendFlush` / `receiveFrame` on video+audio
3. **`nextFrame`** — single-stream convenience only (two consumers on one `MediaInput` unsupported)
4. **`AudioResampler.flush` / `flushInto` / `convertInto`** — drain delay samples; hot-path reuse
5. Flush timestamps use **last input PTS** (documented)

See `docs/FRAME_LIFETIME.md` and `docs/CHANGELOG.md`.
