# Laboratory fixtures

These first-party case documents were written for tasks FP-0007, FP-0054, and FP-0008.
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

The `fp0008-*` fixtures exercise the `decode` and `tokenize` stages of FP-0008.
`fp0008-tokenize-pass.json` carries the UTF-8 byte order mark EF BB BF followed by `<!DOCTYPE html><p class=x>a&amp;b</p>`, the contract's `L_BODY`, and a matching `tokenize` expectation.
`fp0008-tokenize-token-count.json`, `fp0008-tokenize-zero-digest.json`, and `fp0008-tokenize-wrong-errors.json` each change one checked member of that expectation.
`fp0008-tokenize-errors.json` carries a body with two tokenizer parse errors.
`fp0008-tokenize-no-bom.json`, `fp0008-decode-utf16le-bom.json`, and `fp0008-decode-utf16be-bom.json` carry bodies that the `decode` stage does not support.
`fp0008-tokenize-null-body.json` has a `null` document body, so its document fails.
`fp0008-decode-pass.json` and `fp0008-decode-wrong-encoding.json` carry `decode` expectations for the `L_BODY` case.
`fp0008-tokenize-replacement.json` carries the bytes EF BB BF 61 FF 62, whose byte FF the UTF-8 decoder replaces with U+FFFD.

`check.zig` is a test helper for FP-0007 contract case 14, FP-0054 contract case 5 and revision 1 cases 1 to 5, FP-0076 contract cases 1 to 7, and FP-0106 contract case 5.
It confirms that a minimized case is 1-minimal, that a refused minimization wrote no file, and that a refused minimization left its input unchanged.
It creates a fresh directory for each case, with a hard link, a symbolic link, or an output file that the current user may write but not read.
It reads a transcript that the laboratory writes into a FIFO, with a 30-second limit.
It runs the laboratory on a case file and a transcript file one byte above their size limits, and it removes both files before it reports each check.
On Windows, it holds an output file pending deletion while the laboratory runs, and it confirms first that the laboratory's open of that file returns `STATUS_DELETE_PENDING`.
