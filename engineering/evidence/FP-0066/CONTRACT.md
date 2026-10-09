# FP-0066 task contract

## Identity

Task ID: `FP-0066`, "Make release builds independent of the build directory".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0027`, accepted.
The root integrator drafted and froze this contract after the measurements below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

### Measured inputs

`raw/probe.log` and `raw/strip-experiment.log` record these measurements of the ReleaseSafe library on Windows with the locked compiler.

- The library `fairpane.lib` of the FP-0027 revision 2 release build holds one member, `.zig-cache\o\61c2b72ff156fe963e2d6fc2510b6176\fairpane_zcu.obj`.
  That object contains the build directory name 5 times, in CodeView debug information that names absolute source paths.
  The same debug information also names the compiler's `lib\std` directory, so the bytes also depend on where the compiler is installed.
- `zig build-lib -static -OReleaseSafe` of `src/root.zig` at two different directories gives different libraries, with and without `-fstrip`.
  With `-fno-strip`, each library contains its directory name 5 times.
  With `-fstrip`, neither library contains its directory name, and the two extracted objects are byte-identical, SHA-256 `9dccdf15…`.
  The stripped libraries still differ, because each archive member name holds a cache directory, `cache\tmp\776c0874238e8dbc\fairpane_zcu.obj` and `cache\tmp\ebe8e787190647fb\fairpane_zcu.obj`.
- The locked compiler offers `-fstrip` and `-fno-strip` but no option that maps or removes source path prefixes.

### Integrator decisions

- A library that `zig build` installs in a mode other than Debug is built without debug information, so no source path enters it.
  Debug builds keep their debug information.
- The installed static library has exactly one member, named by its base name without a directory, written by a deterministic archive step.
  The archive step is first-party: a build step that runs the locked compiler's archiver in deterministic mode, or a first-party Zig tool; no third-party program joins the build.
- ADR 0009 states both rules, the measurements above, and that a release's debug information is out of scope until a later task defines a reproducible form for it.
- The release build command of build type 1 does not change, so its meaning does not change; the commit's `build.zig` defines the new behavior.
- The Linux run uses WSL Ubuntu with the locked `x86_64-linux` compiler, verified against the lock as in `engineering/evidence/FP-0067/raw/linux-baseline.log`, and Node.js v26.7.0 from <https://nodejs.org/dist/v26.7.0/>, checked against that release's `SHASUMS256.txt`, both installed under `$HOME/fairpane-linux` in WSL.

## Behavior

- `zig build -Doptimize=ReleaseSafe`, `-Doptimize=ReleaseFast`, and `-Doptimize=ReleaseSmall` install a library that contains no path of the build tree or of the compiler installation.
- The installed library's only member is named `fairpane_zcu.obj` on Windows targets and `fairpane_zcu.o` on other targets, with deterministic archive metadata.
- Every public `fp_` symbol stays exported, so `abi-exports` passes on each release library.
- `reproduce-check` reports `reproducible` for the implementation commit on Windows and on Linux.

## Exact test cases

1. Controller or build step: a ReleaseSafe build of the library at two different directories gives byte-identical installed files.
2. A ReleaseSafe library contains neither its build directory name nor the compiler installation directory, checked by a byte search of the installed file.
3. `node tools/fairpane.mjs abi-exports` passes on the ReleaseSafe library.
4. A Debug build keeps debug information: its object names at least one absolute source path.
5. The ReleaseSafe library's member list is exactly `fairpane_zcu.obj` on Windows and `fairpane_zcu.o` on Linux.

Cases 1, 2, and 5 must fail before the change.
A mutation control that removes the strip setting must fail case 2, and one that keeps the cache directory in the member name must fail case 5.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0066/raw/`, and keep each failed attempt as its own log.

1. `tests-before.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `mutation.log` and its diffs, with the hash of each changed file before, during, and after.
3. An uncached `tests-after.log` with `zig build test --summary all`, `controller-tests-after.log`, and `fmt.log`.
4. `node-linux-install.log` and `zig-linux-install.log` for the WSL tools, with their digest checks.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check`, `controller-test`, and `zig-test`.
The integrator then runs `node tools/fairpane.mjs reproduce-check <commit>` for the implementation commit on Windows and on WSL Ubuntu, records both, and requires `reproducible` with exit status 0 from each.

## Authority

Writable paths: `tools`, `build.zig`, `src`, `engineering/decisions`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No reproducible form of release debug information.
- No signing, publishing, or upload.
- No change to the source archive format or the provenance statement.
