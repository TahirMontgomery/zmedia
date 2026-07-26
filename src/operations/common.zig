const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const command_mod = @import("../command.zig");
const runtime_mod = @import("../runtime.zig");
const validation = @import("../validation.zig");

const Command = command_mod.Command;
const Runtime = runtime_mod.Runtime;
const RunResult = @import("../executor.zig").RunResult;
const ValidationError = validation.ValidationError;

pub fn requireNonEmptyInput(path: []const u8) ValidationError!void {
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

pub fn ensureDir(io: Io, path: []const u8) !void {
    if (path.len == 0) return;
    try Io.Dir.cwd().createDirPath(io, path);
}

pub fn ensureParentDir(io: Io, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |directory| {
        try ensureDir(io, directory);
    }
}

pub fn runBuilt(
    runtime: Runtime,
    allocator: Allocator,
    command: *const Command,
) !RunResult {
    return runtime.run(allocator, command);
}

pub fn fileExists(io: Io, path: []const u8) bool {
    _ = Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}
