# FP-0007 task contract

## Identity

Task ID: `FP-0007`, "Build the inspectable headless laboratory".
Workstream: `laboratory`.
Base: commit `c9c243f`.
Prerequisites: `FP-0003` and `FP-0006`.
This contract is frozen before `FP-0003` is accepted, and implementation starts only after that acceptance.
Assigned role: `fairpane-core`.

## Sources

- `docs/QUALIFICATION.md`, "Required result categories" and "Anti-gaming rules".
- `docs/ARCHITECTURE.md`, which requires a replay transcript of host inputs.
- `engineering/decisions/0003-corpus-snapshots.md`, which names a corpus item by corpus name, revision, path, and blob ID.
- Andreas Zeller and Ralf Hildebrandt, "Simplifying and Isolating Failure-Inducing Input", IEEE Transactions on Software Engineering 28(2), 2002, for the `ddmin` algorithm.

## Behavior

### Laboratory program

`src/lab.zig` implements the laboratory, and `src/lab_main.zig` implements its command line.
`zig build lab` builds and installs the executable `fairpane-lab`.
The laboratory drives the engine through the Zig API in `src/engine.zig`.
It changes no C ABI declaration and no file under `include` or `api`.

### Case input

A case is one JSON document with `"format": "fairpane-lab-case"` and `"version": 1`.
Parsing is strict: an unknown field, a duplicate field, a missing required field, or a value of the wrong type is a harness error.
A case file larger than 64 MiB is a harness error, and the laboratory reads no byte beyond that bound.

| Field | Content |
| --- | --- |
| `corpus` | `null`, or an object with `name`, `revision`, `path`, and `blob`. `name` matches `[a-z0-9][a-z0-9-]*`, `revision` and `blob` are 40 lowercase hex digits, and `path` is a relative POSIX path without empty, `.`, or `..` segments. |
| `environment` | `time_origin_ms`, an integer from 0 to 2^53 - 1; `random_seed`, 64 lowercase hex digits; `viewport` with integer `width` and `height` from 1 to 65535 and `device_pixel_ratio_milli` from 1 to 64000; `locale` and `time_zone`, each 1 to 64 ASCII characters from `[A-Za-z0-9_+/-]`. |
| `document` | `url`, an absolute URL as ASCII text of 1 to 8192 bytes, and `body_base64`, canonical padded base64 or `null`. |
| `resources` | An array of objects with `url` and `body_base64`, as in `document`, where no two URLs are equal and none equals the document URL. |
| `limits` | `max_steps` from 0 to 1000000, `step_budget` from 1 to 1000000, `max_outstanding_requests` from 1 to 1024, and `max_response_body_bytes` from 0 to 64 MiB. |
| `expect` | An object with `stage` and stage-specific fields, described under "Outcomes". |

### Explicit inputs only

The laboratory creates one document and loads `document.url`.
It answers each issued request from the case only, by exact byte equality of the URL.
A request whose URL has a non-null body receives that body.
A request whose URL is absent or has a `null` body is cancelled, and the result records its answer as `unavailable`.
A body that the engine refuses with `error.LimitExceeded` is cancelled, and the result records its answer as `limit-exceeded`.
The laboratory opens no network connection and reads no file except the files named on its command line.

### Pipeline state

The result is one JSON document with `"format": "fairpane-lab-result"` and `"version": 1`.
It contains these members.

- `case`: the SHA-256 of the exact case file bytes.
- `corpus`: the case's `corpus` value, unchanged.
- `inputs`: the URL, byte length, and SHA-256 of the document and of each resource, and the case's `environment`.
- `environment_consumers`: for each environment field, the stages that consumed it; every list is empty while no stage consumes it.
- `stages`: the fixed sequence `fetch`, `decode`, `tokenize`, `tree`, `style`, `layout`, `paint`, `script`.
  Each stage has a `status` of `completed`, `failed`, `unsupported`, or `not-reached`.
  The `fetch` stage records each request's URL and answer, the document state, and the loaded body's length and SHA-256.
  Every stage that this task does not implement reports `unsupported`.
- `events`: every engine event in drain order.
  Document and request identifiers appear as ordinals in order of first appearance, so the result never contains a process-wide identifier.
- `steps`: the number of `Engine.step` calls.
- `outcome`: `result`, `stage`, `check`, `expected`, `observed`, and `detail`, where inapplicable members are `null`.

Two runs of one case produce byte-identical results.

### Outcomes

| Result | Condition | Exit status |
| --- | --- | --- |
| `pass` | The expectation's stage completed, and every checked value matches. | 0 |
| `fail` | The expectation's stage is implemented, and a checked value differs. `check` names the first differing field. | 1 |
| `unsupported` | The expectation names a stage that this task does not implement. The laboratory does not interpret its other fields. | 2 |
| `harness-error` | The case or command line is invalid, a file cannot be read, or the engine returns an error that the case's limits do not explain, including `error.OutOfMemory`. | 3 |
| `timeout` | The document is still loading after `max_steps` calls to `Engine.step`. | 4 |

A `fetch` expectation has `document_state`, either `loaded` or `failed`, and `body_sha256`, which is 64 lowercase hex digits when the state is `loaded` and `null` otherwise.
The laboratory checks `document_state` first, then `body_sha256`.
A usage error exits with status 64 and writes no result.

### Replay

`fairpane-lab run <case> --transcript <path>` also writes a transcript of every host action.
The actions are `create_document`, `load`, `respond` with the body in base64, `cancel`, and `step` with its budget.
After each action, the transcript records the normalized events that the laboratory drained.
`fairpane-lab replay <transcript>` repeats the actions against a new engine and compares every drained event and the final document state.
An identical replay reports `pass`.
The first difference reports `fail` with the action index, the expected events, and the observed events.
A malformed or truncated transcript reports `harness-error`.

### Fixture minimization

`src/lab.zig` implements `ddmin` over a byte sequence with a caller-supplied deterministic predicate.
The predicate holds for the input, and the output is a subsequence for which it still holds.
The output is 1-minimal: removing any single byte makes the predicate false.

`fairpane-lab minimize <case> --out <path>` minimizes a case whose outcome is `fail` or `timeout`.
Its predicate holds when a run of the candidate case has the same `result`, `stage`, and `check` as the original run.
It first removes whole resources, one at a time while the predicate holds, and then applies `ddmin` to the document body.
It writes the minimized case and reports the predicate run count.
A case with any other outcome reports `harness-error` and writes nothing.

## Exact test cases

The cases live in `src/lab.zig`, except that cases 13 and 14 run the installed executable through `zig build test`.

1. A valid case parses.
   One fixture per condition reports `harness-error` with a distinct message: an unknown field, a duplicate field, a wrong `format`, a wrong `version`, invalid base64, an uppercase hex digit in `revision`, a `..` path segment, a missing environment field, a duplicate resource URL, and `step_budget` 0.
2. A case with a body and a matching `fetch` expectation reports `pass`.
   Its `fetch` stage is `completed` with the body's length and SHA-256, every other stage is `unsupported`, and every environment field has an empty consumer list.
3. A mismatching `body_sha256` reports `fail` with `check` `body_sha256` and both values, and a mismatching state reports `check` `document_state`.
4. An expectation for the `tree` stage reports `unsupported` with `stage` `tree`.
5. A `null` document body cancels the request, records `unavailable`, and fails the document, and a matching `failed` expectation reports `pass`.
6. A document URL that names a loopback listener still loads the case bytes, and the listener accepts no connection.
7. Two runs of one case produce byte-identical results without process-wide identifiers.
8. `max_steps` 0 reports `timeout`.
9. The result's `case` equals the SHA-256 of the case file bytes, and its `corpus` equals the case's value.
10. A replay of a recorded transcript reports `pass`.
    Changing one recorded event reports `fail` at that action's index, and a truncated transcript reports `harness-error`.
11. `ddmin` reduces `xxaxxbxx` under the predicate "contains `a` before `b`" to `ab`.
    Its result is 1-minimal, and an input for which the predicate is false returns an error.
12. `std.testing.checkAllAllocationFailures` runs case parsing and a complete run.
    Each induced failure reports `harness-error` and leaks nothing.
13. The executable's exit status is 0, 1, 2, 3, and 4 for the outcomes of cases 2, 3, 4, 1, and 8, and 64 for an unknown command.
14. `minimize` turns a failing `fetch` case with a 4096-byte body into a case that fails the same check with a 1-minimal body, and it refuses a passing case.

## Evidence

Record `tests-before.log`, an uncached `tests-after.log`, and a mutation control under `engineering/evidence/FP-0007/raw/`.
The mutation control reports `completed` for every stage, stores its exact diff beside its log, and fails case 2 or case 4.
The integrator records `HEAD`, the staged diff, and file hashes before it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0007/gates`.

## Authority

Writable paths: `src`, `tools`, `tests`, and `build.zig`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No decoding, tokenizing, tree construction, style, layout, paint, or script stage exists in this task.
- No corpus item runs in this task; the laboratory only carries corpus identifiers.
- Process-level crash and wall-clock timeout classification belongs to the runner that executes the laboratory, such as the controller's `record` command.
