const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const minised_dep = b.dependency("minised", .{});

    const minised = b.addExecutable(.{
        .name = "minised",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    minised.addCSourceFiles(.{
        .root = minised_dep.path("."),
        .files = &.{ "sedcomp.c", "sedexec.c" },
    });
    b.installArtifact(minised);
}
