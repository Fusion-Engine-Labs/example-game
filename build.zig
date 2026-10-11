const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdk = b.dependency("fusion_sdk", .{
        .target = target,
        .optimize = optimize,
    });

    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
        .imports = &.{
            .{
                .name = "fusion_sdk",
                .module = sdk.module("fusion_sdk"),
            },
        },
    });

    const lib = b.addLibrary(.{
        .name = "sandbox-game",
        .linkage = .dynamic,
        .root_module = game_mod,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{ .root_module = game_mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run game tests").dependOn(&run_tests.step);
}
