# Process Operations Backlog

Offline (process-backed) builders to add when Ember needs them. Pattern matches existing
`AudioExtraction` / `ScreenshotExtraction`: fluent setters, validate/build/run, argv unit tests
without spawning FFmpeg.

| Operation | Status | Notes |
|---|---|---|
| `probe` | done | ffprobe JSON |
| `audioExtraction` | done | |
| `screenshotExtraction` | done | single-process multi-output |
| `transcode` | stub | video+audio re-encode builder |
| `trim` | stub | clip by timestamps |
| `remux` | stub | container copy / MP4 faststart |
| `hlsPackaging` | planned | segment + playlist |
| `thumbnail` | planned | may share screenshot batching |

Stub modules under `src/operations/` document the intended public surface; implement when an
Ember vertical slice requires them.
