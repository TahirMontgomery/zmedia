const std = @import("std");

const runtime_mod = @import("../process/runtime.zig");
const Command = @import("../process/command.zig").Command;
const ProcessRuntime = runtime_mod.ProcessRuntime;

pub fn requireNonEmptyInput(path: []const u8) @import("../validation.zig").ValidationError!void {
    if (path.len == 0) {
        return error.EmptyInputPath;
    }
}

pub fn appendOverwriteFlag(command: *Command, overwrite: bool) !void {
    if (overwrite) {
        try command.append("-y");
    } else {
        try command.append("-n");
    }
}

pub fn ensureDir(io: std.Io, path: []const u8) !void {
    if (path.len == 0) return;
    try std.Io.Dir.cwd().createDirPath(io, path);
}

pub fn ensureParentDir(io: std.Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |directory| {
        try ensureDir(io, directory);
    }
}

pub fn runBuilt(
    runtime: ProcessRuntime,
    allocator: std.mem.Allocator,
    command: *const Command,
) !@import("../process/executor.zig").RunResult {
    return runtime.run(allocator, command);
}

pub fn fileExists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}
