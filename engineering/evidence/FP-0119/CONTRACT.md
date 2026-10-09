# FP-0119 task contract

## Identity

Task ID: `FP-0119`, "Decode TrueType glyph outlines into a bounded outline model".
Workstream: `text`.
Base: the commit that freezes this contract. At drafting time, `HEAD` was `483a239`.
Prerequisite: `FP-0013`, accepted.
This is the first slice of the `FP-0056` split. The others are `FP-0120` (CFF charstrings), `FP-0121` (the rasterizer), and `FP-0122` (glyph rendering).
A contract worker drafted this contract, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-text`.
Authority: `routine-local-engineering`.

### Integrator decisions

- `FP-0056` is split into `FP-0119` through `FP-0122`. `FP-0056` keeps its five criteria word for word as the closing task.
- The outline is unhinted:
  - Glyph instructions are skipped and never executed.
  - The decoder ignores `ROUND_XY_TO_GRID`, which the `glyf` chapter calls grid fitting.
  - `FP-0057` owns grid fitting.
- Point matching between outline points is supported.
  - An index that may name a phantom point returns `UnsupportedPhantomPoint`, and `FP-0057` owns that behavior.
  - For the parent, the indices are `[n, n+4)` after the `n` points already incorporated.
  - For the child, the indices are `[m, m+4)` after the child's `m` points.
  - The parent numbering is an [INFERENCE]. The `unsupported` result asserts nothing about validity.
- Coordinates are f64 values in font units, with y pointing up.
  - Every expectation below is compared with `==`, so −0 equals 0.
- The bounds are accepted:
  - The composite depth is at most 8. A composite of simple glyphs has depth 1, as `maxp` defines it.
  - `max_points` defaults to 65536.
  - `max_components` defaults to 65536.
- The strictness choices in "Strictness choices for FP-0058" are frozen. `FP-0058` compares them with web-font practice.
- The task adds at most 10 seconds to the `tests/text` run step on the development host.
- No third-party code computes an expectation.
  - fontTools stays an import-time tool and is not used for outlines.
  - No TN5176 table is used.
- This task implements no capability.
  - It changes only the `engine_behavior` text of `glyph-rasterization`.
  - No FP-0013 case pins that text. `tools/capabilities.mjs` line 40 requires only a non-empty string. FP-0013 case 49 in `tools/fileset.test.mjs` compares the ID, the status, and the owner.

## Sources

All sources were retrieved on 2026-10-09.

- OpenType 1.9.1 `glyf`, source commit `810414e13e39f68adfb5f12d525e6b50c850fbbc`: <https://learn.microsoft.com/en-us/typography/opentype/spec/glyf>. These sections apply:
  - "Glyph headers".
  - "Simple glyph description" and the "Simple Glyph flags" table.
  - "Composite glyph description", the component pseudo-code, and the "Component Glyph flags" table.
  - The paragraphs on `ARGS_ARE_XY_VALUES`.
  - Point alignment: "the transformation is applied to the child's point before the points are aligned".
  - The 2 × 2 matrix: `x′ = xscale·x + scale10·y` and `y′ = scale01·x + yscale·y`.
  - `SCALED_COMPONENT_OFFSET` and `UNSCALED_COMPONENT_OFFSET`. The unscaled default is "recommended for all rasterizer implementations".
  - `WE_HAVE_INSTRUCTIONS`: "If the flag is set on any component glyph, then a uint16 value is read immediately after the last component glyph".
- OpenType `maxp`: `maxComponentDepth`, "Maximum levels of recursion; 1 for simple components". The task also uses `maxPoints`, `maxContours`, `maxCompositePoints`, `maxCompositeContours`, and `maxComponentElements`.
- OpenType `loca`, `head`, and `hmtx`.
- OpenType `tt_instructing_glyphs`, "Phantom points".
- OpenType `gvar`, "Point numbers and processing for composite glyphs".
- `docs/RENDERING_AND_TEXT.md`, which the plan entry requires. It states that the engine owns rasterization and that the scalar path is the reference.
- Repository files:
  - `src/font/opentype.zig`, `src/font/tables.zig`, and `src/font/reader.zig`.
  - `tests/text/sfnt_builder.zig`.
  - `engineering/evidence/FP-0013/CONTRACT.md`.
  - The three TrueType fixtures and their `.expect.json` files.

### Observed facts that shaped the decisions

- `src/font/opentype.zig` lines 196 to 337 define `Font`, which has no outline accessor.
- `src/font/opentype.zig` lines 1 to 5 describe the module as "An allocation-free OpenType parser" whose outlines "are not interpreted".
- `parse` declares the locals `outline` (line 343) and `glyf` (line 417).
- `src/font/tables.zig:237` says: "Outline points, flags, and composite components are not decoded."
- `src/font/tables.zig:256` accepts equal `endPtsOfContours` entries.
- `src/font` holds only `layout.zig`, `opentype.zig`, `reader.zig`, `tables.zig`, `cff.zig`, and `cmap.zig`.
- B_TT, in `tests/text/sfnt_builder.zig` lines 587 to 607:
  - Glyph 0 is the box (50,0), (50,700), (450,700), (450,0), with flags `0x01` and 16-bit deltas.
  - Glyph 1 is empty.
  - Glyph 2 is (10,0), (300,700), (590,0).
  - Glyph 3 is a composite with flags `0x0002`, component glyph 2, and byte arguments (0, 0).
- The `maxp` values below come from the expectation files. `head.flags` is 3 in every font.

| Font | Glyphs | `maxPoints` | `maxContours` | `maxCompositePoints` | `maxCompositeContours` | `maxComponentElements` | `maxComponentDepth` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Noto Sans | 3884 | 260 | 24 | 102 | 6 | 4 | 1 |
| Noto Sans Arabic | 1399 | 778 | 38 | 237 | 11 | 8 | 1 |
| Noto Sans Devanagari | 845 | 127 | 8 | 113 | 6 | 3 | 1 |

- FP-0098 dispatched ten runs at `29a9f8e`. The slowest took 191 s on Windows and 188 s on Linux (`engineering/evidence/FP-0098/ci/README.md` line 26). The FP-0098 contract sets a 400 s ceiling, and the gate timeout is 600 s.

## Behavior

### Files

| File | Content |
| --- | --- |
| `src/font/outline.zig` | `Point`, `Verb`, `Path`, `Limits`, `max_composite_depth`, and `OutlineError` |
| `src/font/glyf.zig` | Simple and composite decoding, `TrueTypeGlyph`, and the contour-to-path conversion |
| `src/font/opentype.zig` | `Font.trueTypeGlyph`, `pub const outline_model = @import("outline.zig")`, `pub const glyf_decoder = @import("glyf.zig")`, and test references to the new files. Module comment lines 1 to 5 are restated: `parse` stays allocation-free, `trueTypeGlyph` allocates only through its `gpa` and decodes TrueType outlines, and no function recurses. The `trueTypeGlyph` doc comment states that a `loca` range that no longer lies inside `glyf` returns `InvalidGlyph` |
| `tests/text/glyf_builder.zig` | F_GLYF and its variants |
| `tests/text/glyf_test.zig` | The cases, each named `FP-0119 case N: ...` |
| `tests/text/root.zig` | Imports `glyf_test.zig` |
| `tests/text/sfnt_builder.zig` | Makes `simpleGlyph` public |
| `tests/text/README.md` | Describes F_GLYF, the stop rules, and the observations. Line 5 names FP-0119 outline decoding |
| `specs/capabilities/text-fonts.json` | The new `glyph-rasterization.engine_behavior` text below |

A file-scope declaration named `outline` or `glyf` would collide with the `parse` locals at lines 343 and 417, and this task does not change `parse`.

The new `engine_behavior` text for `glyph-rasterization` is: "Font.trueTypeGlyph decodes TrueType simple and composite outlines in font units without hinting. It returns error.UnsupportedPhantomPoint for point matching against a phantom point and error.NotTrueType for a CFF font. CFF charstrings are not interpreted, and no scan converter exists."
The obligation stays `remaining`, with owner `FP-0056`.
The task changes nothing under `include`, `api`, or `tools`, and it does not change `src/c_api.zig`.

### Interface

```zig
// src/font/outline.zig
pub const Point = struct { x: f64, y: f64 };
pub const Verb = enum(u8) { move, line, quad, cubic, close };
pub const Path = struct {
    verbs: []Verb,
    points: []Point, // move and line take 1 point, quad takes 2 (control, end), cubic takes 3, and close takes 0
    pub fn deinit(path: *Path, gpa: Allocator) void;
};
pub const Limits = struct { max_points: u32 = 65536, max_components: u32 = 65536 };
pub const max_composite_depth = 8;
pub const OutlineError = error{ OutOfMemory, GlyphOutOfRange, NotTrueType, InvalidGlyph, CompositeCycle, CompositeTooDeep, OutlineTooLarge, UnsupportedPhantomPoint };

// src/font/glyf.zig
pub const TrueTypeGlyph = struct {
    points: []Point,
    on_curve: []bool,
    contour_ends: []u32,       // strictly increasing indices into points
    depth: u8,                 // 0 for a simple or empty glyph
    top_level_components: u32, // 0 for a simple or empty glyph
    pub fn deinit(glyph: *TrueTypeGlyph, gpa: Allocator) void;
    pub fn path(glyph: *const TrueTypeGlyph, gpa: Allocator) error{OutOfMemory}!Path;
};

// Font
pub fn trueTypeGlyph(self: *const Font, gpa: Allocator, glyph: u16, limits: Limits) OutlineError!TrueTypeGlyph;
```

The worker may refine these names without changing behavior. A refined name must not collide with a local in `parse`.
The checks run in this order:

1. `glyph >= numGlyphs` returns `GlyphOutOfRange`.
2. A CFF font returns `NotTrueType`.
3. A `loca` range of zero length is an empty glyph: no points, no contours, depth 0, and 0 top-level components.

### Simple glyphs

1. Data shorter than 10 bytes returns `InvalidGlyph`.
2. If `numberOfContours` is n ≥ 1, the decoder first reads the last `endPtsOfContours` entry.
   - A missing entry returns `InvalidGlyph`.
   - Let `p = last + 1`.
   - If `points_so_far + p > max_points`, the decoder returns `OutlineTooLarge`.
3. The decoder checks that the entries strictly increase, or returns `InvalidGlyph`.
4. It reads `instructionLength` and skips that many bytes. If they are not present, it returns `InvalidGlyph`.
5. It expands exactly `p` logical flags.
   - `REPEAT_FLAG` reads the next byte as a count of extra copies.
   - A missing count, or more than `p` logical flags, returns `InvalidGlyph`.
6. It reads the x array, then the y array. Truncation returns `InvalidGlyph`. Each coordinate is one of these:
   - Short with the positive bit set: `+u8`.
   - Short with the positive bit clear: `−u8`.
   - Not short with the same bit set: 0, and no byte is read.
   - Otherwise: a big-endian `i16`.
7. Absolute coordinates are prefix sums from (0, 0) in i64. They are exact, because |sum| ≤ 65536 × 32768.
8. `numberOfContours` = 0 yields no points.
9. Bytes after the y array are ignored.

### Composite glyphs

A negative `numberOfContours` marks a composite.
Each record follows the layout in the specification's pseudo-code. The decoder processes each record in this order:

1. The record bytes must be present, or it returns `InvalidGlyph`.
2. The transform flags must not conflict, or it returns `InvalidGlyph`.
3. The glyph index must be below `numGlyphs`, or it returns `InvalidGlyph`.
4. The number of component records processed at every level, counting this one, must not exceed `max_components`, or it returns `OutlineTooLarge`.
5. A child that is already on the active chain returns `CompositeCycle`.
6. A composite child at a level above 8 returns `CompositeTooDeep`. The top-level composite is level 1.
7. The child's points are appended, flattened.
8. The decoder applies `M` to the appended range, with `F2Dot14 = i16 / 16384`. Then it applies the offset:
   - With `ARGS_ARE_XY_VALUES`, the offset is `(arg1, arg2)`, read as signed bytes or `i16` values. `M` transforms the offset only when `SCALED_COMPONENT_OFFSET` is set without `UNSCALED_COMPONENT_OFFSET`.
   - Otherwise, the arguments are the unsigned point numbers `k` and `l`. They are `u8` values, or `u16` values when `ARG_1_AND_2_ARE_WORDS` is set. The offset is `parent[k] − (M·child)[l]`.
   - Point matching in the first component returns `InvalidGlyph`.
   - An index in a phantom range returns `UnsupportedPhantomPoint`, and a larger index returns `InvalidGlyph`.
9. `MORE_COMPONENTS` continues the loop.
10. If any record sets `WE_HAVE_INSTRUCTIONS`, a `uint16` length and that many bytes must follow the last record, or the decoder returns `InvalidGlyph`.
11. `on_curve` and `contour_ends` follow the incorporated points, renumbered.

Traversal uses a fixed array of 8 frames, so native stack use is constant.
`glyf.zig` contains no recursive call, as the FP-0013 module rule "no function recurses" requires.
The counter `glyf_decoder.work` exists only in test builds. It adds 1 for each component record, each simple-glyph instantiation, and each decoded point.
The decoder checks the points budget before it decodes the points, so `work ≤ max_points + 2·max_components + 2`.
Peak allocation for one decode is at most `64 · max_points + 65536` bytes.

### Contour-to-path rule

For contour points `q_0` to `q_{m−1}`, with m ≥ 1:

1. Choose the start `S` and the sequence `R`:
   - If `q_0` is on the curve, `S = q_0` and `R = q_1 … q_{m−1}`.
   - Otherwise, if `q_{m−1}` is on the curve, `S = q_{m−1}` and `R = q_0 … q_{m−2}`.
   - Otherwise, `S = mid(q_{m−1}, q_0)` and `R = q_0 … q_{m−1}`.
2. Emit `move(S)`.
3. Start with no pending control point `C`, and visit each `p` in `R`:
   - If `p` is on the curve and there is no `C`, emit `line(p)`.
   - If `p` is on the curve and there is a `C`, emit `quad(C, p)` and clear `C`.
   - If `p` is off the curve and there is no `C`, set `C = p`.
   - If `p` is off the curve and there is a `C`, emit `quad(C, mid(C, p))` and set `C = p`.
4. If `C` is still set, emit `quad(C, S)`.
5. Emit `close`. A close is a line back to `S` whenever the current point differs from `S`.

### Strictness choices for FP-0058

Each choice is frozen here and listed for the `FP-0058` web-compatibility comparison.

| # | Input | FP-0119 result | Basis |
| --- | --- | --- | --- |
| 1 | Equal adjacent `endPtsOfContours` entries | `InvalidGlyph` from `trueTypeGlyph`. `glyphHeader` stays non-strict at `tables.zig:256` | `glyf`: "in increasing numeric order" |
| 2 | Simple-glyph flag bit 7, and component flag bits `0xE010` | Ignored | Reserved bits have no outline meaning |
| 3 | `OVERLAP_SIMPLE` and `OVERLAP_COMPOUND` | Ignored | Informational: "Use of this flag is not required" |
| 4 | More than one of `WE_HAVE_A_SCALE`, `WE_HAVE_AN_X_AND_Y_SCALE`, and `WE_HAVE_A_TWO_BY_TWO` | `InvalidGlyph` | "no more than one of these may be set" |
| 5 | Point matching in the first component | `InvalidGlyph` | "This flag must always be set for the first component" |
| 6 | A repeat count that runs past the point count, or a missing count | `InvalidGlyph` | The logical flags array has one entry per point |
| 7 | Composite instructions that run past the glyph data | `InvalidGlyph` | The same rule as the simple-glyph `instructionLength` check |
| 8 | A component glyph index at or past `numGlyphs` | `InvalidGlyph` | Glyph IDs index `loca` |
| 9 | Bytes after the y array, or after the composite instructions | Ignored | Padding |
| 10 | `SCALED_COMPONENT_OFFSET` and `UNSCALED_COMPONENT_OFFSET` both set | The unscaled default | "the rasterizer should use its default behavior" |
| 11 | Header bounds that differ from the decoded points | Ignored | The header is derived from the points. Case 14 checks the real fonts |
| 12 | `numberOfContours` below −1 | Decoded as a composite | "If negative, this is a composite glyph" |
| 13 | A point-matching index at or past n+4 for the parent, or m+4 for the child | `InvalidGlyph` | Only the incorporated points and four phantom points are numbered |
| 14 | `WE_HAVE_INSTRUCTIONS` on a record other than the last | The instructions follow the last record | "If the flag is set on any component glyph, then a uint16 value is read immediately after the last component glyph" |

## Exact test cases

The cases live in `tests/text/glyf_test.zig` and run through `zig build test`.

### Fixture font F_GLYF

F_GLYF is B_TT with these changes:

- `head.indexToLocFormat` is 1, at byte 50 of the 54-byte table.
- `loca` is long.
- `maxp` is version 1.0 with `numGlyphs` 45.
- `hhea.numberOfHMetrics` is 1.
- `hmtx` holds (500, 0) followed by 44 left side bearings of 0.
- `glyf` holds the entries below.

Simple-glyph headers carry their exact point bounds.
Each composite "Header" is `FFFF 0000 0000 0000 0000`, which gives a `numberOfContours` of −1 and bounds of (0, 0, 0, 0).

| ID | Name | Glyph data (hex), or builder call |
| --- | --- | --- |
| 0 | BOX | The bytes of B_TT glyph 0 |
| 1 | EMPTY | Zero length |
| 2 | T1 | `0002 FF0B 0014 03E8 012C 0003 0006 0003 AABBCC 77 11 22 15 29 02 0A FF 04DD FC18 FFF6 14 0118 FF` (37 bytes) |
| 3 | T2 | `0001 0000 0000 0064 0064 0003 0000 00 00 00 00 0000 0064 0000 FF9C 0000 0000 0064 0000` (34 bytes) |
| 4 | T3 | `0001 0000 0000 0064 0064 0002 0000 00 01 01 0032 0032 FF9C 0064 FF9C 0000` |
| 5 | TRI | `simpleGlyph` with (0,0), (100,0), (50,100), all on the curve |
| 6 | DOT | `simpleGlyph` with (0,0), (10,0), (10,10), (0,10), all on the curve |
| 7 | C1 | `FFFF 0000 0000 0000 0000 0002 0003 0A EC` |
| 8 | C2 | Header, then `000B 0005 012C FED4 2000` |
| 9 | C3 | Header, then `0042 0005 0A 00 C000 6000` |
| 10 | C4 | Header, then `0082 0005 00 00 0000 4000 C000 0000` |
| 11 | C5a | Header, then `080B 0005 0064 00C8 2000` |
| 12 | C5b | Header, then `100B 0005 0064 00C8 2000` |
| 13 | C5c | Header, then `180B 0005 0064 00C8 2000` |
| 14 | C6 | Header, then `0022 0005 00 00` and `0008 0006 02 02 2000` (24 bytes) |
| 15 | C7 | Header, then `0122 0005 00 00`, `0003 0006 00C8 0000`, and `0002 01 02` (28 bytes) |
| 16 | C8 | Header, then `0002 0007 05 05` |
| 17 to 25 | D1 to D9 | D1 is a header, then `0002 0005 00 00`. Dk is a header, then `0002 <glyph 15+k> 00 00` |
| 26 | SELF | Header, then `0002 001A 00 00` |
| 27, 28 | PING, PONG | PING is a header, then `0002 001C 00 00`. PONG is a header, then `0002 001B 00 00` |
| 29 | L300 | `simpleGlyph` with (10·(i mod 2), i) for i = 0 to 299, all on the curve |
| 30 to 37 | E1 to E8 | Ek holds two records, `0022 <g> 00 00` and `0002 <g> 00 00`, with g = 28 + k |
| 38 to 41 | F1 to F4 | 16 records: 15 copies of `0022 <g> 00 00`, then `0002 <g> 00 00`. g is 1 for F1 and 36 + k for Fk |
| 42 | T4 | `0002 0005 0005 0007 0009 0000 0001 0000 37 36 05 02 05 04` |
| 43 | C5d | Header, then `080F 0005 0065 00C9 2000` |
| 44 | C9 | Header, then `0022 001D 00 00`, `0020 0006 C8 00`, and `0001 0006 0101 0002` (30 bytes) |

Derivation of T1:

- The flags `77 11 22 15 29 02` expand to 7 logical flags:
  - `0x77`: on the curve; x short and positive; y short and positive. Bit 6 (`OVERLAP_SIMPLE`) is ignored.
  - `0x11`: on the curve; x same; y an `i16`.
  - `0x22`: off the curve; x short and negative; y same.
  - `0x15`: on the curve; x same; y short and negative.
  - `0x29` with count 2: three points, each on the curve, with x an `i16` and y same.
- The x deltas are +10, 0, −255, 0, +1245 (`04DD`), −1000 (`FC18`), and −10 (`FFF6`). The absolute x values are 10, 10, −245, −245, 1000, 0, and −10.
- The y deltas are +20, +280 (`0118`), 0, −255, 0, 0, and 0. The absolute y values are 20, 300, 300, 45, 45, 45, and 45.
- The bounds (−245, 20, 1000, 300) equal the header.
- The length is 10 + 4 + 2 + 3 + 6 + 8 + 4 = 37 bytes.

Derivation of T3: the x deltas 50, 50, −100 give x values 50, 100, 0. The y deltas 100, −100, 0 give y values 100, 0, 0.

Derivation of T4: flag `37` (on the curve) and flag `36` (off the curve), with short positive deltas, give (5,5) and (7,9).

Derivation of C5d:

- The flags `080F` are `SCALED_COMPONENT_OFFSET`, `WE_HAVE_A_SCALE`, `ROUND_XY_TO_GRID`, `ARGS_ARE_XY_VALUES`, and `ARG_1_AND_2_ARE_WORDS`.
- The arguments `0065 00C9` are (101, 201). The scale `2000` is 0.5.
- The scaled offset is 0.5·(101,201) = (50.5,100.5). The decoder does not round it.

Derivation of C9:

- The first record, `0022`, places L300 with the offset (0,0).
- The second record, `0020`, has no `ARGS_ARE_XY_VALUES` and no words, so its arguments are the unsigned bytes k = `C8` = 200 and l = 0.
- The third record, `0001`, has words, so its arguments are k = `0101` = 257 and l = 2. When it is read, the parent holds 300 + 4 = 304 points.
- The length is 10 + 6 + 6 + 8 = 30 bytes.

### Cases

1. B_TT:
   - Glyph 0 gives the points (50,0), (50,700), (450,700), (450,0), all on the curve, with `contour_ends` [3].
   - Glyph 1 is empty.
   - Glyph 2 gives (10,0), (300,700), (590,0).
   - Glyph 3 gives the points of glyph 2, with depth 1 and 1 top-level component.
   - Glyph 4 returns `GlyphOutOfRange`.
   - B_CFF glyph 0 returns `NotTrueType`.
   - B_CFF glyph 2 returns `GlyphOutOfRange`.
2. T1 gives the points (10,20), (10,300), (−245,300), (−245,45), (1000,45), (0,45), (−10,45).
   `on_curve` is T T F T T T T, and `contour_ends` is [3, 6].
3. Paths:
   - T1: move(10,20) line(10,300) quad((−245,300),(−245,45)) close move(1000,45) line(0,45) line(−10,45) close.
   - T2: move(0,50) quad((0,0),(50,0)) quad((100,0),(100,50)) quad((100,100),(50,100)) quad((0,100),(0,50)) close.
   - T3: move(0,0) quad((50,100),(100,0)) close.
   - T4: move(5,5) close move(7,9) quad((7,9),(7,9)) close.
   - BOX: move(50,0) line(50,700) line(450,700) line(450,0) close.
4. Component transforms. Every point is on the curve, except in C1.
   - C1 gives (10,−20), (110,−20), (110,80), (10,80), all off the curve.
     Its path is move(10,30) quad((10,−20),(60,−20)) quad((110,−20),(110,30)) quad((110,80),(60,80)) quad((10,80),(10,30)) close.
   - C2 = 0.5·p + (300,−300) gives (300,−300), (350,−300), (325,−250).
   - C3, with x′ = −x + 10 and y′ = 1.5y, gives (10,0), (−90,0), (−40,150).
   - C4, with x′ = −y and y′ = x, gives (0,0), (0,100), (−100,50).
   - C5a, with the offset 0.5·(100,200) = (50,100), gives (50,100), (100,100), (75,150).
   - C5b and C5c, with the offset (100,200), give (100,200), (150,200), (125,250).
   - C5d sets `ROUND_XY_TO_GRID`, and the decoder ignores it. With the scaled offset (50.5,100.5), C5d gives (50.5,100.5), (100.5,100.5), (75.5,150.5).
5. C6, C7, C8, and C9:
   - C6:
     - TRI gives (0,0), (100,0), (50,100).
     - DOT scaled by 0.5 gives (0,0), (5,0), (5,5), (0,5).
     - The offset is (50,100) − (5,5) = (45,95).
     - So C6 gives (0,0), (100,0), (50,100), (45,95), (50,95), (50,100), (45,100), with `contour_ends` [2, 6] and 2 top-level components.
   - C7 gives TRI, then DOT plus (200,0): (200,0), (210,0), (210,10), (200,10). `contour_ends` is [2, 6].
     Only the first record sets the instructions flag, but the instructions follow the last record.
   - C8 gives C1 plus (5,5): (15,−15), (115,−15), (115,85), (15,85), all off the curve, with depth 2.
   - C9:
     - C9 starts with the 300 L300 points.
     - Next, DOT moves by L300[200] − DOT[0] = (0,200) − (0,0), which gives (0,200), (10,200), (10,210), (0,210).
     - Last, DOT moves by L300[257] − DOT[2] = (10,257) − (10,10) = (0,247), which gives (0,247), (10,247), (10,257), (0,257).
     - `contour_ends` is [299, 303, 307], with 3 top-level components and depth 1.
6. Depth and cycles:
   - D8 gives the TRI points with depth 8.
   - D9 returns `CompositeTooDeep`.
   - SELF, PING, and PONG each return `CompositeCycle`.
7. Budgets:
   - `Limits{}` has `max_points` 65536 and `max_components` 65536, and `max_composite_depth` is 8.
   - E7 gives 2^7 × 300 = 38400 points, 128 contours, and depth 7.
   - E8 would need 76800 points, which is more than 65536, so it returns `OutlineTooLarge`.
   - F3 gives no points and depth 3, after 16 + 256 + 4096 = 4368 records.
   - F3 decodes with `max_components` 4368, and it returns `OutlineTooLarge` with `max_components` 4367.
   - F4 would need 69904 records, which is more than 65536, so it returns `OutlineTooLarge`.
   - L300 returns `OutlineTooLarge` with `max_points` 299, and it decodes with `max_points` 300.
   - C6 returns `OutlineTooLarge` with `max_components` 1.
   - For E8 and F4, `glyf_decoder.work` is at most 196610.
8. Malformed simple glyphs. Each row edits T1, unless the row states otherwise.
   - X1: bytes 12 and 13 set to `0003` make the ends [3, 3]. The decode returns `InvalidGlyph`, and `glyphHeader` still returns a header.
   - X2: bytes 12 and 13 set to `0002` return `InvalidGlyph`.
   - X3: a 12-byte prefix returns `InvalidGlyph`.
   - X4: bytes 14 and 15 set to `00FF` return `InvalidGlyph`.
   - X5: a 22-byte prefix returns `InvalidGlyph`.
   - X6: byte 24 set to `03` gives 8 logical flags for 7 points, so the decode returns `InvalidGlyph`.
   - X7: a 24-byte prefix leaves the repeat count missing, so the decode returns `InvalidGlyph`.
   - X8: a 30-byte prefix returns `InvalidGlyph`.
   - X9: a 36-byte prefix returns `InvalidGlyph`.
   - X10: the glyph `0001 00000000 00000000 FFFF 0000` returns `InvalidGlyph` under the default limits. It returns `OutlineTooLarge` with `max_points` 65535.
   - X11: the glyph `0001 0000 0000` returns `InvalidGlyph`.
   - X12: the glyph `7FFF`, then 8 zero bytes, then `0000`, returns `InvalidGlyph`.
9. Malformed composite glyphs:
   - Y1: a 20-byte prefix of C6 returns `InvalidGlyph`.
   - Y2: an 18-byte prefix of C2 returns `InvalidGlyph`.
   - Y3: C2 with flags `008B`, `004B`, or `00CB` returns `InvalidGlyph`.
   - Y4: C1 with glyph index `002D` or `FFFF` returns `InvalidGlyph`.
   - Y5: C7 with instruction length `0010` returns `InvalidGlyph`.
   - Y6: C6 with the point arguments (3,2) or (6,2) returns `UnsupportedPhantomPoint`, and (7,2) returns `InvalidGlyph`.
     With (2,4) or (2,7), it returns `UnsupportedPhantomPoint`, and (2,8) returns `InvalidGlyph`.
   - Y7: C6 with first flags `0020` returns `InvalidGlyph`.
   - Y8: C6 with the second record `0009 0006 FFFF 0002 2000` returns `InvalidGlyph`.
   - Y9: if the X11 bytes replace T2, both C1 and C8 return `InvalidGlyph`.
10. Ignored inputs. Each of these decodes exactly as in cases 2, 4, and 5:
    - T1 with byte 20 set to `91`.
    - C1 with flags `E012`, C1 with flags `0402`, and C1 with `numberOfContours` `FFFE`.
    - T1 followed by the bytes `0000`.
    - C7 followed by the bytes `0000`.
11. Robustness:
    - For T1, C6, and C7, every prefix length L from 1 to the full length minus 1 returns `InvalidGlyph`.
    - L = 0 gives an empty glyph.
    - Each byte of those glyphs is set in turn to `00`, `FF`, and its value XOR `80`.
    - After each change, the font is parsed again under `.report`, and the glyph is decoded twice.
    - Both results are equal, and nothing panics or leaks.
12. Allocation:
    - `std.testing.checkAllAllocationFailures` runs decode and `path` on T1, C6, C7, and C8.
    - Every induced failure returns `OutOfMemory`, and nothing leaks.
    - A counting allocator shows that the peak for E7 is at most 64 × 65536 + 65536 bytes.
13. Stack:
    - D8, D9, SELF, E8, and F4 decode on a thread spawned with a 256 KiB stack in the Debug test build.
    - They give the outcomes of cases 6 and 7.
    - This is a robustness property, and no mutation control targets it.
    - The reviewers read the source to confirm that `glyf.zig` contains no recursive call.
14. Real fonts. For every glyph `g` of the three TrueType fixtures:
    - `trueTypeGlyph` succeeds.
    - An empty glyph, whose `glyphHeader` is null, has no points.
    - A simple glyph with points has bounds exactly equal to its header bounds, and `contour_ends.len` equals its `numberOfContours`. Its point count is at most `maxPoints`, and its contour count is at most `maxContours`.
    - A composite has header bounds equal to `⌊v + 1/2⌋` of its point bounds. [INFERENCE] fontTools wrote those bounds.
    - A composite with no points has header bounds (0, 0, 0, 0). [INFERENCE] fontTools writes zeros for an empty coordinate list.
    - For a composite, the points, contours, `top_level_components`, and `depth` are at most `maxCompositePoints`, `maxCompositeContours`, `maxComponentElements`, and `maxComponentDepth`.
    - The path has one move for each contour, and every subpath ends with `close`.

### Base failures

No case passes on the base.
Cases 1 to 14 call `Font.trueTypeGlyph`, `TrueTypeGlyph.path`, or `font.outline_model`.
`src/font/opentype.zig` lines 196 to 337 define none of them, and neither `src/font/outline.zig` nor `src/font/glyf.zig` exists.
`src/font/tables.zig:237` documents that nothing below the header is decoded.
So `tests-before.log` fails to compile the `tests/text` artifact.

### Mutation controls

Record each control as a `.diff`.
Apply it with `git apply`, run the tests, and reverse it with `git apply -R`.
Record the file hashes before and after each control.

| Control | Mutation | Case that fails, and why |
| --- | --- | --- |
| M1 | The sign of a short x is inverted | Case 2: the x of P0 becomes −10 |
| M2 | The repeat count is read as count + 1 | Case 2: 8 logical flags give `InvalidGlyph` |
| M3 | `SCALED_COMPONENT_OFFSET` is ignored | Case 4: C5a gets the offset (100,200), not (50,100) |
| M4 | The depth check rejects level 8 | Case 6: D8 returns `CompositeTooDeep` |
| M5 | The 2 × 2 matrix is transposed | Case 4: C4 maps (100,0) to (0,−100) |
| M6 | The points budget check is removed | Case 7: E8 returns 76800 points |
| M7 | The all-off-curve start uses `q_0` | Case 3: T2 starts at (0,0) |
| M8 | The cycle check is removed | Case 6: SELF returns `CompositeTooDeep` |
| M9 | The transform is applied after alignment | Case 5: the C6 offset becomes (40,90) |
| M10 | Phantom-range indices return `InvalidGlyph` | Case 9, row Y6 |
| M11 | Offsets are rounded to integers when `ROUND_XY_TO_GRID` is set | Case 4: the C5d offset becomes (51,101) or (50,100) |
| M12 | Byte point numbers are read as `int8` | Case 5: C9 fails, because `C8` becomes −56 |
| M13 | The component check rejects a count equal to `max_components` | Case 7: F3 with `max_components` 4368 returns `OutlineTooLarge` |

### Stop rules

- If a case 14 invariant fails, stop. Report the font, the glyph ID, and both values. Never edit a fixture or an expectation.
- If any fixture glyph returns `UnsupportedPhantomPoint`, stop and report it.
- If the `tests/text` run step grows by more than 10 seconds over the base on the development host, stop and report both durations.
- If any expectation here contradicts the cited text, stop and report it. Never edit an expectation silently.

### Criterion mapping

| FP-0119 criterion | Cases and evidence |
| --- | --- |
| Decode simple TrueType glyphs with checked bounds | 1, 2, 8, 10; M1, M2 |
| Decode composite glyphs with bounded depth, cycle detection, and constant stack | 1, 4 to 6, 9, 13; M3 to M5, M8, M9, M12 |
| Convert contours to closed paths, unhinted, and report phantom point matching as unsupported | 3, 4, 9 (Y6); M7, M10, M11 |
| Reject malformed glyphs within budgets, and record strictness | 7 to 9, 11 to 13; M6, M13; the strictness table |
| Check the three TrueType fixtures | 14 |
| Add at most 10 seconds of test time | `tests-before-duration.log` and `tests-after.log` |

### Remaining obligations

These obligations belong to other tasks:

- `FP-0057` owns `ROUND_XY_TO_GRID`, `USE_MY_METRICS`, glyph instructions, and point matching against phantom points. Vertical phantom points come from `FP-0061`.
- `FP-0059` owns `gvar`.
- `FP-0120` owns CFF charstrings.
- `FP-0121` and `FP-0122` own rasterization.
- `FP-0058` compares the strictness choices with web-font practice.

The README records these observations without asserting them:

- The counts of simple, composite, and empty glyphs for each font.
- How many components use each flag.
- Whether each `maxp` maximum is reached.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0119/raw/`.
Use `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`.
Never overwrite a log.
Name the log of a failed attempt with the suffix `-attempt-N`.

1. Write cases 1 to 14 before the implementation.
   Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0119-before`.
   It must fail.
2. In a worktree at the base commit, delete `out/fp0119-base`.
   Then record `tests-before-duration.log` with `cmd /d /c ver` and `zig build test --summary all --cache-dir out/fp0119-base`.
   It must exit with status 0 and show the `tests/text` run-step duration.
3. Delete `out/fp0119-after`.
   Then record `tests-after.log` with `cmd /d /c ver` and `zig build test --summary all --cache-dir out/fp0119-after`.
   It must exit with status 0 and show the step durations.
4. Record `fmt.log` with `zig fmt --check build.zig src tests`.
5. Record `controller-tests-after.log` with `node --version` and `node tools/fairpane.mjs test`.
6. Record `mutation.log`, and record `mutation-M1.diff` through `mutation-M13.diff`.
7. Write `engineering/evidence/FP-0119/README.md`.
   It gives the worktree `HEAD`, the criterion mapping, the result of each control, the case 14 observations, the time delta, and every resolved ambiguity.

The integrator then does the following:

1. Record `raw/integration-binding.log`.
2. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0119/gates`.
3. Record an uncached `integration-tests.log`.

## Authority

The writable paths are `src`, `tests`, `specs/capabilities/text-fonts.json`, and `engineering/evidence/FP-0119/`.
These protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
Only the integrator updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
The required reviewers are `fairpane-review` and `fairpane-security`.

## Non-goals

This task does none of the following:

- Hinting, grid fitting, phantom points, or `USE_MY_METRICS` metrics.
- Variations, CFF, rasterization, or device transforms.
- Changes to `parse`, `glyphHeader`, the C ABI, `include`, `api`, or `tools`.
- Performance claims.
