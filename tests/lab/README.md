# Laboratory fixtures

These first-party case documents were written for tasks FP-0007 and FP-0054.
They exercise the `fairpane-lab` case format, its outcomes, and its minimizer.
They contain no upstream test content.
Their URLs name the reserved `example.test` domain, and the laboratory answers them from the case bytes only.

The `case-NN-*` prefix names the FP-0007 contract case that uses each fixture.
The `fp0054-case-NN-*` prefix names the FP-0054 contract case that uses each fixture.
The `case-01-*` fixtures other than `case-01-valid.json` each contain one invalid condition.
`case-01-wrong-version.json` has version 3, because a case may have version 1 or version 2.
`case-14-minimize.json` carries a 4096-byte document body that exceeds its `max_response_body_bytes` limit of 100 bytes.

A version 2 case is derived from another case, such as a minimized case.
Its `derived_from` names the original case's SHA-256 and `corpus` value, and its own `corpus` is `null`.
`fp0054-case-03-minimize-corpus.json` is a failing version 1 case with a corpus item, which `minimize` turns into a version 2 case.
The `fp0054-case-04-*` fixtures each contain one invalid use of `derived_from` or `corpus`.

`check.zig` is a test helper for FP-0007 contract case 14 and FP-0054 contract case 5.
It confirms that a minimized case is 1-minimal, that a refused minimization wrote no file, and that a refused minimization left its input unchanged.
