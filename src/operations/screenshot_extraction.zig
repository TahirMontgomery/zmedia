const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const command_mod = @import("../command.zig");
const executor_mod = @import("../executor.zig");
const image = @import("../image.zig");
const runtime_mod = @import("../runtime.zig");
const time = @import("../time.zig");
const validation = @import("../validation.zig");

const Command = command_mod.Command;
const Executor = executor_mod.Executor;
const ProcessResult = executor_mod.ProcessResult;
const ImageFormat = image.ImageFormat;
const ImageQuality = image.ImageQuality;
const RuntimeConfig = runtime_mod.RuntimeConfig;
const Timestamp = time.Timestamp;
const ValidationError = validation.ValidationError;

pub const ScreenshotResult = struct {
    timestamp: Timestamp,
    output_path: []u8,
    process: ProcessResult,

    pub fn deinit(self: *ScreenshotResult, allocator: Allocator) void {
        allocator.free(self.output_path);
        self.process.deinit(allocator);
        self.* = undefined;
    }
};

pub const ScreenshotBatchResult = struct {
    items: []ScreenshotResult,

    pub fn succeeded(self: ScreenshotBatchResult) bool {
        for (self.items) |item| {
            if (!item.process.succeeded()) {
                return false;
            }
        }
        return true;
    }

    pub fn expectSuccess(self: ScreenshotBatchResult) !void {
        if (!self.succeeded()) {
            return error.ScreenshotExtractionFailed;
        }
    }

    pub fn deinit(self: *ScreenshotBatchResult, allocator: Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
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

    pub fn validate(self: *const ScreenshotExtraction) ValidationError!void {
        if (self.input_path.len == 0) {
            return error.EmptyInputPath;
        }

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

    pub fn buildForTimestamp(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        config: RuntimeConfig,
        timestamp: Timestamp,
        output_path: []const u8,
    ) !Command {
        try self.validate();

        var command = Command.init(allocator, config.ffmpeg_path);
        errdefer command.deinit();

        if (self.overwrite_existing) {
            try command.append("-y");
        } else {
            try command.append("-n");
        }

        const formatted = try timestamp.formatAlloc(allocator);
        defer allocator.free(formatted);

        try command.append("-ss");
        try command.append(formatted);
        try command.append("-i");
        try command.append(self.input_path);
        try command.append("-frames:v");
        try command.append("1");
        try command.append("-c:v");
        try command.append(self.image_format.ffmpegCodec());

        if (self.image_quality) |quality_value| {
            switch (self.image_format) {
                .jpeg => {
                    try command.append("-q:v");
                    try command.appendFormat("{d}", .{quality_value.jpegQScale()});
                },
                .webp => {
                    try command.append("-quality");
                    try command.appendFormat("{d}", .{quality_value.webpQuality()});
                },
                .png => {},
            }
        }

        try command.append(output_path);
        return command;
    }

    pub fn run(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        io: Io,
    ) !ScreenshotBatchResult {
        return self.runWithConfig(allocator, io, .{});
    }

    pub fn runWithConfig(
        self: *const ScreenshotExtraction,
        allocator: Allocator,
        io: Io,
        config: RuntimeConfig,
    ) !ScreenshotBatchResult {
        try self.validate();

        try Io.Dir.cwd().createDirPath(io, self.output_directory.?);

        var items: std.ArrayList(ScreenshotResult) = .empty;
        errdefer {
            for (items.items) |*item| {
                item.deinit(allocator);
            }
            items.deinit(allocator);
        }

        const executor = Executor.init(config);

        for (self.timestamps_value, 0..) |timestamp, index| {
            const output_path = try self.outputPathForIndex(allocator, index);
            errdefer allocator.free(output_path);

            var built = try self.buildForTimestamp(
                allocator,
                config,
                timestamp,
                output_path,
            );
            defer built.deinit();

            var run_result = try executor.run(allocator, io, &built);
            const process = switch (run_result) {
                .success => |result| result,
                .failure => |result| result,
            };
            run_result = undefined;

            try items.append(allocator, .{
                .timestamp = timestamp,
                .output_path = output_path,
                .process = process,
            });
        }

        return .{
            .items = try items.toOwnedSlice(allocator),
        };
    }
};
