# Ember handoff: cancellable / bounded MediaInput.open

**From:** Ember Studio (`montgomery_labs/ember/studio`)  
**To:** zmedia  
**Priority:** Needed for clean app Quit and reopen while a discover/open is in flight  
**Date:** 2026-07-28  
**Consumer commit context:** Ember Sprint 2 — worker-thread `MediaInput.open` + stream listing; Quit currently blocks on `Thread.join` because open cannot be interrupted.

## Problem Ember hit

Ember opens media **off the UI thread**. That call is **blocking and uncancellable**. On Quit / reopen Ember must `join` the worker. If `MediaInput.open` hangs, the app freezes in deinit instead of exiting or starting a new open.

Ember will **not** call FFmpeg, pthread_cancel, or abandon a worker that still holds a live `MediaInput` / libav state. Cancellation must be owned by zmedia.

## API shipped

```zig
pub const CancelToken = struct {
    pub fn init() CancelToken;
    pub fn requestCancel(self: *CancelToken) void;
    pub fn isCancelRequested(self: *const CancelToken) bool;
};

pub const OpenOptions = struct {
    cancel: ?*CancelToken = null,
    timeout_ns: ?u64 = null,
};

pub fn open(allocator, path) MediaError!MediaInput;
pub fn openWithOptions(allocator, path, options) MediaError!MediaInput;
```

Errors: `error.Cancelled`, `error.TimedOut` (dedicated; not mapped through `Unknown`).

## Semantics

1. Pre-cancelled token → immediate `Cancelled`.
2. During open: FFmpeg `AVFormatContext.interrupt_callback` (`AVIOInterruptCB`) polls cancel + optional deadline.
3. Partial open always cleaned up (`avformat_close_input`).
4. Cancel applies to the open attempt only; decode cancel is a separate handoff.
5. `open(allocator, path)` unchanged (`openWithOptions` with `{}`).

## Interrupt mechanism (implementation note)

zmedia uses **`AVFormatContext.interrupt_callback`** (`AVIOInterruptCB`):

- Allocates an `AVFormatContext` up front, installs the callback, then calls `avformat_open_input` / `avformat_find_stream_info`.
- Callback returns `1` when the cancel token is set or the monotonic deadline from `timeout_ns` has passed.
- FFmpeg typically surfaces that as `AVERROR_EXIT`; zmedia maps via the interrupt reason to `Cancelled` or `TimedOut`.

### Limits (best-effort)

- Interrupt is **cooperative**. Protocols/demuxers that block in a kernel syscall without polling the callback (e.g. blocking `open()` on a FIFO with no writer, some rare demuxer stalls) may not abort until the next check point.
- Local files usually interrupt quickly during probe / `find_stream_info`.
- Network URLs generally honor the callback during connect/read loops.
- Cancel token is **one-shot** for a given open attempt: once `requestCancel` is called, it stays requested; Ember should use a fresh token (or rely on one-shot) per open.

## Acceptance

Covered by `tests/ffmpeg_runtime_test.zig` (cancel-before-open, cancel-during-open via FIFO stall, timeout).
