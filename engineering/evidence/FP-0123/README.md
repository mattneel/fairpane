# FP-0123 evidence

## Scope

Task `FP-0123` implements the Encoding Standard labels, the decode hooks, and the UTF-8, UTF-16BE, UTF-16LE, replacement, and x-user-defined decoders.
The frozen contract is `engineering/evidence/FP-0123/CONTRACT.md`, frozen at `4465aa9`.
The normative baseline is whatwg/encoding `a985b62a9b45c17da3e17a9f0a0b4e30c34c4a8a`.
The `fairpane-core` worker `FP0123Encoding` implemented it in an isolated working tree whose `HEAD` was `4465aa94966dc211c0c8a2a63f64a7a2cbdf7dba`.
The host was Windows 10.0.26200.9457 on x64 with Node v26.7.0 and the locked Zig `0.18.0-dev.120+9fe22a29b`.
No protected path changed, and `specs/applicability/wpt.json` is unchanged.
[INFERENCE] Other agents ran builds on the same host, so every local duration includes some contention; no log records those builds.
[INFERENCE] The worker did not commit or push; no log records that.

## Changes

- `src/encoding/root.zig`: `Encoding` (40 tags in table order), `name`, `fromName`, `labels`, `getEncoding`, `outputEncoding`, `unsupportedOwner`, `bomSniff` with `Bom`, `ErrorMode`, `Status`, `Result`, `Decoder`, `Decode`, and `Utf8Decode`.
  A compile-time check ties each tag to its table row's name.
- `src/encoding/labels.zig`: the 40 names and 228 labels of §4.2, with the WHATWG attribution, the BSD 3-Clause statement, the `LICENSE` blob `f2dcda46deccefd245749202a88a7837e35c6daa`, and a reference to `src/html/entities.LICENSE`.
- `src/encoding/utf8.zig`: the UTF-8 handler and `Scalars`, a one-shot iterator over a complete byte sequence. It imports only `std`.
- `src/encoding/utf16.zig`: the shared UTF-16 handler.
- `src/encoding/tests.zig`: cases 1 to 13, case 14's text scan, and case 16.
- `src/root.zig`: exports `encoding` and references it in `test`.
- `src/web_string.zig`: `fromUtf8`, `fromUtf8Lossy`, `decodeUtf8`, and `codeUnitIndexForUtf8Offset` run `utf8.Scalars`; `Utf8Decoder` is removed; case 14's new test.
- `src/lab.zig`: `decode` completes for all three byte order marks through `encoding.bomSniff` and `encoding.Decoder` in "replacement" mode; the laboratory encoding type is `encoding.Encoding`, parsed with `fromName` and written with `name()`; the module comment and the comments of the old lines 193 and 1091 to 1095 are updated; `WebString` is no longer imported; FP-0008 case 21 is revised; Lab-2 to Lab-6, Lab-9, and Lab-10 are new.
- `tests/lab/fp0123-*.json`: six case 15 fixtures.
- `build.zig`: the six fixtures in `lab_fixtures`, and the Lab-7 exit-status case.
- `specs/sources.json`: `S102`, "Encoding Standard at whatwg/encoding a985b62a", at the URL of `encoding.bs` at the pin. `S88` is unchanged.

## Criterion mapping

| Plan criterion | Cases and evidence |
| --- | --- |
| 1. Pin, names, labels | Cases 1 to 4 pass in `raw/tests-after.log`. `raw/encoding-standard-pin.log` is the integrator's record. `raw/labels-vs-spec.log` compares `src/encoding/labels.zig` with the table in the pinned `encoding.bs` (SHA-256 `90bd4f43…1c55`): 40 names and 228 labels on both sides, identical. It also records `git hash-object` of `encoding.bs` (`684c72d8…`) and of `LICENSE` and `src/html/entities.LICENSE` (both `f2dcda46…`). `integrator-label-count.log` is the integrator's step. |
| 2. Five streaming decoders and both error modes | Cases 5 to 8, 12, 13, and 16 pass in `raw/tests-after.log`. M1 to M5 and M9 fail them in `raw/mutation.log`. |
| 3. Hooks, and other encodings unsupported with owners | Cases 9 to 11 pass in `raw/tests-after.log`. M6 fails T1, T2, T3, and case 12 on G1. |
| 4. One UTF-8 decoder | Case 14 passes in `raw/tests-after.log`: the `web_string` regression tests are unchanged and pass, the new row passes, and the text scan finds no `Utf8Decoder`, `bytes_needed`, or `lower_boundary` and finds `@import("encoding/utf8.zig")`. M1 and M2 fail the named `web_string` tests. |
| 5. UTF-16 byte order marks in the laboratory | Case 15 passes in `raw/tests-after.log`, including the Lab-7 exit-status step. M8 fails Lab-1's UTF-16BE fixture, Lab-3, Lab-6, and Lab-7. |
| 6. Errors and replacement exact | Cases 5 to 10 and 15 pass with exact output, error counts, statuses, and `read` values. |
| 7. Added run-step time | See "Run-step time". |

## Run-step time

| Log | Unit-test run step | Tests in that step | Build summary | `zig build test` |
| --- | --- | --- | --- | --- |
| `raw/tests-base.log` | 36 s | 271 | 100/100 steps; 322/322 tests | 54678 ms |
| `raw/tests-after.log` | 33 s | 299 | 101/101 steps; 350/350 tests | 50725 ms |

The unit-test run step changed by −3 seconds, which is within the stop rule's limit of +10 seconds.
Both runs used a fresh `--cache-dir` and the shared `ZIG_GLOBAL_CACHE_DIR`.
The 28 added unit tests are 19 in `src/encoding/tests.zig`, the unnamed `test` block of `src/encoding/root.zig`, 1 in `src/web_string.zig`, and 7 in `src/lab.zig`.
The extra build step is the Lab-7 exit-status case.
The `zig-test` gate at `b68eebf` took 46,060 ms, as its receipt `gates/2026-10-09T18-39-59-489Z-zig-test-0569155d.json` records; "Integration" lists every receipt.

## Before the change

`raw/tests-before.log` records these commands in order.

1. `git rev-parse HEAD`: `4465aa94966dc211c0c8a2a63f64a7a2cbdf7dba`.
2. The staging command `git add -- build.zig src/root.zig src/encoding/root.zig src/encoding/tests.zig src/web_string.zig src/lab.zig` and the six `tests/lab/fp0123-*.json` fixtures.
3. `git diff --cached --name-status` and `git ls-files --stage`. The staged blobs are `build.zig` `d59edc8a`, `src/encoding/root.zig` `5095a1a6`, `src/encoding/tests.zig` `f4c5f7db`, `src/lab.zig` `987654bc`, `src/root.zig` `0b7d2d80`, `src/web_string.zig` `ea35bc7f`, and the fixtures `f0bf87ed`, `e2f7958f`, `5921fdbf`, `fef2d2de`, `d08ad806`, and `916b85b9`.
4. `zig build test --summary all --cache-dir out/fp0123-before`, `exit_code` 1.
   The unit-test compile step fails with `src\encoding\tests.zig:9:26: error: root source file struct 'encoding.root' has no member named 'Encoding'` and the same error for `Status`.
   The Lab-7 step also fails, because the base laboratory reports `unsupported` for the UTF-16BE fixture.

The staged `src/encoding/root.zig` (`5095a1a6`) held only its module comment and `test { _ = @import("tests.zig"); }`, so the compile error names the missing declarations, as "Before the change" requires.

`raw/tests-before-lab.log` records these commands in order.

1. `git rev-parse HEAD`, then `git reset -q -- src/root.zig src/encoding`, a `cmd` command that moves `src/encoding` and a copy of `src/root.zig` into `out/fp0123-stash`, and `git checkout -- src/root.zig`.
2. The staging command `git add -- build.zig src/web_string.zig src/lab.zig` and the six fixtures, then `git diff --cached --name-status`, `git ls-files --stage`, and `git status --porcelain=v1`. `src/root.zig` has its base blob `df4e8065`, and the other staged blobs are those of `raw/tests-before.log`.
3. `zig build test --summary all --cache-dir out/fp0123-before-lab`, `exit_code` 1, with `323/330 tests passed (7 failed)` and the unit-test step at 272 pass and 7 fail.
   The failing tests are Lab-1 (revised FP-0008 case 21: "expected .fail, found .unsupported"), Lab-2, Lab-3, Lab-4, and Lab-9 ("expected .pass, found .unsupported"), Lab-5 ("expected .unsupported, found .harness_error"), and Lab-6.
   The Lab-7 step fails because `"result": "pass"` is missing from its output.
   Lab-8 (FP-0007 case 2 and FP-0008 cases 18, 23, 24, and 26), Lab-10, case 14's new `web_string` row, and every other `web_string` test pass.
4. A `cmd` command that moves the stashed files back, and `git hash-object` showing `src/root.zig` `0b7d2d80`, `src/encoding/root.zig` `5095a1a6`, and `src/encoding/tests.zig` `f4c5f7db`, the blobs of `raw/tests-before.log`.

### Test changes after the before logs

`raw/test-changes.log` records `git diff` between the before blobs and the final blobs.

- `src/lab.zig` (`987654bc` to `f69f8a4c`): only the implementation changed; every test is byte-identical to the before blob.
- `src/web_string.zig` (`ea35bc7f` to `b7870822`): only the implementation changed; the case 14 test is unchanged.
- `src/encoding/tests.zig` (`f4c5f7db` to `728b3054`): the harness reports every failing row, so a mutation log names each failing row rather than the first one.
  `expectRows` and the case 12 driver continue after a failing row and fail at the end.
  Case 9's G16, T1, T2, and T3 moved into four tests of their own, so each reports separately.
  No row, input, or expected value changed.
- `src/root.zig` keeps blob `0b7d2d80` from the before stage.

## Mutation controls

`raw/mutation.log` runs each control in turn: `git hash-object` of the file, `git apply` of the diff, `git hash-object`, `zig build test --summary all --cache-dir out/fp0123-mutation`, `git apply -R`, and `git hash-object`.
Every `git apply` and `git apply -R` exits with 0, and every file returns to its original blob.
Each diff is `raw/mutation-M<n>.diff`.

| Control | File: before, during, after | Result |
| --- | --- | --- |
| M1: the UTF-8 handler consumes the out-of-range byte (`return .failure` in place of `return .failure_restore`). | `utf8.zig`: `886db77d`, `6301afcb`, `886db77d` | `exit_code` 1; 293 pass, 6 fail. Case 5 fails on A18 to A24, A28, A29, A30, A35, and A36; case 12 fails on the same rows; `web_string` tests 6, 7, 16, and FP-0047 case 2 fail. The required A28, A29, A30, and `web_string` test 6 fail. |
| M2: the ED upper boundary is not applied. | `utf8.zig`: `886db77d`, `6f33e4ef`, `886db77d` | `exit_code` 1; 294 pass, 5 fail, and 1 leak. Case 5 and case 12 fail on A20 and A21; `web_string` tests 5 and 7 and the FP-0123 case 14 test fail, the last with "expected error.InvalidUtf8, found @fromBackingInt(0)". The leak is the string that the mutated `fromUtf8` returned in `web_string` test 5, which that test does not expect to own. |
| M3: a non-trailing unit after a leading surrogate is dropped. | `utf16.zig`: `db8d313f`, `a9dff07d`, `db8d313f` | `exit_code` 1; 297 pass, 2 fail. Case 6 and case 12 fail on B7, B13, and C4. |
| M4: end-of-queue with a leading byte and a leading surrogate reports two errors. | `utf16.zig`: `db8d313f`, `fc6ee249`, `db8d313f` | `exit_code` 1; 297 pass, 2 fail. Case 6 and case 12 fail on B12 and C8. |
| M5: the replacement decoder reports an error on empty input. | `root.zig`: `c0034622`, `dedd9fe8`, `c0034622` | `exit_code` 1; 296 pass, 3 fail. Case 7 and case 12 fail on D1, and case 8 fails at F6's empty-input call. |
| M6: `Decode` decides from the first chunk (`p.len != 0 or last` in place of `p.len == 3 or last`). | `root.zig`: `c0034622`, `b2844a56`, `c0034622` | `exit_code` 1; 295 pass, 4 fail. T1 ("expected null, found .utf_16le"), T2, T3, and case 12 fail; case 12 fails on G1 first, at partition mask 1, and on G2 to G7, G9, G11, G13, G17, G18, H1, and H4. |
| M7: `getEncoding` does not trim ASCII whitespace. | `root.zig`: `c0034622`, `fcc10bb0`, `c0034622` | `exit_code` 1; 298 pass, 1 fail. Case 3 fails on its first whitespace variant, `"\t\n\x0c\r unicode-1-1-utf-8\t\n\x0c\r "`. |
| M8: the laboratory maps both UTF-16 byte order marks to UTF-16LE. | `lab.zig`: `f69f8a4c`, `7bd028bb`, `f69f8a4c` | `exit_code` 1; 296 pass, 3 fail, and the Lab-7 step fails. Lab-1 fails on its UTF-16BE fixture (expected `UTF-16BE`), and Lab-3 and Lab-6 fail. |
| M9: fatal mode writes U+FFFD and continues (`false and d.mode == .fatal`). | `root.zig`: `c0034622`, `55df0d32`, `c0034622` | `exit_code` 1; 296 pass, 3 fail. Case 8 fails on F2, F3, F4, F5, and F8, case 10 on H7, and case 12 on the same rows. |

M6 and M9 keep every parameter referenced, because Zig rejects an unused parameter, so a plain `return true` or `if (false)` would not compile.

## Records

Every command ran through `node tools/fairpane.mjs record`, and every Zig command had `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
The worker deleted and overwrote no log.

| Log | Result |
| --- | --- |
| `raw/encoding-standard-pin.log` | The integrator's record before the freeze. |
| `raw/tests-base.log` | The deletion of `out/fp0123-base` (absent), `git rev-parse HEAD` and `git status --porcelain=v1` (0), and `zig build test --summary all --cache-dir out/fp0123-base` (0): 100/100 steps and 322/322 tests. |
| `raw/tests-before.log` | See "Before the change". |
| `raw/tests-before-lab.log` | See "Before the change". |
| `raw/tests-after-attempt-1.log` | A passing development run, `exit_code` 0, with `--cache-dir out/fp0123-dev`: 101/101 steps and 346/346 tests, 295 in the unit-test step. It preceded the harness change in "Test changes after the before logs", so `raw/tests-after.log` supersedes it. |
| `raw/tests-after-attempt-2.log` | `zig fmt --check build.zig src tests` (0) and a passing development run (0) after the harness change: 299 unit tests; the library-test step was cached, so its total is 344/344. It used the reused development cache, so `raw/tests-after.log` supersedes it. |
| `raw/tests-after-attempt-3.log` | A failed invocation: the worker put `--env` after the log path, so the recorder reported "The executable is not on PATH: --env" and no build ran. Its deletion of `out/fp0123-after`, `ver`, `git rev-parse`, `git status`, and `git hash-object` records exit with 0. |
| `raw/tests-after.log` | The deletion of `out/fp0123-after` (absent), `cmd /d /c ver` (Windows 10.0.26200.9457), `git rev-parse HEAD`, `git status --porcelain=v1`, `git hash-object` of every changed file, and `zig build test --summary all --cache-dir out/fp0123-after`, `exit_code` 0: 101/101 steps and 350/350 tests. |
| `raw/fmt-attempt-1.log` | `zig fmt --check build.zig src tests`, `exit_code` 1, listing `src\encoding\root.zig`. The locked `zig fmt` rewrites `@intFromEnum` to `@backingInt` and `@enumFromInt` to `@fromBackingInt`. The log then records `zig fmt src/encoding/root.zig` (0), which applied those four rewrites. |
| `raw/fmt.log` | `zig fmt --check build.zig src tests`, `exit_code` 0, before the controls, and again, `exit_code` 0, after `raw/tests-after.log`. |
| `raw/controller-tests-after.log` | `node --version` (v26.7.0) and `node tools/fairpane.mjs test`, `exit_code` 0, with 238 of 238 tests. |
| `raw/labels-vs-spec.log` | The comparison script's text, its run (0), and `git hash-object` of the pinned files (0); see criterion 1. The script was a throwaway file under `out/`, so the log keeps its full text. |
| `raw/test-changes.log` | `git diff` (0) between the before and final test blobs; see "Test changes after the before logs". |
| `raw/mutation.log` | See "Mutation controls". |
| `raw/repo-check-after.log` | `node tools/fairpane.mjs check`, `exit_code` 0, `"result": "pass"` at the bootstrap-integrity level. |

## Resolved ambiguities

1. **Attribution line.** A Zig file cannot begin with bare text, so `labels.zig` begins with `//! Copyright © WHATWG (Apple, Google, Mozilla, Microsoft).`.
2. **Stub for the before run.** The before run needs `src/encoding/root.zig` to exist for the error to name missing declarations, so the staged stub holds only the module comment and the test import.
3. **UTF-8 restore.** The UTF-8 handler restores only the byte it is handling, so a restored byte is never consumed: the handler returns `failure_restore`, and the driver reads the same byte again. Its state is then initial, so a byte restores at most once. This is the "unread the current byte" strategy of "Implementation considerations".
4. **UTF-16 restore.** Restoring the two bytes and reading them again sets the leading byte, then forms the same code unit with no leading surrogate. That unit is not a trailing surrogate, so the handler takes those steps directly: it returns an error and either sets the leading surrogate or returns the unit as a scalar value. The output, error count, and state equal the standard's in every case. M3 removes exactly this path.
5. **Output space.** Every step, including end-of-queue, writes at most 2 units, so a call needs 2 free units before each step and otherwise returns `output_full`. The Rules guarantee progress only with 2 free units.
6. **Fatal `read`.** In "fatal" mode, the failing call's `read` includes the erroring byte, even when the handler restored it (F2: 3). At end-of-queue, `read` is the whole input (F4: 3; H7: 2).
7. **H7.** The contract states only `malformed`. Following the Rules, the test also requires written U+0041, `read` 2, and `errors` 1.
8. **Unsupported fallback.** `Decode` returns `error.UnsupportedEncoding` from the call that decides on an encoding without a decoder, and from every later call. After that call, `encoding()` names the fallback and `bomLength()` is 0.
9. **`bomSniff` and `Bom`.** The interface lists no BOM sniff function. `bomSniff` implements §6.1's "BOM sniff" and returns the mark's encoding with the byte count that "decode" reads, so `Decode` and the laboratory share one table.
10. **Laboratory decoding.** The laboratory calls `bomSniff` and then the mark's `Decoder` in "replacement" mode on the bytes after the mark, as the contract's "Laboratory" section states. The laboratory therefore owns the mark-to-encoding step that M8 mutates. Its output buffer holds the bound for the encoding plus the 2 free units that the last step needs, so one call always finishes.
11. **`u16` rows of case 3.** The `x-user-defined` + `C2 A0` row runs as bytes widened to units for `u16`, and a separate `u16` row uses U+00A0.
12. **Lab-5 validity.** "Is a valid case" is checked by the result `unsupported` with exit status 2; an invalid case reports `harness-error`.
13. **Lab-6.** The new `runDecodedUnderAllocationFailure` follows `runUnderAllocationFailure` and also requires `decode` `completed` for the run without an induced failure.
14. **UTF-8 end-of-queue.** The standard sets only "UTF-8 bytes needed" to 0 at end-of-queue. The handler resets every field, which no later step can observe.
15. **`specs/sources.json`.** The next free identifier was `S102`.

## Stop rules

- No frozen row contradicts `encoding.bs` at the pin. The worker read each row of cases 5 to 10 against §8.1.1, §14.1.1, §14.2.1, §14.5.1, §6, and §6.1 and found no contradiction; no log records that reading. Every row passes in `raw/tests-after.log`.
- `raw/labels-vs-spec.log` shows the expected blob IDs of `encoding.bs` and `LICENSE`.
- Removing `Utf8Decoder` changed no `web_string` result: every existing `web_string` test passes unchanged in `raw/tests-after.log`.
- The unit-test run step took 33 seconds, 3 seconds less than in `raw/tests-base.log`.

## Integration

Commit `b68eebf` applies the worker's `out/fp0123.patch`, blob `82dfab363b248c80ae667491587ee7e542c4b6d8`, on `3400a38`, and all 40 files apply cleanly.
That head holds `FP-0107`'s four-worker controller runner, `FP-0108`, `FP-0119`, and FP-0082 revision 2; `S102` was free in `specs/sources.json`.

- `raw/integrator-label-count.log` fetches `encodings.json` at `a985b62a9b45c17da3e17a9f0a0b4e30c34c4a8a` to `out/`, which is not committed (SHA-256 `078212b3…c9e7`, 8,913 bytes), and counts 40 names and 228 labels.
- `raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache directory `out/fp0123-integration`: `Build Summary: 101/101 steps succeeded; 378/378 tests passed`.
- `raw/integration-binding.log` records `HEAD` `b68eebf` and a status that includes ignored files before and after the four gates, which pass:

| Gate | Receipt | Duration |
| --- | --- | --- |
| `repo-check` | `gates/2026-10-09T18-39-08-910Z-repo-check-c733b89e.json` | 352 ms |
| `controller-test` | `gates/2026-10-09T18-39-09-702Z-controller-test-1685435d.json`, 247 of 247 | 49,148 ms |
| `zig-fmt` | `gates/2026-10-09T18-39-59-093Z-zig-fmt-0a369dd7.json` | 79 ms |
| `zig-test` | `gates/2026-10-09T18-39-59-489Z-zig-test-0569155d.json` | 46,060 ms |

- `raw/bun-selftest.log` records Bun 1.4.2 with 247 of 247 controller cases.
