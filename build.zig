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
    "fp0054-case-03-minimize-corpus.json",
    "fp0054-case-04-v1-derived.json",
    "fp0054-case-04-v2-missing-derived.json",
    "fp0054-case-04-v2-corpus.json",
    "fp0008-tokenize-pass.json",
    "fp0008-tokenize-token-count.json",
    "fp0008-tokenize-zero-digest.json",
    "fp0008-tokenize-wrong-errors.json",
    "fp0008-tokenize-errors.json",
    "fp0008-tokenize-no-bom.json",
    "fp0008-decode-utf16le-bom.json",
    "fp0008-decode-utf16be-bom.json",
    "fp0008-tokenize-null-body.json",
    "fp0008-decode-pass.json",
    "fp0008-decode-wrong-encoding.json",
    "fp0008-tokenize-replacement.json",
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
    .{ .case = 4, .file = "leaf_calls_behavior.zig", .status = 1, .stderr = &.{ "expected type", "expected type '*js.runtime.Runtime(.reference).Context(@fromBackingInt(15))', found '*js.runtime.Runtime(.reference).Context(@fromBackingInt(0))'" } },
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
    .{ .case = 34, .file = "leaf_reaches_heap.zig", .status = 1, .stderr = &.{"no field or member function named 'allocateString' in 'js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(0))'"} },
    .{ .case = 35, .file = "leaf_widens_context.zig", .status = 1, .stderr = &.{
        "expected type '*js.runtime.Runtime(.reference)', found '*js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(0))'",
        "expected type '*js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(15))', found '*js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(0))'",
    } },
    .{ .case = 36, .file = "binding_missing_kernel.zig", .status = 1, .stderr = &.{"fairpane-js: operation StubOperation has no kernel"} },
    .{ .case = 36, .file = "binding_stray_kernel.zig", .status = 1, .stderr = &.{"fairpane-js: kernel stub_kernel belongs to no operation"} },
};

const measured_representations = [_][]const u8{ "reference", "nan_box", "tagged_index" };
pub fn build(b: *std.Build) void {
    const expected = std.mem.trim(u8, @embedFile("toolchains/zig-version.txt"), "\r\n");
    if (!std.mem.eql(u8, builtin.zig_version_string, expected)) {
        std.debug.panic("Fairpane requires Zig {s}; found {s}", .{ expected, builtin.zig_version_string });
    }
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `zig build entities-generate` regenerates the committed named character reference table from the unedited `entities.json`.
    // FP-0008 contract case 3 compares the committed table with a parse of `entities.json`, so a stale table fails the tests.
    const entities_gen = b.addExecutable(.{
        .name = "fairpane-html-entities-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/html/entities_gen.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    const generate_entities = b.addRunArtifact(entities_gen);
    generate_entities.setName("generate the HTML named character reference table");
    generate_entities.addFileArg(b.path("src/html/entities.json"));
    const generated_table = generate_entities.addOutputFileArg2("entities_table.zig", .{});
    const update_table = b.addUpdateSourceFiles();
    update_table.addCopyFileToSource(generated_table, "src/html/entities_table.zig");
    const entities_step = b.step("entities-generate", "Regenerate src/html/entities_table.zig from src/html/entities.json");
    entities_step.dependOn(&update_table.step);

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

    const text_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/text/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fairpane", .module = module }},
    }) });
    const run_text_tests = b.addRunArtifact(text_tests);
    // FP-0013 case 12 reads the expectation generator and the import-tool declaration relative to the build root.
    run_text_tests.setCwd(b.path("."));
    run_text_tests.addFileInput(b.path("tools/fonts/font_expectations.py"));
    run_text_tests.addFileInput(b.path("engineering/dependencies.json"));
    test_step.dependOn(&run_text_tests.step);

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
    check_step.dependOn(&text_tests.step);
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

/// Adds FP-0007 contract cases 13 and 14, FP-0054 contract case 5 and revision 1 cases 1 to 5, and FP-0008 contract case 26,
/// which run the installed `fairpane-lab` executable.
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
        .{ .name = "FP-0008 case 26: case 18 passes with exit status 0", .args = &.{"run"}, .fixture = "fp0008-tokenize-pass.json", .status = 0 },
        .{ .name = "FP-0008 case 26: the token_count variant of case 19 fails with exit status 1", .args = &.{"run"}, .fixture = "fp0008-tokenize-token-count.json", .status = 1 },
        .{ .name = "FP-0008 case 26: the <p> case of case 21 is unsupported with exit status 2", .args = &.{"run"}, .fixture = "fp0008-tokenize-no-bom.json", .status = 2 },
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

    // The run mutates nothing in `tests/lab`: it names a private copy of a failing case, which minimize would otherwise overwrite.
    const copies = b.addWriteFiles();
    const input = copies.addCopyFile(b.path("tests/lab/case-03-body-mismatch.json"), "case.json");
    const guard = labRun(b, install, lab, "FP-0054 case 5: minimize refuses an --out path that names the input file through another spelling");
    guard.setCwd(copies.getDirectory());
    guard.addArg("minimize");
    // The input is an absolute path and the output is relative to the copy's directory: two spellings of one file.
    guard.addFileArg2(input, .{ .make_absolute = true });
    guard.addArgs(&.{ "--out", "case.json" });
    guard.expectExitCode(3);
    guard.expectStdOutMatch("\"result\": \"harness-error\"");
    guard.expectStdOutMatch("\"detail\": \"command line: the output path names the input file\"");
    test_step.dependOn(&guard.step);

    const unchanged = b.addRunArtifact(check);
    unchanged.setName("FP-0054 case 5: the refused minimization leaves the input unchanged");
    unchanged.addArg("same");
    unchanged.addFileArg(b.path("tests/lab/case-03-body-mismatch.json"));
    unchanged.addFileArg(input);
    unchanged.expectExitCode(0);
    unchanged.step.dependOn(&guard.step);
    test_step.dependOn(&unchanged.step);

    addRevision1Cases(b, test_step, install, lab, check);
}

/// Adds FP-0054 revision 1 cases 1 to 5.
/// Each case works in a directory that `check fresh` creates for the run,
/// so a guard regression cannot corrupt a cached copy that a later run reuses.
/// Every step that reads or writes that directory has side effects, so each run repeats it.
fn addRevision1Cases(
    b: *std.Build,
    test_step: *std.Build.Step,
    install: *std.Build.Step,
    lab: std.Build.LazyPath,
    check: *std.Build.Step.Compile,
) void {
    const fixture = b.path("tests/lab/case-03-body-mismatch.json");
    const harness_error = "\"result\": \"harness-error\"";

    const guards = [_]struct { case: u8, name: []const u8, layout: []const u8, args: []const []const u8 }{
        .{ .case = 1, .name = "minimize refuses an --out path that is a hard link to the input file", .layout = "link", .args = &.{ "minimize", "case.json", "--out", "link.json" } },
        .{ .case = 2, .name = "run refuses a --transcript path that is a hard link to the input file", .layout = "link", .args = &.{ "run", "case.json", "--transcript", "link.json" } },
        .{ .case = 3, .name = "minimize refuses an --out path that names the input file in other letter case", .layout = "case", .args = &.{ "minimize", "case.json", "--out", "CASE.JSON" } },
    };
    for (guards) |guard_case| {
        // Only Windows hosts add case 3, because other file systems may hold `case.json` and `CASE.JSON` as two files.
        if (guard_case.case == 3 and b.graph.host.result.os.tag != .windows) continue;
        const dir = freshDirectory(b, check, guard_case.case, guard_case.layout, fixture);
        const guard = revisionLabRun(b, install, lab, dir, b.fmt("FP-0054 revision 1 case {d}: {s}", .{ guard_case.case, guard_case.name }));
        guard.addArgs(guard_case.args);
        guard.expectExitCode(3);
        guard.expectStdOutMatch(harness_error);
        guard.expectStdOutMatch("\"detail\": \"command line: the output path names the input file\"");
        test_step.dependOn(&guard.step);

        const unchanged = revisionCheck(b, check, dir, b.fmt("FP-0054 revision 1 case {d}: the refused command leaves the input unchanged", .{guard_case.case}));
        unchanged.addArg("same");
        unchanged.addFileArg(fixture);
        unchanged.addArg("case.json");
        unchanged.step.dependOn(&guard.step);
        test_step.dependOn(&unchanged.step);
    }

    const copies = freshDirectory(b, check, 4, "copy", fixture);
    const distinct = revisionLabRun(b, install, lab, copies, "FP-0054 revision 1 case 4: minimize writes over a separate byte-identical copy of the input file");
    distinct.addArgs(&.{ "minimize", "case.json", "--out", "other.json" });
    distinct.expectExitCode(0);
    distinct.expectStdOutMatch("\"result\": \"pass\"");
    test_step.dependOn(&distinct.step);

    const derived = revisionCheck(b, check, copies, "FP-0054 revision 1 case 4: the written case is a version 2 case derived from the input digest");
    derived.addArgs(&.{ "derived", "case.json", "other.json" });
    derived.step.dependOn(&distinct.step);
    test_step.dependOn(&derived.step);

    const oversized = freshDirectory(b, check, 5, "oversized", null);
    const case_detail = "\"detail\": \"case file: exceeds the size limit\"";
    const run_case = revisionLabRun(b, install, lab, oversized, "FP-0054 revision 1 case 5: run reports a case file one byte above the size limit");
    run_case.addArgs(&.{ "run", "case.json" });
    run_case.expectExitCode(3);
    run_case.expectStdOutMatch(harness_error);
    run_case.expectStdOutMatch(case_detail);

    const minimize_case = revisionLabRun(b, install, lab, oversized, "FP-0054 revision 1 case 5: minimize reports a case file one byte above the size limit");
    minimize_case.addArgs(&.{ "minimize", "case.json", "--out", "minimized.json" });
    minimize_case.expectExitCode(3);
    minimize_case.expectStdOutMatch(harness_error);
    minimize_case.expectStdOutMatch(case_detail);

    const absent = revisionCheck(b, check, oversized, "FP-0054 revision 1 case 5: the failed minimization creates no output file");
    absent.addArgs(&.{ "absent", "minimized.json" });
    absent.step.dependOn(&minimize_case.step);

    const replay_transcript = revisionLabRun(b, install, lab, oversized, "FP-0054 revision 1 case 5: replay reports a transcript file one byte above the size limit");
    replay_transcript.addArgs(&.{ "replay", "transcript.json" });
    replay_transcript.expectExitCode(3);
    replay_transcript.expectStdOutMatch(harness_error);
    replay_transcript.expectStdOutMatch("\"detail\": \"transcript file: exceeds the size limit\"");

    const removal = revisionCheck(b, check, oversized, "FP-0054 revision 1 case 5: remove the oversized files");
    removal.addArgs(&.{ "remove", "case.json", "transcript.json" });
    removal.step.dependOn(&run_case.step);
    removal.step.dependOn(&absent.step);
    removal.step.dependOn(&replay_transcript.step);
    test_step.dependOn(&removal.step);
}

/// Returns a directory that `check fresh` replaces on every run with the files of `layout`.
fn freshDirectory(b: *std.Build, check: *std.Build.Step.Compile, case: u8, layout: []const u8, fixture: ?std.Build.LazyPath) std.Build.LazyPath {
    const run = b.addRunArtifact(check);
    run.setName(b.fmt("FP-0054 revision 1 case {d}: create a fresh directory", .{case}));
    run.has_side_effects = true;
    run.addArg("fresh");
    const dir = run.addOutputDirectoryArg2(b.fmt("fp0054-r1-case-{d}", .{case}), .{});
    run.addArg(layout);
    if (fixture) |path| run.addFileArg(path);
    run.expectExitCode(0);
    return dir;
}

/// Runs the installed laboratory executable in `dir` on every run.
fn revisionLabRun(b: *std.Build, install: *std.Build.Step, lab: std.Build.LazyPath, dir: std.Build.LazyPath, name: []const u8) *std.Build.Step.Run {
    const run = labRun(b, install, lab, name);
    run.setCwd(dir);
    run.has_side_effects = true;
    return run;
}

/// Runs the check executable in `dir` on every run, expecting exit status 0.
fn revisionCheck(b: *std.Build, check: *std.Build.Step.Compile, dir: std.Build.LazyPath, name: []const u8) *std.Build.Step.Run {
    const run = b.addRunArtifact(check);
    run.setName(name);
    run.setCwd(dir);
    run.has_side_effects = true;
    run.expectExitCode(0);
    return run;
}

/// Runs the installed laboratory executable after the `lab` installation step.
fn labRun(b: *std.Build, install: *std.Build.Step, lab: std.Build.LazyPath, name: []const u8) *std.Build.Step.Run {
    const run = b.addRunFile(lab);
    run.setName(name);
    run.step.dependOn(install);
    return run;
}
