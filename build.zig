const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zmedia", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    const test_step = b.step("test", "Run unit tests (no FFmpeg required)");
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
    // Integration tests read fixtures/ relative to the project root.
    run_integration_tests.setCwd(b.path("."));

    const integration_step = b.step("integration-test", "Run integration tests (requires FFmpeg)");
    integration_step.dependOn(&run_integration_tests.step);

    addExample(b, mod, target, optimize, "extract_audio", "examples/extract_audio.zig");
    addExample(b, mod, target, optimize, "screenshots", "examples/screenshots.zig");
    addExample(b, mod, target, optimize, "probe", "examples/probe.zig");
    addExample(b, mod, target, optimize, "process_video", "examples/process_video.zig");
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
