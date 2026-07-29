const std = @import("std");

/// Cooperative cancel token. Safe to signal from another thread while a worker
/// is inside `MediaInput.openWithOptions`.
///
/// One-shot: once `requestCancel` is called, `isCancelRequested` stays true.
/// Ember should use one token per open attempt (or treat it as one-shot).
pub const CancelToken = struct {
    cancelled: std.atomic.Value(bool) = .init(false),

    pub fn init() CancelToken {
        return .{};
    }

    pub fn requestCancel(self: *CancelToken) void {
        self.cancelled.store(true, .release);
    }

    pub fn isCancelRequested(self: *const CancelToken) bool {
        return self.cancelled.load(.acquire);
    }
};

pub const OpenOptions = struct {
    cancel: ?*CancelToken = null,
    /// Optional wall-clock bound (monotonic). Whichever of cancel/timeout
    /// fires first wins.
    timeout_ns: ?u64 = null,
};

pub const InterruptReason = enum {
    none,
    cancelled,
    timed_out,
};

/// Opaque state passed to FFmpeg's AVIOInterruptCB. Lives on the open stack.
pub const InterruptState = struct {
    cancel: ?*CancelToken = null,
    deadline_ns: ?u64 = null,
    reason: InterruptReason = .none,

    pub fn fromOptions(options: OpenOptions) InterruptState {
        var state: InterruptState = .{
            .cancel = options.cancel,
        };
        if (options.timeout_ns) |timeout_ns| {
            state.deadline_ns = monotonicNs() +| timeout_ns;
        }
        return state;
    }

    pub fn shouldAbort(self: *InterruptState) bool {
        if (self.cancel) |token| {
            if (token.isCancelRequested()) {
                self.reason = .cancelled;
                return true;
            }
        }
        if (self.deadline_ns) |deadline| {
            if (monotonicNs() >= deadline) {
                self.reason = .timed_out;
                return true;
            }
        }
        return false;
    }
};

pub fn monotonicNs() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts) != 0) {
        return 0;
    }
    const sec: u64 = @intCast(@max(ts.sec, 0));
    const nsec: u64 = @intCast(@max(ts.nsec, 0));
    return sec * std.time.ns_per_s + nsec;
}
