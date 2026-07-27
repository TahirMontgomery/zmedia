# VideoFrame / AudioFrame Lifetime

## VideoFrame

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

## AudioFrame

`AudioDecoder.nextFrame()` returns an `AudioFrame` with **owned** sample bytes
(`FrameStorage.owned_bytes`). The underlying `AVFrame` is freed during conversion.

Rules:

1. Call `frame.deinit()` to free the owned buffer.
2. Frames remain valid across subsequent `nextFrame()` calls until `deinit`.
3. `AudioResampler.convert` returns a new owned `AudioFrame`; both input and output must be
   released by the caller when done.

## Ownership summary

| Type | Storage | Valid after next decode? |
|---|---|---|
| `VideoFrame` | borrowed AVFrame | Yes (separate AVFrame), until `deinit` |
| `AudioFrame` | owned bytes | Yes, until `deinit` |
| `Packet` | owned AVPacket | until `deinit` |

No frame pools in v1. Measure copies before adding pooling.
