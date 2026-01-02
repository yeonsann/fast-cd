const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import ZigTUI module
    const zigtui_module = b.addModule("zigtui", .{
        .root_source_file = b.path("libs/zigtui/src/lib.zig"),
    });

    // Your executable
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigtui", .module = zigtui_module },
            },
        }),
    });

    b.installArtifact(exe);
}
