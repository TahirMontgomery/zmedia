const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const command_mod = @import("command.zig");
const runtime_mod = @import("runtime.zig");

const Command = command_mod.Command;
const RuntimeConfig = runtime_mod.RuntimeConfig;

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

pub const Executor = struct {
    config: RuntimeConfig = .{},

    pub fn init(config: RuntimeConfig) Executor {
        return .{ .config = config };
    }

    pub fn run(
        self: Executor,
        allocator: Allocator,
        io: Io,
        command: *const Command,
    ) !RunResult {
        const full_argv = try command.fullArgv(allocator);
        defer allocator.free(full_argv);

        const started = Io.Timestamp.now(io, .awake);

        const process_result = try std.process.run(allocator, io, .{
            .argv = full_argv,
        });

        const finished = Io.Timestamp.now(io, .awake);
        const elapsed = started.durationTo(finished);
        const elapsed_ns: u64 = if (elapsed.nanoseconds <= 0)
            0
        else
            @intCast(@min(elapsed.nanoseconds, std.math.maxInt(u64)));

        const exit_code = termToExitCode(process_result.term);

        var stdout = process_result.stdout;
        var stderr = process_result.stderr;

        if (!self.config.capture_stdout) {
            allocator.free(stdout);
            stdout = try allocator.dupe(u8, "");
        }
        if (!self.config.capture_stderr) {
            allocator.free(stderr);
            stderr = try allocator.dupe(u8, "");
        }

        const owned = ProcessResult{
            .exit_code = exit_code,
            .stdout = stdout,
            .stderr = stderr,
            .elapsed_ns = elapsed_ns,
        };

        if (exit_code == 0) {
            return .{ .success = owned };
        }

        return .{ .failure = owned };
    }
};

fn termToExitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => 128,
        .stopped => 128,
        .unknown => 1,
    };
}
