const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const expected = std.mem.trim(u8, @embedFile("toolchains/zig-version.txt"), "\r\n");
    if (!std.mem.eql(u8, builtin.zig_version_string, expected)) {
        std.debug.panic("Fairpane requires Zig {s}; found {s}", .{ expected, builtin.zig_version_string });
    }
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("fairpane", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "fairpane",
        .linkage = .static,
        .root_module = module,
    });
    b.installArtifact(lib);
    b.installFile("include/fairpane.h", "include/fairpane.h");

    const unit_tests = b.addTest(.{ .root_module = module });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run the bootstrap Zig unit tests");
    test_step.dependOn(&run_tests.step);

    const check_step = b.step("check", "Compile the library and unit tests without execution");
    check_step.dependOn(&lib.step);
    check_step.dependOn(&unit_tests.step);
}
