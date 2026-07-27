const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const command_mod = @import("command.zig");
const runtime_mod = @import("runtime.zig");

const Command = command_mod.Command;
const ProcessConfig = runtime_mod.ProcessConfig;

pub const ProcessResult = struct {
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,
    elapsed_ns: u64,

    pub fn succeeded(self: ProcessResult) bool {
        return self.exit_code == 0;
    }

    pub fn deinit(self: *ProcessResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
        self.* = undefined;
    }
};

pub const RunResult = union(enum) {
    success: ProcessResult,
    failure: ProcessResult,

    pub fn succeeded(self: RunResult) bool {
        return switch (self) {
            .success => true,
            .failure => false,
        };
    }

    pub fn expectSuccess(self: RunResult) !void {
        return switch (self) {
            .success => {},
            .failure => error.FfmpegProcessFailed,
        };
    }

    pub fn process(self: *const RunResult) *const ProcessResult {
        return switch (self.*) {
            .success => |*result| result,
            .failure => |*result| result,
        };
    }

    pub fn deinit(self: *RunResult, allocator: Allocator) void {
        switch (self.*) {
            .success => |*result| result.deinit(allocator),
            .failure => |*result| result.deinit(allocator),
        }
        self.* = undefined;
    }
};

/// Thin wrapper kept for compatibility; prefer `ProcessRuntime.run`.
pub const Executor = struct {
    config: ProcessConfig = .{},

    pub fn init(config: ProcessConfig) Executor {
        return .{ .config = config };
    }

    pub fn run(
        self: Executor,
        allocator: Allocator,
        io: Io,
        command: *const Command,
    ) !RunResult {
        return runCommand(allocator, io, self.config, command);
    }
};

pub fn run(
    allocator: Allocator,
    io: Io,
    config: ProcessConfig,
    command: *const Command,
) !RunResult {
    return runCommand(allocator, io, config, command);
}

fn runCommand(
    allocator: Allocator,
    io: Io,
    config: ProcessConfig,
    command: *const Command,
) !RunResult {
    const full_argv = try command.fullArgv(allocator);
    defer allocator.free(full_argv);

    const started = Io.Timestamp.now(io, .awake);

    const stdout_behavior: std.process.SpawnOptions.StdIo = if (config.capture_stdout) .pipe else .ignore;
    const stderr_behavior: std.process.SpawnOptions.StdIo = if (config.capture_stderr) .pipe else .ignore;

    var child = try std.process.spawn(io, .{
        .argv = full_argv,
        .stdin = .ignore,
        .stdout = stdout_behavior,
        .stderr = stderr_behavior,
    });
    defer child.kill(io);

    var stdout: []u8 = try allocator.dupe(u8, "");
    errdefer allocator.free(stdout);
    var stderr: []u8 = try allocator.dupe(u8, "");
    errdefer allocator.free(stderr);

    if (config.capture_stdout and config.capture_stderr) {
        const collected = try collectBoth(allocator, io, child.stdout.?, child.stderr.?);
        allocator.free(stdout);
        allocator.free(stderr);
        stdout = collected.stdout;
        stderr = collected.stderr;
    } else if (config.capture_stdout) {
        allocator.free(stdout);
        stdout = try readAll(allocator, io, child.stdout.?);
    } else if (config.capture_stderr) {
        allocator.free(stderr);
        stderr = try readAll(allocator, io, child.stderr.?);
    }

    const term = try child.wait(io);

    const finished = Io.Timestamp.now(io, .awake);
    const elapsed = started.durationTo(finished);
    const elapsed_ns: u64 = if (elapsed.nanoseconds <= 0)
        0
    else
        @intCast(@min(elapsed.nanoseconds, std.math.maxInt(u64)));

    const owned = ProcessResult{
        .exit_code = termToExitCode(term),
        .stdout = stdout,
        .stderr = stderr,
        .elapsed_ns = elapsed_ns,
    };

    if (owned.exit_code == 0) {
        return .{ .success = owned };
    }
    return .{ .failure = owned };
}

fn collectBoth(
    allocator: Allocator,
    io: Io,
    stdout_file: Io.File,
    stderr_file: Io.File,
) !struct { stdout: []u8, stderr: []u8 } {
    var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: Io.File.MultiReader = undefined;
    multi_reader.init(
        allocator,
        io,
        multi_reader_buffer.toStreams(),
        &.{ stdout_file, stderr_file },
    );
    defer multi_reader.deinit();

    while (multi_reader.fill(64, .none)) |_| {} else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }
    try multi_reader.checkAnyError();

    const stdout = try multi_reader.toOwnedSlice(0);
    errdefer allocator.free(stdout);
    const stderr = try multi_reader.toOwnedSlice(1);
    return .{ .stdout = stdout, .stderr = stderr };
}

fn readAll(allocator: Allocator, io: Io, file: Io.File) ![]u8 {
    var buffer: [4096]u8 = undefined;
    var file_reader = file.readerStreaming(io, &buffer);
    return file_reader.interface.allocRemaining(allocator, .unlimited) catch |err| switch (err) {
        error.ReadFailed => return file_reader.err orelse error.Unexpected,
        error.OutOfMemory => return error.OutOfMemory,
        error.StreamTooLong => return error.StreamTooLong,
    };
}

fn termToExitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => 128,
        .stopped => 128,
        .unknown => 1,
    };
}
