const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const command_mod = @import("../command.zig");
const common = @import("common.zig");
const executor_mod = @import("../executor.zig");
const image = @import("../image.zig");
const runtime_mod = @import("../runtime.zig");
const time = @import("../time.zig");
const validation = @import("../validation.zig");

const Command = command_mod.Command;
const ProcessResult = executor_mod.ProcessResult;
const ImageFormat = image.ImageFormat;
const ImageQuality = image.ImageQuality;
const Runtime = runtime_mod.Runtime;
const RuntimeConfig = runtime_mod.RuntimeConfig;
const Timestamp = time.Timestamp;
const ValidationError = validation.ValidationError;

pub const ScreenshotResult = struct {
    timestamp: Timestamp,
    output_path: []u8,
    written: bool,

    pub fn deinit(self: *ScreenshotResult, allocator: Allocator) void {
        allocator.free(self.output_path);
        self.* = undefined;
    }
};

pub const ScreenshotBatchResult = struct {
    items: []ScreenshotResult,
    process: ProcessResult,

    pub fn succeeded(self: ScreenshotBatchResult) bool {
        if (!self.process.succeeded()) {
            return false;
        }
        for (self.items) |item| {
            if (!item.written) {
                return false;
            }
        }
        return true;
    }

    pub fn expectSuccess(self: ScreenshotBatchResult) !void {
        if (!self.succeeded()) {
            return error.FfmpegProcessFailed;
        }
    }

    pub fn deinit(self: *ScreenshotBatchResult, allocator: Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
        self.process.deinit(allocator);
        self.* = undefined;
    }
};

pub const ScreenshotExtraction = struct {
    input_path: []const u8,

    timestamps_value: []const Timestamp = &.{},
    output_directory: ?[]const u8 = null,
    output_prefix: []const u8 = "frame",

    image_format: ImageFormat = .jpeg,
    image_quality: ?ImageQuality = null,

    overwrite_existing: bool = false,
    reject_duplicate_timestamps: bool = false,

    pub fn init(input_path: []const u8) ScreenshotExtraction {
        return .{
            .input_path = input_path,
        };
    }

    pub fn timestamps(
        self: *ScreenshotExtraction,
        values: []const Timestamp,
    ) *ScreenshotExtraction {
        self.timestamps_value = values;
        return self;
    }

    pub fn format(
        self: *ScreenshotExtraction,
        value: ImageFormat,
    ) *ScreenshotExtraction {
        self.image_format = value;
        return self;
    }

    pub fn quality(
        self: *ScreenshotExtraction,
        value: ImageQuality,
    ) *ScreenshotExtraction {
        self.image_quality = value;
        return self;
    }

    pub fn outputDirectory(
        self: *ScreenshotExtraction,
        path: []const u8,
    ) *ScreenshotExtraction {
        self.output_directory = path;
        return self;
    }

    pub fn prefix(
        self: *ScreenshotExtraction,
        value: []const u8,
    ) *ScreenshotExtraction {
        self.output_prefix = value;
        return self;
    }

    pub fn overwrite(
        self: *ScreenshotExtraction,
        enabled: bool,
    ) *ScreenshotExtraction {
        self.overwrite_existing = enabled;
        return self;
    }

    pub fn rejectDuplicates(
        self: *ScreenshotExtraction,
        enabled: bool,
    ) *ScreenshotExtraction {
        self.reject_duplicate_timestamps = enabled;
        return self;
    }

    pub fn validate(self: *const ScreenshotExtraction) ValidationError!void {
        try common.requireNonEmptyInput(self.input_path);

        if (self.timestamps_value.len == 0) {
            return error.NoTimestamps;
        }

        const directory = self.output_directory orelse {
            return error.MissingOutputDirectory;
        };

        if (directory.len == 0) {
            return error.MissingOutputDirectory;
        }

        if (self.output_prefix.len == 0) {
            return error.EmptyOutputPrefix;
        }

        if (self.reject_duplicate_timestamps) {
            for (self.timestamps_value, 0..) |left, i| {
                for (self.timestamps_value[i + 1 ..]) |right| {
                    if (left.eql(right)) {
                        return error.DuplicateTimestamp;
                    }
                }
            }
        }
    }

    pub fn outputPathForIndex(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        index: usize,
    ) ![]u8 {
        const directory = self.output_directory orelse {
            return error.MissingOutputDirectory;
        };

        return std.fmt.allocPrint(
            allocator,
            "{s}/{s}-{d:0>3}.{s}",
            .{
                directory,
                self.output_prefix,
                index + 1,
                self.image_format.extension(),
            },
        );
    }

    /// Builds one multi-output ffmpeg command for all timestamps.
    pub fn build(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        config: RuntimeConfig,
    ) !Command {
        try self.validate();

        var command = Command.init(allocator, config.ffmpeg_path);
        errdefer command.deinit();

        try command.arguments.ensureTotalCapacity(
            allocator,
            4 + self.timestamps_value.len * 8,
        );

        try common.appendOverwriteFlag(&command, self.overwrite_existing);
        try command.appendPair("-i", self.input_path);

        for (self.timestamps_value, 0..) |timestamp, index| {
            const output_path = try self.outputPathForIndex(allocator, index);
            appendOutputSegment(self, &command, timestamp, output_path) catch |err| {
                allocator.free(output_path);
                return err;
            };
        }

        return command;
    }

    pub fn run(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        io: Io,
    ) !ScreenshotBatchResult {
        return self.runWith(allocator, Runtime.init(io, .{}));
    }

    pub fn runWithConfig(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        io: Io,
        config: RuntimeConfig,
    ) !ScreenshotBatchResult {
        return self.runWith(allocator, Runtime.init(io, config));
    }

    pub fn runWith(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        runtime: Runtime,
    ) !ScreenshotBatchResult {
        try self.validate();
        try common.ensureDir(runtime.io, self.output_directory.?);

        var output_paths: std.ArrayList([]u8) = .empty;
        errdefer {
            for (output_paths.items) |path| {
                allocator.free(path);
            }
            output_paths.deinit(allocator);
        }

        try output_paths.ensureTotalCapacity(allocator, self.timestamps_value.len);
        for (self.timestamps_value, 0..) |_, index| {
            try output_paths.append(allocator, try self.outputPathForIndex(allocator, index));
        }

        var built = try self.build(allocator, runtime.config);
        defer built.deinit();

        var run_result = try common.runBuilt(runtime, allocator, &built);
        errdefer run_result.deinit(allocator);

        var items: std.ArrayList(ScreenshotResult) = .empty;
        errdefer {
            for (items.items) |*item| {
                item.deinit(allocator);
            }
            items.deinit(allocator);
        }

        try items.ensureTotalCapacity(allocator, self.timestamps_value.len);
        for (self.timestamps_value, output_paths.items) |timestamp, output_path| {
            const written = common.fileExists(runtime.io, output_path);
            try items.append(allocator, .{
                .timestamp = timestamp,
                .output_path = output_path,
                .written = written,
            });
        }
        // Paths are now owned by items.
        output_paths.clearRetainingCapacity();
        output_paths.deinit(allocator);

        const process = switch (run_result) {
            .success => |result| result,
            .failure => |result| result,
        };
        run_result = undefined;

        return .{
            .items = try items.toOwnedSlice(allocator),
            .process = process,
        };
    }

    pub fn printCommand(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        writer: *Io.Writer,
        config: RuntimeConfig,
    ) !void {
        var built = try self.build(allocator, config);
        defer built.deinit();
        try built.render(writer);
    }
};

fn appendOutputSegment(
    self: *const ScreenshotExtraction,
    command: *Command,
    timestamp: Timestamp,
    output_path: []u8,
) !void {
    const formatted = try timestamp.formatAlloc(command.allocator);
    try command.append("-ss");
    try command.appendOwned(formatted);
    try command.appendPair("-frames:v", "1");
    try command.appendPair("-c:v", self.image_format.ffmpegCodec());

    if (self.image_quality) |quality_value| {
        switch (self.image_format) {
            .jpeg => {
                try command.appendPairFormat("-q:v", "{d}", .{quality_value.jpegQScale()});
            },
            .webp => {
                try command.appendPairFormat("-quality", "{d}", .{quality_value.webpQuality()});
            },
            .png => {},
        }
    }

    try command.appendOwned(output_path);
}
