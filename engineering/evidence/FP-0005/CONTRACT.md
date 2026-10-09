# FP-0005 task contract

## Identity

Task ID: `FP-0005`, "Implement lossless owned web strings".
Workstream: `substrate`.
Base: commit `475cb0e`, with source digest `80451afb1cda32e1541a29828d892792d9deb4be2342be6cc3cddcdacd27f119`.
Prerequisites: `FP-0004`, accepted.
Assigned role: `fairpane-core`.

## Sources

- ECMAScript String type: <https://tc39.es/ecma262/#sec-ecmascript-language-types-string-type>.
- ECMAScript `IsLessThan` for strings: <https://tc39.es/ecma262/#sec-islessthan>.
- WHATWG Encoding UTF-8 decoder: <https://encoding.spec.whatwg.org/#utf-8-decoder>.
- WHATWG Infra scalar value string conversion: <https://infra.spec.whatwg.org/#javascript-string-convert>.
- Unicode Standard, chapter 3, "U+FFFD Substitution of Maximal Subparts", table 3-8.

## Behavior

All code lives in `src/web_string.zig`.
The module uses only the pinned Zig standard library.

### Offset types

`CodeUnitIndex` is a distinct type for UTF-16 code-unit positions.
`Utf8ByteIndex` is a distinct type for UTF-8 byte positions.
Both are non-exhaustive `enum(usize)` types, so the compiler rejects mixing them with each other or with bare integers.
Every API that accepts or returns a position uses one of these types.

### Borrowed view

`View` stays a borrowed sequence of UTF-16 code units.
`View.codeUnitLen()` returns the number of code units.
`View.codeUnitAt(CodeUnitIndex)` returns the code unit or `null` past the end.
`View.eql` compares code units exactly and never normalizes.
`View.order` compares code units numerically, as ECMAScript `IsLessThan` does for strings.

### Owned string

`WebString` owns an immutable sequence of UTF-16 code units.
It stores any code unit, including zero and unpaired surrogates.
The caller passes the same allocator to every allocating function and to `deinit`.

| Operation | Contract |
| --- | --- |
| `fromCodeUnits(gpa, units)` | Copies the units exactly. |
| `fromUtf8(gpa, bytes)` | Decodes well-formed UTF-8, or returns `error.InvalidUtf8` at the first decoder error. |
| `fromUtf8Lossy(gpa, bytes)` | Decodes with the WHATWG UTF-8 decoder and emits U+FFFD for each decoder error. |
| `view()` | Returns a `View` that stays valid until `deinit`. |
| `clone(gpa)` | Returns an independent copy. |
| `concat(gpa, a, b)` | Returns the code units of view `a` followed by view `b`. |
| `slice(gpa, start, end)` | Copies code units in `[start, end)`, or returns `error.OutOfBounds`. |
| `toUtf8Alloc(gpa)` | Encodes, or returns `error.UnpairedSurrogate` for any unpaired surrogate. |
| `toUtf8LossyAlloc(gpa)` | Encodes the scalar value string, replacing each unpaired surrogate with U+FFFD. |
| `deinit(gpa)` | Releases the storage. |

`slice` can split a surrogate pair, and the result keeps the lone surrogate.
`concat` of a lone high surrogate and a lone low surrogate yields a valid pair.
An empty result never allocates.
Each function that fails leaves no allocation behind and no partially initialized string.

### Offset conversion

`codeUnitIndexForUtf8Offset(bytes, Utf8ByteIndex)` maps a byte offset in well-formed UTF-8 to the code-unit index of the decoded string.
It returns `error.InvalidUtf8` for ill-formed input, `error.NotScalarBoundary` inside a scalar value, and `error.OutOfBounds` past the end.
`utf8OffsetForCodeUnitIndex(View, CodeUnitIndex)` maps a code-unit index to the byte offset of the strict UTF-8 encoding.
It returns `error.InsideSurrogatePair` between the units of a pair, `error.UnpairedSurrogate` when the prefix contains an unpaired surrogate, and `error.OutOfBounds` past the end.
Both functions accept the end position.

### Exclusions

A one-byte storage representation is a performance hypothesis outside this task.
Its later introduction needs a measurement and keeps this two-byte path as the reference.
This task adds no C ABI export.

## Exact test cases

Each test lives in `src/web_string.zig` and runs through `zig build test`.

1. `fromCodeUnits` preserves `{0x0041, 0xD800, 0x0000, 0xDC00, 0xDC00, 0xD800}` exactly.
2. `fromCodeUnits` and `fromUtf8` with empty input succeed under an allocator that fails its first allocation.
   The results have length 0, `codeUnitAt(0)` returns `null`, and both UTF-8 encodings return empty slices.
3. `fromUtf8("a\x00b")` yields `{0x0061, 0x0000, 0x0062}`, and `toUtf8Alloc` returns the same three bytes.
4. `fromUtf8` decodes `C3 A9` to `{0x00E9}`, `F0 9F 98 80` to `{0xD83D, 0xDE00}`, and `F4 8F BF BF` to `{0xDBFF, 0xDFFF}`.
5. `fromUtf8` returns `error.InvalidUtf8` for `C0 AF`, `E0 80 AF`, `ED A0 80`, `F4 90 80 80`, `E2 82`, `80`, and `FF`, without leaks.
6. `fromUtf8Lossy` maps `61 F1 80 80 E1 80 C2 62 80 63 80 BF 64` to `{0x0061, 0xFFFD, 0xFFFD, 0xFFFD, 0x0062, 0xFFFD, 0x0063, 0xFFFD, 0xFFFD, 0x0064}`.
7. `fromUtf8Lossy` maps `ED A0 80` to three U+FFFD units, `F4 90 80 80` to four, `C0 AF` to two, and `E2 82` to one.
8. `toUtf8Alloc` returns `error.UnpairedSurrogate` for `{0xD800}`, `{0xDC00}`, and `{0xDC00, 0xD800}`, and encodes `{0xD83D, 0xDE00}` as `F0 9F 98 80`.
9. `toUtf8LossyAlloc` encodes `{0x0061, 0xD800, 0x0062, 0xDC00, 0xD83D, 0xDE00}` as `61 EF BF BD 62 EF BF BD F0 9F 98 80`.
10. `eql` distinguishes `{0x00E9}` from `{0x0065, 0x0301}`, and `order` returns `.gt` for that pair.
11. `order` places `{0xFF61}` after `{0xD83D, 0xDE00}`, although U+FF61 precedes U+1F600 in code-point order.
12. `slice` of `{0xD83D, 0xDE00}` over `[0, 1)` yields `{0xD83D}`, and `concat` of `{0xD83D}` and `{0xDE00}` encodes strictly as `F0 9F 98 80`.
13. `slice` returns `error.OutOfBounds` when `start > end` or `end` exceeds the length.
14. For the UTF-8 text `a é 😀 b` without spaces, byte offsets 0, 1, 3, 7, and 8 map to code-unit indexes 0, 1, 2, 4, and 5.
    Byte offsets 2, 4, 5, and 6 return `error.NotScalarBoundary`, and byte offset 9 returns `error.OutOfBounds`.
15. For the decoded string of case 14, code-unit index 3 returns `error.InsideSurrogatePair`, and index 6 returns `error.OutOfBounds`.
    For `{0xD800, 0x0061}`, index 2 returns `error.UnpairedSurrogate`.
16. `std.testing.checkAllAllocationFailures` runs a scenario with `fromCodeUnits`, `fromUtf8`, `fromUtf8Lossy`, `clone`, `concat`, `slice`, `toUtf8Alloc`, and `toUtf8LossyAlloc`.
    Each induced failure returns `error.OutOfMemory` and leaks nothing.

## Gates

Run these gates with the locked compiler and record their receipts under `engineering/evidence/FP-0005/gates`.

- `repo-check`
- `controller-test`
- `zig-test`

Also run `zig-fmt` and `zig-build` as regression checks.

## Review

`fairpane-review` reviews the integrated change.
