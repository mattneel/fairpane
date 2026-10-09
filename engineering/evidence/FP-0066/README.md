# FP-0066 evidence

## Scope

Task `FP-0066` makes release builds independent of the build directory.
The frozen contract is `engineering/evidence/FP-0066/CONTRACT.md` with amendment 1, under which the integrator installed both WSL tools before dispatch.
The worker implemented it in an isolated working tree whose `HEAD` was `f31eb22b72588b095e3b031ecf7606665c37fd6e`.
The Windows host was Windows 10.0.26200 on x64 with Node v26.7.0 and the locked Zig `0.18.0-dev.120+9fe22a29b`.
The Linux host was WSL Ubuntu with Linux 7.2.6, the locked `x86_64-linux` Zig, and Node v26.7.0.
No protected path changed, and the build type 1 command, `zig build -Doptimize=ReleaseSafe --prefix zig-out`, is unchanged.
The worker did not commit, push, or dispatch a workflow run.

## Changes

- `build.zig`: `libraryArchive` builds the installed static library.
  It compiles `src/root.zig` as the object `fairpane_zcu` with `strip` set in every mode other than Debug.
  A build step then runs the locked compiler's `zig ar --format=<layout> rcsD` with the object, so the library's one member is named by the object's base name and every member header has a zero time stamp, owner, and group.
  The layout is `coff` for COFF targets, `darwin` for Mach-O targets, and `gnu` otherwise.
  `zig build` installs that archive under the same name as before, `lib/fairpane.lib` on Windows and `lib/libfairpane.a` elsewhere.
  The exported `fairpane` module and the unit tests keep their debug information.
- `build.zig`: the new step `library-test`, which `zig build test` runs, holds contract cases 1, 2, 4, and 5, a metadata check, and the unit tests of the check tool.
- `tools/zig/library_check.zig`: the first-party check tool of those cases.
  It parses the GNU, COFF, and BSD archive layouts, and its unit tests cover long names, BSD names, a cache directory in a member name, a nonzero time stamp, every malformed-archive error, and the path search.
- `engineering/decisions/0009-release-and-stewardship.md`: the section "Library rules" states both rules, the contract's measurements, the measurements of this task, and that a release's debug information is out of scope until a later task defines a reproducible form for it.
  The section "Build type 1" states that `build.zig` defines what the unchanged command installs.
- `tools/README.md`: the library rules and the `library-test` cases under "Produce release records".

## Test cases

`zig build library-test` builds a ReleaseSafe library from each of two copies of `src`, `fp0066-tree-a/src` and `fp0066-tree-b/src`, which a `WriteFiles` step places in a cache directory.
The two libraries therefore differ in their source directory and in the cache directory of every compiler output.

| Case | Build step or command |
| --- | --- |
| 1 | `library_check same` compares the two ReleaseSafe libraries byte for byte. |
| 2 | `library_check absent` searches the library of `fp0066-tree-a` for the name `fp0066-tree-a`, the absolute paths of that tree, of the build root, and of the local cache, the compiler installation directory, and the compiler's `lib` directory. The search ignores ASCII letter case and treats `/` and `\` as the same byte. |
| 3 | `node tools/fairpane.mjs abi-exports` on the installed ReleaseSafe library. |
| 4 | `library_check names` confirms that the object of a Debug library built from `src` names the absolute path of `src`. |
| 5 | `library_check members` requires the member list to be exactly `fairpane_zcu.obj` for a Windows target and `fairpane_zcu.o` for another target. |

A sixth step, `library_check metadata`, requires every member header of the ReleaseSafe library to hold 0 or nothing as its time stamp, owner, and group.

## Criterion mapping

| Criterion | Evidence |
| --- | --- |
| Cases 1, 2, and 5 fail before the change. | `raw/tests-before.log`: `zig build library-test` exits with 1. Cases 1, 2, and 5 fail, and case 4, the metadata step, and the 6 tool tests pass. Case 2 finds the tree name, the tree, build-root, and cache paths, the compiler directory, and its `lib` directory. Case 5 lists the member `out\fp0066-before\o\e23c4dee94332a61c6d8557154433e88\fairpane_zcu.obj`. |
| Case 3 before the change. | `raw/tests-before.log`: the base ReleaseSafe build exits with 0, `abi-exports` passes with 15 exports, and `zig ar t` lists `out\fp0066-before-release-cache\o\b57abc32c89c5ecb0b35695e8b2f97d1\fairpane_zcu.obj`. |
| Cases 1, 2, 4, and 5 pass. | `raw/tests-after.log`, uncached on Windows: 81 of 81 steps and 306 of 306 tests pass. `raw/linux-run.log`, uncached on WSL Ubuntu: `library-test` passes 16 of 16 steps, and `zig build test` passes 78 of 78 steps and 306 of 306 tests. Linux has 3 fewer steps, because FP-0054 revision 1 case 3 runs only on Windows hosts. |
| Case 3 passes: `abi-exports` on the ReleaseSafe library. | `raw/release-libraries.log` on Windows and `raw/linux-run.log` on Linux: `abi-exports` passes with 15 exports. |
| A mutation control that removes the strip setting fails case 2. | `raw/mutation.log` with `raw/mutation-strip.diff`: cases 1 and 2 fail, and case 2 finds the tree name, its paths, and both compiler paths. |
| A mutation control that keeps the cache directory in the member name fails case 5. | `raw/mutation.log` with `raw/mutation-member.diff`, which installs the compiler's own archive of the stripped object: cases 1 and 5 fail, and case 5 lists the member `out\fp0066-mutation-member\o\0ba5992f36e476f549d1d6b7d2853ea0\fairpane_zcu.obj`. Case 2 passes. |
| Every release mode installs a path-free library with one member and every `fp_` export. | `raw/release-libraries.log`: ReleaseSafe, ReleaseFast, and ReleaseSmall each build, pass `abi-exports`, list only `fairpane_zcu.obj`, pass `library_check absent` for the working tree and the compiler directory, and link and run `tests/c/abi_smoke.c`. All 22 commands exit with 0. |
| Other targets. | `raw/cross-libraries.log`: ReleaseSafe libraries for `aarch64-macos`, `aarch64-linux`, and `x86_64-windows-msvc` pass `abi-exports`, `members`, `metadata`, and `absent`. All 15 commands exit with 0. |
| `reproduce-check` reports `reproducible`. | The integrator runs it on the implementation commit. The worker ran it on scratch commit `00803cff8da2db46a3d58c8fa360f65fc3896cd5`, see "Scratch commit". `raw/reproduce-check-windows.log` and `raw/linux-run.log` each report `reproducible` with exit status 0 and removed work trees. |
| `zig fmt --check build.zig src tests` passes. | `raw/fmt.log`: exit status 0, and 0 for `zig fmt --check tools/zig`. |
| `node tools/fairpane.mjs test` passes. | `raw/controller-tests-after.log`: 212 of 212 cases, then `node tools/fairpane.mjs check` with exit status 0. |
| Baseline identity. | `raw/tests-before.log` records `HEAD`, the status, the staging command `git add -- build.zig tools/zig/library_check.zig`, and the staged blobs `build.zig` `4957dbc268efd030ec96001f7665585e84e09090` and `tools/zig/library_check.zig` `42ead8e42ec6d2c99c4141ffacc3bd488fc68dbc`. The staged `build.zig` adds the cases and a `libraryArchive` that builds the library as the base did. The final tree keeps the same `tools/zig/library_check.zig` blob. |
| Linux tools, amendment 1. | `raw/linux-tools.log`; see "Linux tools". |

## Measurements

| Library | Bytes | SHA-256 | Source |
| --- | --- | --- | --- |
| Base ReleaseSafe, Windows | 3,053,734 | `30dd4f10d48652cbffb6637ca45fb0e654d47770b9d91f42f61f7b3a3cca31e6` | `raw/release-libraries.log` |
| ReleaseSafe, Windows | 706,412 | `249d63f2dc832ffed237a63269ba0ce4edbde603d73625c68b07db9ccadc4f48` | `raw/release-libraries.log` |
| ReleaseFast, Windows | 25,708 | `5da5ec16db0cfcd916eb5656f7dbdcdef3ec4b452fccdbfcd21ac978c2c5a78a` | `raw/release-libraries.log` |
| ReleaseSmall, Windows | 25,514 | `a77911016983a41c2a5d96569c8dcb860b06488eeee5685fe096ff420ed6e4a8` | `raw/release-libraries.log` |
| ReleaseSafe, Linux | 644,396 | `30a44076be407b8647dbe1ce9f9b01eb039a975bfa8f9f90ef776ed0981c43e1` | `raw/linux-run.log` |

The ReleaseSafe library of the working tree on Windows has the same SHA-256 as both libraries of the Windows `reproduce-check`, and the ReleaseSafe library of the WSL clone has the same SHA-256 as both libraries of the Linux `reproduce-check`.
`raw/archive-format.log` shows that the base Windows library already had the COFF layout, two linker members, and zero time stamps, owners, and groups; only its member name and its debug information depended on the build.

## Scratch commit

`raw/reproduce-scratch.log` clones the working tree's repository into `out/fp0066-scratch` with `git clone --no-local`.
It applies `git diff HEAD` of `build.zig`, `tools`, and `engineering/decisions` and commits the result as `00803cff8da2db46a3d58c8fa360f65fc3896cd5`, whose parent is the base.
It then links the clone's `.tools` to the installed compilers, because `reproduce-check` and the gates read the locked compiler from the repository.
After that commit, the worker added one sentence to ADR 0009 and wrote this file; neither affects a build.
`raw/gates-scratch.log` shows that the clone and the working tree have the same `build.zig` and `tools/zig/library_check.zig` blobs, and that the gates `zig-build`, `c-abi`, `cross-windows-x86_64`, `cross-linux-aarch64`, and `cross-macos-aarch64` pass there.
The WSL run in `raw/linux-run.log` clones the scratch repository into `$HOME/fairpane-linux/work/FP-0066/repo`, checks out the scratch commit with no status lines, and links `.tools/zig/0.18.0-dev.120+9fe22a29b/x86_64-linux` to the installed compiler.

## Linux tools

The assignment named the Linux compiler at `$HOME/fairpane-linux/tools/zig/0.18.0-dev.120+9fe22a29b/x86_64-linux/zig`.
The first command of `raw/linux-tools.log` exits with 127, because no file exists there.
`engineering/evidence/FP-0067/raw/linux-baseline.log` extracted the compiler to `$HOME/fairpane-linux/tools/zig-x86_64-linux-0.18.0-dev.120+9fe22a29b`.
The second command runs it by that path and reports `0.18.0-dev.120+9fe22a29b`, the same path as `zig_exe` and its `lib` directory as `lib_dir`.
It also reports Node `v26.7.0` on `linux x64` by `$HOME/fairpane-linux/node/bin/node`, and `Linux 7.2.6-locietta-WSL2-xanmod1`.
The worker installed nothing.

## Failed and abandoned attempts

| Log | Cause |
| --- | --- |
| `raw/tests-before-attempt-1.log` | The first before-run of the harness. Cases 1, 2, and 5 failed as in `raw/tests-before.log`, and the metadata step also failed, because the GNU and COFF name table `//` leaves its time stamp, owner, and group blank. The tool then accepted a blank field, and the harness was staged after that change. |
| `raw/library-test-after-attempt-1.log` | `build.zig` compared the optimize mode with the deprecated declaration `.Debug`, which the locked compiler rejects in a comparison. The final code uses `.debug` and `.safe`. |
| `raw/library-test-after-attempt-2.log` | The first complete after-run, cached in `out/fp0066-after-attempt-2`: 16 of 16 steps pass. It is superseded by `raw/tests-after.log`, not failed. |
| `raw/gates.log` | Each gate failed in the working tree with "The locked compiler is absent", because the working tree has no `.tools` directory. `raw/gates-scratch.log` ran them in the scratch clone. |

## Open items

- Closed: the integrator ran `reproduce-check` on the implementation commit on Windows and on WSL Ubuntu; see `raw/integration-reproduce-windows.log` and `raw/integration-reproduce-linux.log`.
- The Linux compiler path in the assignment differs from the installed path; see "Linux tools".

## Integration

The integrator applied the worker's patch and committed it alone as `81481a3`.
`raw/integration-commit.log` records `git ls-tree` for that commit, with the worker's final blobs `31c7fd20` for `build.zig` and `42ead8e4` for `tools/zig/library_check.zig`, and `git show --stat` with parent `775d988` and the 24 files of the patch.
The worker's report was right about the Linux compiler path: the integrator's assignment named a directory layout that does not exist, and the installed compiler is the one the worker used.

- `raw/integration-binding.log` records `HEAD` `81481a3` and a status that includes ignored files for every source root, before and after the runs below; both statuses are empty.
- `gates/2026-10-09T14-50-08-364Z-repo-check-2e4e7a2e.json`, `gates/2026-10-09T14-50-08-694Z-controller-test-caaaf587.json`, and `gates/2026-10-09T14-50-58-732Z-zig-test-a7bead4e.json` pass.
- `raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0066-integration`: 81 of 81 build steps and 306 of 306 tests pass.
- `raw/bun-selftest.log` records Bun 1.4.2 and `tools/selftest.mjs` with 220 of 220 tests.
- `raw/integration-reproduce-windows.log` runs `reproduce-check` for `81481a373eed462a345fdd640870abd5743bb179` on Windows: `reproducible`, exit status 0, with `lib/fairpane.lib` `249d63f2…` in both builds and both work trees removed.
  An earlier attempt with the abbreviated ID failed with "The candidate must be a full 40-hex commit ID." and exit status 1; `raw/integration-reproduce-windows-attempt-1.log` keeps it.
  The integrator had first appended that attempt to the worker's `raw/reproduce-check-windows.log` in `7744e42`; review 1 found this, so the integrator moved the record byte for byte to its own log and restored the worker's log to its content at `81481a3`.
- `raw/integration-reproduce-linux.log` clones the repository at that commit in WSL Ubuntu with no status lines, links the locked Linux compiler into the clone's `.tools`, and runs `reproduce-check` with Node v26.7.0: `reproducible`, exit status 0, with `lib/libfairpane.a` `30a44076…` in both builds and both work trees removed.

## Review 1 findings

`reviews/review-1-accept.json` accepts with four minor findings and three notes.

- The integrator's blob check and the failed attempt's log are fixed above, and "Open items" now records the closed `reproduce-check` item.
- Case 3, `abi-exports` on the ReleaseSafe library, runs in no gate, so a later export regression in release builds alone would go unnoticed.
  The integrator proposes this for FP-0099 in a reviewed plan change.
- `find` in `tools/zig/library_check.zig` folds a copy of the whole library once for each needle, which is avoidable allocation and copying.
  The integrator proposes this for FP-0099 as well.
- Case 1's two builds share the build root and cache root; case 2's search and `reproduce-check` cover a dependence on them, so no change is needed.
- The contract names the workstream `laboratory`, while the plan gives `stewardship`; the plan is authoritative, and the contract text stays frozen.
