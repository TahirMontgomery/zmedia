const std = @import("std");

test {
    _ = @import("command_test.zig");
    _ = @import("timestamp_test.zig");
    _ = @import("audio_extraction_test.zig");
    _ = @import("screenshot_extraction_test.zig");
    _ = @import("probe_test.zig");
}
