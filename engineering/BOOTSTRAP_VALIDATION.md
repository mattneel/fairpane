# Bootstrap validation

## Scope

These results qualify preparation of this archive, not a browser or JavaScript engine.
The preparation host ran Linux x86_64 with Node v22.16.0.
GCC 14.2.0 supplied the C and C++ syntax checks.
No implementation task is accepted.

## Actual results

| Check | Result |
| --- | --- |
| Controller module syntax | Pass for all three JavaScript modules. |
| Controller selftests | 55 passed, zero failed. |
| Repository integrity and task graph | Pass, with 27 planned tasks and 19 required capability families. |
| Initial task selection | Only `FP-0001` is ready. |
| Local passed-gate receipts | Pass against the current source and policy digests. |
| Changed source, output, and gate definitions | Negative tests reject stale or altered receipts. |
| Missing executable, failed child, and hung child | Negative tests preserve failure and timeout outcomes. |
| Missing Zig compiler | The gate reports failure and does not claim execution. |
| Release qualification | Expected nonzero exit, with no release success claim. |
| C11 header and caller | Syntax-only pass with warnings treated as errors. |
| C++17 header | Syntax-only pass with warnings treated as errors. |
| POSIX wrapper | Syntax and help-command execution pass. |
| JSON and OMP frontmatter | Syntax checks pass. OMP execution remains untested. |
| Archive extraction | See the packaging record below. |

## Unexecuted paths

- The preparation environment contained no Zig executable.
- The compiler download attempt did not succeed in that environment.
- No Zig source compiled or executed during preparation.
- The C caller did not link to or execute the Zig library.
- PowerShell, OMP, and Bun did not execute during preparation.
- Windows, macOS, and cross-target runtime tests did not run.
- No HTML, CSS, JavaScript, WPT, Test262, GPU, or application conformance suite ran.

Task `FP-0001` must resolve the actual local environment and compile the candidate source.
It must check the installed OMP schema and prompt discovery.
A source repair must preserve the exact master pin and the founding policy.

## Evidence

`engineering/BOOTSTRAP_VALIDATION.json` contains actual commands, exits, and captured output.
The archive also retains local gate receipts and logs under `out/evidence`.
Those receipts contain absolute command paths from the preparation host.
Their source hashes use relative paths and remain checkable after extraction.

The receipts are unsigned local integrity records.
They do not establish independent release authority.
The Git ignore policy excludes local output from later commits.
Reviewed durable evidence belongs under `engineering/evidence`.

### Included receipt files

- `out/evidence/2026-10-08T23-09-34-005Z-repo-check-d8d2c96e.json`
- `out/evidence/2026-10-08T23-09-34-107Z-controller-test-69c613b5.json`
- `out/evidence/2026-10-08T23-11-23-342Z-zig-test-b9dff59e.json`

## Packaging record

A fresh extraction passed the ZIP CRC check and every file hash in the manifest.
The extracted repository passed its integrity check and all 55 controller tests.
The passed receipts also matched the extracted source and policy inventories.
`AGENTS.md` and `.omp` occupy the archive root without an enclosing directory.
No compiler binary, credential, font file, or third-party engine is bundled.

The manifest excludes its own checksum to avoid a self-reference.
The separate ZIP checksum covers the complete archive.
Neither checksum is a digital signature.
