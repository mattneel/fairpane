const std = @import("std");
const builtin = @import("builtin");

/// The case fixtures that the laboratory's unit tests read relative to the build root.
const lab_fixtures = [_][]const u8{
    "case-01-valid.json",
    "case-01-unknown-field.json",
    "case-01-duplicate-field.json",
    "case-01-wrong-format.json",
    "case-01-wrong-version.json",
    "case-01-invalid-base64.json",
    "case-01-uppercase-revision.json",
    "case-01-dotdot-path.json",
    "case-01-missing-environment-field.json",
    "case-01-duplicate-resource-url.json",
    "case-01-zero-step-budget.json",
    "case-02-pass.json",
    "case-03-body-mismatch.json",
    "case-03-state-mismatch.json",
    "case-04-tree-unsupported.json",
    "case-05-null-body.json",
    "case-08-timeout.json",
};

/// A compile-failure fixture of FP-0011 and the exit status and standard-error texts that it must produce.
const CompileFixture = struct {
    case: u8,
    file: []const u8,
    status: u8,
    stderr: []const []const u8,
};

const abi_errors: []const []const u8 = &.{
    "error: parameter of type",
    "error: return type",
    "not allowed in function with calling convention",
    "extern structs cannot contain fields of type",
};

const compile_fixtures = [_]CompileFixture{
    .{ .case = 4, .file = "leaf_invokes_to_number.zig", .status = 1, .stderr = &.{"fairpane-js: a context with effects {} cannot invoke ToNumber, which has effects {callback, allocation, exception, heap_mutation}"} },
    .{ .case = 4, .file = "leaf_invokes_number_to_string.zig", .status = 1, .stderr = &.{"fairpane-js: a context with effects {} cannot invoke Number::toString, which has effects {allocation}"} },
    .{ .case = 4, .file = "allocation_invokes_call.zig", .status = 1, .stderr = &.{"fairpane-js: a context with effects {allocation} cannot invoke Call, which has effects {callback, allocation, exception, heap_mutation}"} },
    .{ .case = 4, .file = "leaf_allocates.zig", .status = 1, .stderr = &.{"fairpane-js: allocateString requires effects {allocation}; the context has effects {}"} },
    .{ .case = 4, .file = "mutation_throws.zig", .status = 1, .stderr = &.{"fairpane-js: throwTypeError requires effects {allocation, exception}; the context has effects {heap_mutation}"} },
    .{ .case = 4, .file = "leaf_calls_behavior.zig", .status = 1, .stderr = &.{"expected type"} },
    .{ .case = 4, .file = "leaf_positive.zig", .status = 0, .stderr = &.{} },
    .{ .case = 5, .file = "catalog_callback_alone.zig", .status = 1, .stderr = &.{"fairpane-js: operation BadCallback declares callback without allocation, exception, and heap_mutation"} },
    .{ .case = 5, .file = "catalog_exception_alone.zig", .status = 1, .stderr = &.{"fairpane-js: operation BadException declares exception without allocation"} },
    .{ .case = 5, .file = "catalog_duplicate_id.zig", .status = 1, .stderr = &.{"fairpane-js: duplicate operation id number_add"} },
    .{ .case = 5, .file = "kernel_wider_context.zig", .status = 1, .stderr = &.{"fairpane-js: kernel for Number::add takes a context with effects {allocation}, but the operation has effects {}"} },
    .{ .case = 5, .file = "kernel_undeclared_throw.zig", .status = 1, .stderr = &.{"fairpane-js: kernel for Number::sameValue returns error.Throw, but the operation does not have the exception effect"} },
    .{ .case = 8, .file = "layout_undescribed_field.zig", .status = 1, .stderr = &.{"fairpane-js: layout Probe does not describe field extra"} },
    .{ .case = 8, .file = "layout_plain_reference.zig", .status = 1, .stderr = &.{"fairpane-js: field hidden of layout Probe holds a heap reference but is declared plain"} },
    .{ .case = 8, .file = "layout_missing_field.zig", .status = 1, .stderr = &.{"fairpane-js: layout Probe describes field ghost, which does not exist"} },
    .{ .case = 20, .file = "abi_reference_value.zig", .status = 1, .stderr = abi_errors },
    .{ .case = 20, .file = "abi_nan_box_value.zig", .status = 1, .stderr = abi_errors },
    .{ .case = 20, .file = "abi_tagged_index_value.zig", .status = 1, .stderr = abi_errors },
};

const measured_representations = [_][]const u8{ "reference", "nan_box", "tagged_index" };
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
    run_tests.setCwd(b.path("."));
    for (lab_fixtures) |name| run_tests.addFileInput(b.path(b.fmt("tests/lab/{s}", .{name})));
    const test_step = b.step("test", "Run the bootstrap Zig unit tests and the laboratory executable cases");
    test_step.dependOn(&run_tests.step);

    const lab_exe = b.addExecutable(.{
        .name = "fairpane-lab",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lab_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const install_lab = b.addInstallArtifact(lab_exe, .{});
    const lab_step = b.step("lab", "Build and install the fairpane-lab headless laboratory");
    lab_step.dependOn(&install_lab.step);

    const lab_check = b.addExecutable(.{
        .name = "fairpane-lab-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lab/check.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "lab", .module = b.createModule(.{
                .root_source_file = b.path("src/lab.zig"),
                .target = target,
                .optimize = optimize,
            }) }},
        }),
    });
    const installed_lab = b.graph.path(.install_bin, b.fmt("fairpane-lab{s}", .{target.result.exeFileExt()}));
    addLabCases(b, test_step, &install_lab.step, installed_lab, lab_check);

    // Each fixture must fail to compile with its listed diagnostics, or compile cleanly when its status is 0.
    // The fixtures import every file of the module, so each check runs on every invocation.
    for (compile_fixtures) |fixture| {
        const run = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "build-obj",
            "-fno-emit-bin",
            "--dep",
            "fairpane",
            b.fmt("-Mroot=tests/compile_fail/{s}", .{fixture.file}),
            "-Mfairpane=src/root.zig",
        });
        run.setName(b.fmt("FP-0011 case {d}: {s}", .{ fixture.case, fixture.file }));
        run.setCwd(b.path("."));
        run.has_side_effects = true;
        run.expectExitCode(fixture.status);
        for (fixture.stderr) |text| run.expectStdErrMatch(text);
        test_step.dependOn(&run.step);
    }

    const check_step = b.step("check", "Compile the library, the laboratory, and unit tests without execution");
    check_step.dependOn(&lib.step);
    check_step.dependOn(&unit_tests.step);
    check_step.dependOn(&lab_exe.step);
    check_step.dependOn(&lab_check.step);

    // A module may import only files under the directory of its root source file.
    // Each measurement root therefore sits beside a copy of `src`, so `src/js` can import `src/dom.zig`.
    const measure_step = b.step("measure", "Build the FP-0011 measurement executables");
    const measure_sources = b.addWriteFiles();
    _ = measure_sources.addCopyDirectory(b.path("src"), "src", .{ .include_extensions = &.{".zig"} });
    for (measured_representations) |name| {
        const root = measure_sources.add(
            b.fmt("fairpane_js_measure_{s}.zig", .{name}),
            b.fmt("pub const main = @import(\"src/js/measure_main_{s}.zig\").main;\n", .{name}),
        );
        const exe = b.addExecutable(.{
            .name = b.fmt("fairpane-js-measure-{s}", .{name}),
            .root_module = b.createModule(.{
                .root_source_file = root,
                .target = target,
                .optimize = optimize,
            }),
        });
        measure_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }
}

/// Adds contract cases 13 and 14, which run the installed `fairpane-lab` executable.
fn addLabCases(
    b: *std.Build,
    test_step: *std.Build.Step,
    install: *std.Build.Step,
    lab: std.Build.LazyPath,
    check: *std.Build.Step.Compile,
) void {
    const exits = [_]struct { name: []const u8, args: []const []const u8, fixture: ?[]const u8, status: u8 }{
        .{ .name = "FP-0007 case 13: case 2 passes with exit status 0", .args = &.{"run"}, .fixture = "case-02-pass.json", .status = 0 },
        .{ .name = "FP-0007 case 13: case 3 fails with exit status 1", .args = &.{"run"}, .fixture = "case-03-body-mismatch.json", .status = 1 },
        .{ .name = "FP-0007 case 13: case 4 is unsupported with exit status 2", .args = &.{"run"}, .fixture = "case-04-tree-unsupported.json", .status = 2 },
        .{ .name = "FP-0007 case 13: case 1 is a harness error with exit status 3", .args = &.{"run"}, .fixture = "case-01-unknown-field.json", .status = 3 },
        .{ .name = "FP-0007 case 13: case 8 times out with exit status 4", .args = &.{"run"}, .fixture = "case-08-timeout.json", .status = 4 },
        .{ .name = "FP-0007 case 13: an unknown command exits with status 64 and writes no result", .args = &.{"frobnicate"}, .fixture = null, .status = 64 },
    };
    const results = [_][]const u8{ "pass", "fail", "unsupported", "harness-error", "timeout" };
    for (exits) |case| {
        const run = labRun(b, install, lab, case.name);
        run.addArgs(case.args);
        if (case.fixture) |fixture| run.addFileArg(b.path(b.fmt("tests/lab/{s}", .{fixture})));
        run.expectExitCode(case.status);
        if (case.status < results.len) {
            run.expectStdOutMatch(b.fmt("\"result\": \"{s}\"", .{results[case.status]}));
        } else {
            run.expectStdOutEqual("");
            run.expectStdErrMatch("usage: fairpane-lab");
        }
        test_step.dependOn(&run.step);
    }

    const minimize = labRun(b, install, lab, "FP-0007 case 14: minimize reduces a failing fetch case with a 4096-byte body");
    minimize.addArg("minimize");
    minimize.addFileArg(b.path("tests/lab/case-14-minimize.json"));
    minimize.addArg("--out");
    const minimized = minimize.addOutputFileArg("minimized.json");
    minimize.expectExitCode(0);
    minimize.expectStdOutMatch("\"result\": \"pass\"");
    test_step.dependOn(&minimize.step);

    const rerun = labRun(b, install, lab, "FP-0007 case 14: the minimized case fails the same check");
    rerun.addArg("run");
    rerun.addFileArg(minimized);
    rerun.expectExitCode(1);
    rerun.expectStdOutMatch("\"check\": \"document_state\"");
    test_step.dependOn(&rerun.step);

    const minimal = b.addRunArtifact(check);
    minimal.setName("FP-0007 case 14: the minimized document body is 1-minimal");
    minimal.addArg("minimal");
    minimal.addFileArg(minimized);
    minimal.expectExitCode(0);
    test_step.dependOn(&minimal.step);

    const refuse = labRun(b, install, lab, "FP-0007 case 14: minimize refuses a passing case");
    refuse.addArg("minimize");
    refuse.addFileArg(b.path("tests/lab/case-02-pass.json"));
    refuse.addArg("--out");
    const refused = refuse.addOutputDirectoryArg2("refused", .{ .suffix = "/minimized.json" });
    refuse.expectExitCode(3);
    refuse.expectStdOutMatch("\"result\": \"harness-error\"");
    test_step.dependOn(&refuse.step);

    const empty = b.addRunArtifact(check);
    empty.setName("FP-0007 case 14: a refused minimization writes nothing");
    empty.addArg("empty");
    empty.addDirectoryArg(refused);
    empty.expectExitCode(0);
    test_step.dependOn(&empty.step);
}

/// Runs the installed laboratory executable after the `lab` installation step.
fn labRun(b: *std.Build, install: *std.Build.Step, lab: std.Build.LazyPath, name: []const u8) *std.Build.Step.Run {
    const run = b.addRunFile(lab);
    run.setName(name);
    run.step.dependOn(install);
    return run;
}
