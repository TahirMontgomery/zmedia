const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const link_ffmpeg = b.option(bool, "link-ffmpeg", "Link FFmpeg libraries for runtime APIs") orelse true;

    const include_dir = b.option([]const u8, "ffmpeg-include", "FFmpeg include directory") orelse
        detectFfmpegInclude(b);
    const lib_dir = b.option([]const u8, "ffmpeg-lib", "FFmpeg library directory") orelse
        detectFfmpegLib(b);

    const options = b.addOptions();
    options.addOption(bool, "link_ffmpeg", link_ffmpeg);

    var ffmpeg_mod: ?*std.Build.Module = null;
    if (link_ffmpeg) {
        const tc = b.addTranslateC(.{
            .root_source_file = b.path("src/internal/bindings/ffmpeg.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        tc.addIncludePath(.{ .cwd_relative = include_dir });
        ffmpeg_mod = tc.createModule();
    }

    const mod = b.addModule("zmedia", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = link_ffmpeg,
    });
    mod.addOptions("build_options", options);

    if (link_ffmpeg) {
        mod.addImport("ffmpeg_c", ffmpeg_mod.?);
        mod.addLibraryPath(.{ .cwd_relative = lib_dir });
        mod.addIncludePath(.{ .cwd_relative = include_dir });
        mod.linkSystemLibrary("avformat", .{});
        mod.linkSystemLibrary("avcodec", .{});
        mod.linkSystemLibrary("avutil", .{});
        mod.linkSystemLibrary("swresample", .{});
        mod.linkSystemLibrary("swscale", .{});
    }

    const exe = b.addExecutable(.{
        .name = "zmedia-process",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmedia", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run zmedia-process");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmedia", .module = mod },
            },
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_mod_tests.step);

    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmedia", .module = mod },
            },
        }),
    });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    run_integration_tests.setCwd(b.path("."));

    const integration_step = b.step("integration-test", "Run process integration tests (requires ffmpeg CLI)");
    integration_step.dependOn(&run_integration_tests.step);

    if (link_ffmpeg) {
        const ffmpeg_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/ffmpeg_runtime_test.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zmedia", .module = mod },
                },
            }),
        });
        const run_ffmpeg_tests = b.addRunArtifact(ffmpeg_tests);
        run_ffmpeg_tests.setCwd(b.path("."));
        const ffmpeg_step = b.step("ffmpeg-test", "Run library-backed FFmpeg runtime tests");
        ffmpeg_step.dependOn(&run_ffmpeg_tests.step);
        integration_step.dependOn(&run_ffmpeg_tests.step);
    }

    addExample(b, mod, target, optimize, "extract_audio", "examples/extract_audio.zig");
    addExample(b, mod, target, optimize, "screenshots", "examples/screenshots.zig");
    addExample(b, mod, target, optimize, "probe", "examples/probe.zig");
    addExample(b, mod, target, optimize, "process_video", "examples/process_video.zig");
    if (link_ffmpeg) {
        addExample(b, mod, target, optimize, "decode_video", "examples/decode_video.zig");
    }
}

fn addExample(
    b: *std.Build,
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    source: []const u8,
) void {
    const example_exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmedia", .module = mod },
            },
        }),
    });

    const install = b.addInstallArtifact(example_exe, .{
        .dest_dir = .{ .override = .{ .custom = "examples" } },
    });

    const step = b.step(name, b.fmt("Build and install the {s} example", .{name}));
    step.dependOn(&install.step);

    const run_cmd = b.addRunArtifact(example_exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step(
        b.fmt("run-{s}", .{name}),
        b.fmt("Run the {s} example", .{name}),
    );
    run_step.dependOn(&run_cmd.step);
}

fn detectFfmpegInclude(b: *std.Build) []const u8 {
    if (pkgConfigFirstToken(b, &.{ "pkg-config", "--cflags-only-I", "libavformat" })) |token| {
        return stripFlag(token, "-I");
    }
    const candidates = [_][]const u8{
        "/opt/homebrew/include",
        "/usr/local/include",
        "/usr/include",
    };
    for (candidates) |path| {
        if (pathExists(b, b.fmt("{s}/libavformat/avformat.h", .{path}))) return path;
    }
    return "/opt/homebrew/include";
}

fn detectFfmpegLib(b: *std.Build) []const u8 {
    if (pkgConfigFirstToken(b, &.{ "pkg-config", "--libs-only-L", "libavformat" })) |token| {
        return stripFlag(token, "-L");
    }
    const candidates = [_][]const u8{
        "/opt/homebrew/lib",
        "/usr/local/lib",
        "/usr/lib",
    };
    for (candidates) |path| {
        if (pathExists(b, path)) return path;
    }
    return "/opt/homebrew/lib";
}

fn pkgConfigFirstToken(b: *std.Build, argv: []const []const u8) ?[]const u8 {
    var code: u8 = undefined;
    const stdout = b.runAllowFail(argv, &code, .ignore) catch return null;
    if (code != 0) return null;
    const trimmed = std.mem.trim(u8, stdout, " \t\r\n");
    if (trimmed.len == 0) return null;
    var iter = std.mem.tokenizeAny(u8, trimmed, " \t");
    return b.dupe(iter.next() orelse trimmed);
}

fn pathExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(b.graph.io, path, .{}) catch return false;
    return true;
}

fn stripFlag(value: []const u8, prefix: []const u8) []const u8 {
    if (std.mem.startsWith(u8, value, prefix)) {
        return value[prefix.len..];
    }
    return value;
}
