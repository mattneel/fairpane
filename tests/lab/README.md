# Laboratory fixtures

These first-party case documents were written for task FP-0007.
They exercise the `fairpane-lab` case format, its outcomes, and its minimizer.
They contain no upstream test content.
Their URLs name the reserved `example.test` domain, and the laboratory answers them from the case bytes only.

The `case-NN-*` prefix names the contract case that uses each fixture.
The `case-01-*` fixtures other than `case-01-valid.json` each contain one invalid condition.
`case-14-minimize.json` carries a 4096-byte document body that exceeds its `max_response_body_bytes` limit of 100 bytes.

`check.zig` is a test helper for contract case 14.
It confirms that a minimized case is 1-minimal and that a refused minimization wrote no file.
