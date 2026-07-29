# VideoFrame / AudioFrame Lifetime

## VideoFrame (decoded)

`VideoDecoder.nextFrame()` returns a `VideoFrame` whose pixel planes borrow memory from an
internal `AVFrame` (`FrameStorage.borrowed_avframe`).

Rules:

1. Call `frame.deinit()` when finished with a frame.
2. Do **not** call `nextFrame()` again while holding a previous borrowed frame from the same
   decoder unless you have already `deinit`'d it. The current implementation allocates a new
   `AVFrame` per successful decode, so multiple outstanding frames are allowed, but you must
   still free each one.
3. Plane pointers (`frame.planes[i].data`) are invalid after `deinit`.
4. Ember may copy plane bytes into a GPU texture before releasing the frame.

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

`VideoConverter.convert` returns an **owned** `VideoFrame` (`FrameStorage.owned_bytes`) in a
packed RGB format (typically `.rgba`). That buffer remains valid after the source decoded
frame’s `deinit`. Call `converted.deinit()` when finished.

`convertInto` writes into a caller-owned buffer and does not allocate a `VideoFrame`.

## AudioFrame

`AudioDecoder.nextFrame()` returns an `AudioFrame` with **owned** sample bytes
(`FrameStorage.owned_bytes`). The underlying `AVFrame` is freed during conversion.

Rules:

1. Call `frame.deinit()` to free the owned buffer.
2. Frames remain valid across subsequent `nextFrame()` calls until `deinit`.
3. `AudioResampler.convert` returns a new owned `AudioFrame`; both input and output must be
   released by the caller when done.

## Ownership summary

| Type | Storage | Valid after source `deinit`? |
|---|---|---|
| Decoded `VideoFrame` | borrowed AVFrame | No |
| Converted `VideoFrame` | owned bytes | Yes (independent of source) |
| `AudioFrame` | owned bytes | Yes |
| `Packet` | owned AVPacket | until `deinit` |

No frame pools in v1. Measure copies before adding pooling.
