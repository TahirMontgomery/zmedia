# VideoFrame / AudioFrame / Packet Lifetime

## Shared demux (A/V)

For files with both video and audio, use **`Demuxer`** + packet-driven decode:

```text
Demuxer.nextPacket → Packet
  → VideoDecoder.sendPacket / AudioDecoder.sendPacket  (borrow)
  → receiveFrame until null
Packet.deinit (caller)
… EOS …
sendFlush → receiveFrame until null
AudioResampler.flush → drain delay samples
```

- **One demux cursor** per `MediaInput`. Do not run two `nextFrame` consumers, or a
  `Demuxer` plus `nextFrame`, on the same open input — they share `av_read_frame` and
  will drop each other’s packets.
- `nextFrame` remains a **single-stream convenience** (video-only or audio-only apps).

### Packet ownership

`sendPacket` **borrows** the packet for the duration of the call. The caller keeps the
`Packet` alive through `sendPacket` and then calls `Packet.deinit`. The decoder does not
take ownership or free the caller’s `AVPacket`.

If `sendPacket` / `sendFlush` returns `error.WouldBlock`, drain with `receiveFrame` and
retry the send.

## VideoFrame (decoded)

`VideoDecoder.receiveFrame` / `nextFrame` returns a `VideoFrame` whose pixel planes borrow
memory from an internal `AVFrame` (`FrameStorage.borrowed_avframe`).

Rules:

1. Call `frame.deinit()` when finished.
2. Plane pointers are invalid after `deinit`.
3. Multiple outstanding borrowed frames from separate `AVFrame` allocations are allowed;
   each must still be freed.

### Plane sizing

`Plane.data.len` is the usable byte length for that plane (including row padding implied by
`line_size × plane_height`). Heights/widths follow the pixel format’s chroma subsampling
(`av_image_fill_plane_sizes` / `log2_chroma_*`):

| Format | Luma | Chroma height | Notes |
|---|---|---|---|
| `yuv420p` / `nv12` | H | H/2 | nv12: semi-planar UV in plane 1 |
| `yuv422p` | H | H | chroma width W/2 |
| `yuv444p` | H | H | full chroma |
| `rgba` / `rgb24` / … | H | n/a | single packed plane |

`line_size` may be larger than the active row width (alignment padding). Prefer
`plane.data.len` for bounds checks; use `line_size` for row strides.

## VideoFrame (converted)

`VideoConverter.convert` returns an **owned** frame. Valid after source `deinit`.

## AudioFrame

Decoded and resampled audio frames use **owned** bytes. Valid across subsequent
`receiveFrame` / `convert` calls until `deinit`.

`AudioResampler.flush` returns owned frames (or null when drained). Flush timestamps use
the **last input PTS**. After a final null flush, further flush returns null.

`convertInto` / `flushInto` write into caller buffers (`ConvertIntoResult`).

## Ownership summary

| Type | Storage | Notes |
|---|---|---|
| `Packet` | owned AVPacket | caller `deinit` after `sendPacket` |
| Decoded `VideoFrame` | borrowed AVFrame | until `deinit` |
| Converted `VideoFrame` | owned bytes | independent of source |
| `AudioFrame` | owned bytes | until `deinit` |

No frame pools in v1.
