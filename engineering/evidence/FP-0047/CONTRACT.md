# FP-0047 task contract

## Identity

Task ID: `FP-0047`, "Close the FP-0005 review findings".
Workstream: `substrate`.
Base: commit `7bc9ace`.
Prerequisites: `FP-0005`, accepted.
Assigned role: `fairpane-core`.
Source findings: `engineering/evidence/FP-0005/reviews/review-1-accept.json`.

## Behavior

`src/web_string.zig` keeps every behavior that FP-0005 accepted.
This task adds tests and evidence only, unless a new test exposes a defect.
A defect fix stays inside `src/web_string.zig` and names the failing case.

## Exact test cases

Each case lives in `src/web_string.zig` and runs through `zig build test`.

1. `fromUtf8` returns `error.InvalidUtf8` for `F0 80 80 80` and `F0 8F BF BF`.
2. `fromUtf8Lossy` maps `F0 80 80 80` to four U+FFFD units and `F0 8F BF BF` to four U+FFFD units.
3. `fromUtf8` decodes `E0 A0 80` to `{0x0800}`, `ED 9F BF` to `{0xD7FF}`, and `F0 90 80 80` to `{0xD800, 0xDC00}`.
4. `fromUtf8` returns `error.InvalidUtf8` for `F5 80 80 80` and `C1 BF`.
5. `fromUtf8Lossy` maps `F5 80 80 80` to four U+FFFD units and `C1 BF` to two.
6. `codeUnitIndexForUtf8Offset` returns `error.InvalidUtf8` for `"a\x80"` at offset 1 and at offset 5, so ill-formed input wins over an out-of-range offset.

## Mutation controls

Each control stores its source diff beside its log under `engineering/evidence/FP-0047/raw/`.

- Removing `if (byte == 0xF0) lower_boundary = 0x90;` fails case 1 or case 2.
- Widening the four-byte lead range to `0xF0...0xF7` fails case 4 or case 5.
- Counting a strict decoder failure as one code unit in `codeUnitIndexForUtf8Offset` fails case 6.

## Evidence

Record `tests-before.log`, `tests-after.log` with an uncached `zig build test --summary all`, and each mutation log and diff under `engineering/evidence/FP-0047/raw/`.
The integrator runs `repo-check`, `controller-test`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0047/gates`.

## Authority

Writable paths: `src`, `tests`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.
