# FP-0123 task contract

## Identity

Task ID: `FP-0123`, "Implement the Encoding Standard labels, decode hooks, and the UTF-8, UTF-16, replacement, and x-user-defined decoders".
Workstream: `html-dom`.
Base: the commit that freezes this contract.
The pre-freeze check verified the observed facts below against the working tree at `0954a37`.
Prerequisite: `FP-0008`, accepted.
A `fairpane-spec` worker drafted this contract as the first part of the `FP-0065` split, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

### Integrator decisions

- `FP-0065` is split into `FP-0123`, `FP-0124`, `FP-0125`, and `FP-0126`. `FP-0065` keeps its four criteria word for word as the closing task.
- Commit `f90350b` admitted the Encoding Standard index files but committed none. `FP-0124` and `FP-0125` import them. This task imports no data.
- The normative baseline is the Encoding Standard source at whatwg/encoding commit `a985b62a9b45c17da3e17a9f0a0b4e30c34c4a8a`.
- Before freeze, the integrator records `raw/encoding-standard-pin.log` with the Git blob ID and SHA-256 of `encoding.bs` and `LICENSE` at that commit, the "Last Updated" date that <https://encoding.spec.whatwg.org/> shows, and whether `LICENSE` is byte-identical to `src/html/entities.LICENSE`.
- The label table is written into first-party code from the specification text.
  - `src/encoding/labels.zig` begins with `Copyright © WHATWG (Apple, Google, Mozilla, Microsoft).`. It states that the table is used under the BSD 3-Clause License, and it names the `LICENSE` blob `f2dcda46deccefd245749202a88a7837e35c6daa`.
  - If `raw/encoding-standard-pin.log` shows that `LICENSE` is byte-identical to `src/html/entities.LICENSE`, the comment refers to that file. Otherwise the integrator asks the owner before freeze.
  - `encodings.json` and `indexes.json` are not committed.
- Decoders are push-based. They write UTF-16 code units into a buffer that the caller supplies, and they never allocate.
- Errors are counted, not positioned, because the standard defines no error position. The laboratory adds no `decoder_errors` field.
- An encoding whose decoder belongs to a later slice returns `error.UnsupportedEncoding`, and `unsupportedOwner` names `FP-0124` or `FP-0125`.
- `src/web_string.zig` stops carrying its own UTF-8 decoder.
- The laboratory completes `decode` for all three byte order marks. A body without one stays `unsupported` with its current detail until `FP-0126`.
- No laboratory case or result format changes. FP-0008 case 21 changes on purpose for its two UTF-16 rows.
- Encoders, `TextDecoder`, `TextEncoder`, URL query encoding, and form submission belong to `FP-0026`'s frontier decomposition.

## Sources

- Encoding Standard, whatwg/encoding commit `a985b62a9b45c17da3e17a9f0a0b4e30c34c4a8a` (2026-05-21, "Editorial: separate TextDecoderStream constructor to two algorithms"), tree `2022fc6f63f2be90be78d10354609699857f1d39`.
  - `encoding.bs`: Git blob `684c72d8fd1d3578e3772677c73a2ab6aef6d7ee`, 145,368 bytes, SHA-256 `90bd4f43b965186afd34661d5ad0f45d35f9a178da895dcc9f08f610cc031c55`.
  - `LICENSE`: Git blob `f2dcda46deccefd245749202a88a7837e35c6daa`, 16,315 bytes, SHA-256 `85dc6f5ccb57a6fe8c33d158f9fc8fc7ee5655a5d3db2cdd131c6a3d0f48a864`, byte-identical to `src/html/entities.LICENSE`.
  - The integrator recorded both values and the published "Last Updated" date, 21 May 2026, in `raw/encoding-standard-pin.log` before the freeze; the date equals the commit date of `a985b62a`.
  - `encodings.json`: Git blob `74019c09603e215110831276384aa7d96f55b645`. Only the integrator's label count reads it, under `out/`.
  - Sections, numbered by heading order:
    - §3 "Terminology": I/O queue, read, peek, push, restore, end-of-queue, scalar value from surrogates.
    - §4.1 "Encoders and decoders": handler, process a queue, process an item, error mode.
    - §4.2 "Names and labels" and §4.3 "Output encodings".
    - §6 "Hooks for standards" and §6.1 "Legacy hooks for standards": decode, BOM sniff.
    - §8.1.1 "UTF-8 decoder"; §14.1.1 "replacement decoder"; §14.2.1 "shared UTF-16 decoder"; §14.3.1; §14.4.1; §14.5.1 "x-user-defined decoder".
    - "Implementation considerations".
- Infra Standard: ASCII whitespace is U+0009, U+000A, U+000C, U+000D, and U+0020. Also ASCII case-insensitive, and leading and trailing surrogates.
- HTML Standard at whatwg/html `efc54f7b` §13.2.3.2, step 1 only.
- Repository: `src/web_string.zig`, `src/lab.zig`, `src/root.zig`, `build.zig`, and `engineering/evidence/FP-0008/CONTRACT.md` ("Laboratory stages" and cases 18 to 26).

### Observed facts that shaped the decisions

- No `src/encoding/` directory and no `index-*.txt` file exist. `src/root.zig:3-12` exports no `encoding`.
- `lab.zig:1096-1118` completes `decode` only for EF BB BF. `lab.zig:1098-1104` returns `unsupported` for FE FF and FF FE.
- `lab.zig:194` allows three encoding names. `lab.zig:566` parses the name through `enumeration`, which rejects any other name at `lab.zig:385` with "expected a known name".
- `lab.zig:3054-3073`, FP-0008 case 21, asserts `unsupported` for `fp0008-decode-utf16le-bom.json` (FF FE 3C 00) and `fp0008-decode-utf16be-bom.json` (FE FF 00 3C). Both fixtures expect `"encoding": "UTF-8"`.
- `lab.zig:193` and `lab.zig:1091-1095` describe the base decode stage and become stale.
- `web_string.zig:233-290` holds a one-shot UTF-8 decoder. `Utf8Decoder` is declared at line 236, and it has callers at lines 65, 78, 161, and 197.
- `build.zig:5-39` lists the laboratory fixtures, and `build.zig:449-451` holds the exit-status cases.
- `specs/sources.json:711-716` holds S88, "Encoding Standard", at the unpinned URL.

## Behavior

### Files

| File | Content |
| --- | --- |
| `src/encoding/root.zig` | `Encoding`, names, `getEncoding`, `outputEncoding`, `Decoder`, `Decode`, `Utf8Decode`, `unsupportedOwner` |
| `src/encoding/labels.zig` | The 228-label table with the WHATWG attribution above |
| `src/encoding/utf8.zig` | The UTF-8 handler; it imports only `std` |
| `src/encoding/utf16.zig` | The shared UTF-16 handler |
| `src/encoding/tests.zig` | Cases 1 to 13, case 14's text scan, and case 16 |
| `src/root.zig` | Exports `encoding` and references it in `test` |
| `src/web_string.zig` | Calls `encoding/utf8.zig`; `Utf8Decoder` is removed; case 14's new rows |
| `src/lab.zig` | `decode` for three byte order marks, the encoding type, the module comment at lines 6 to 8, and the comments at lines 193 and 1091 to 1095 |
| `tests/lab/fp0123-*.json` | Case 15 fixtures |
| `build.zig` | `lab_fixtures` entries and one exit-status case |
| `specs/sources.json` | A new entry `S<next>`, titled `Encoding Standard at whatwg/encoding a985b62a`, with the URL of `encoding.bs` at the pinned commit. S88 stays unchanged. |

No file under `src/encoding` contains `export `, `callconv(`, `extern struct`, or `extern union`, and none imports `web_string.zig`.

### Interface

The Zig names are the intended shape. The worker may refine them without changing behavior.

```zig
pub const Encoding = enum { utf_8, ibm866, iso_8859_2, …, x_user_defined }; // 40 tags in table order
pub fn name(e: Encoding) []const u8;
pub fn fromName(text: []const u8) ?Encoding; // exact, case-sensitive
pub fn labels(e: Encoding) []const []const u8;
pub fn getEncoding(comptime Unit: type, label: []const Unit) ?Encoding; // Unit is u8 or u16
pub fn outputEncoding(e: Encoding) Encoding;
pub fn unsupportedOwner(e: Encoding) ?[]const u8; // "FP-0124", "FP-0125", or null
pub const ErrorMode = enum { replacement, fatal };
pub const Status = enum { input_empty, output_full, finished, malformed };
pub const Result = struct { read: usize, written: usize, errors: usize, status: Status };
pub const Decoder = struct {
    pub fn init(e: Encoding, mode: ErrorMode) error{UnsupportedEncoding}!Decoder;
    pub fn decode(d: *Decoder, input: []const u8, output: []u16, last: bool) Result;
};
pub const Decode = struct { // BOM sniff, then replacement mode
    pub fn init(fallback: Encoding) Decode;
    pub fn decode(d: *Decode, input: []const u8, output: []u16, last: bool) error{UnsupportedEncoding}!Result;
    pub fn encoding(d: *const Decode) ?Encoding; // null until decided
    pub fn bomLength(d: *const Decode) ?u2; // null until decided
};
pub const Utf8Decode = struct {
    pub const Kind = enum { utf8_decode, without_bom, without_bom_or_fail };
    pub fn init(kind: Kind) Utf8Decode;
    pub fn decode(d: *Utf8Decode, input: []const u8, output: []u16, last: bool) Result;
};
```

### Rules

- A call consumes bytes in order. The decoder keeps each byte that it has read but not yet decided (at most 3), and each byte that it restores. No later call needs earlier input.
- Each step writes at most 2 code units.
- A call makes progress when all of these hold: its input is nonempty or `last` is true; the decoder has not returned `malformed` or `finished`; and `output` has at least 2 free units. Progress means `read > 0`, `written > 0`, or status `finished` or `malformed`.
- With `last` false, exhausted input gives `input_empty`. With `last` true, the decoder processes end-of-queue and returns `finished`.
- A scalar value at or above U+10000 is written as a surrogate pair. No decoder writes an unpaired surrogate.
- In "replacement" mode, each error writes U+FFFD and adds 1 to `errors`.
- In "fatal" mode, the first error stops the call with `malformed`.
  - That call reports `errors` 1. Every other call reports 0.
  - `written` covers the output before the error.
  - `read` counts every byte that the call took, including the erroring byte and any byte that the handler restored.
  - Every later call returns `malformed` with 0 read and 0 written.
- After `finished`, every later call returns `finished` with `read = input.len` and `written = 0`. The call in which a replacement decoder finishes also reports `read = input.len`.
- `Decode` and `Utf8Decode(.utf8_decode)` decide the byte order mark only when 3 bytes are available or `last` is true, as "peek" requires.
- `getEncoding` removes leading and trailing ASCII whitespace, then matches labels ASCII case-insensitively. A code unit above 0x7F never matches.

### Names and labels

The table is frozen in §4.2 order. It has 40 names and 228 labels.

| Name | Labels |
| --- | --- |
| UTF-8 | unicode-1-1-utf-8, unicode11utf8, unicode20utf8, utf-8, utf8, x-unicode20utf8 |
| IBM866 | 866, cp866, csibm866, ibm866 |
| ISO-8859-2 | csisolatin2, iso-8859-2, iso-ir-101, iso8859-2, iso88592, iso_8859-2, iso_8859-2:1987, l2, latin2 |
| ISO-8859-3 | csisolatin3, iso-8859-3, iso-ir-109, iso8859-3, iso88593, iso_8859-3, iso_8859-3:1988, l3, latin3 |
| ISO-8859-4 | csisolatin4, iso-8859-4, iso-ir-110, iso8859-4, iso88594, iso_8859-4, iso_8859-4:1988, l4, latin4 |
| ISO-8859-5 | csisolatincyrillic, cyrillic, iso-8859-5, iso-ir-144, iso8859-5, iso88595, iso_8859-5, iso_8859-5:1988 |
| ISO-8859-6 | arabic, asmo-708, csiso88596e, csiso88596i, csisolatinarabic, ecma-114, iso-8859-6, iso-8859-6-e, iso-8859-6-i, iso-ir-127, iso8859-6, iso88596, iso_8859-6, iso_8859-6:1987 |
| ISO-8859-7 | csisolatingreek, ecma-118, elot_928, greek, greek8, iso-8859-7, iso-ir-126, iso8859-7, iso88597, iso_8859-7, iso_8859-7:1987, sun_eu_greek |
| ISO-8859-8 | csiso88598e, csisolatinhebrew, hebrew, iso-8859-8, iso-8859-8-e, iso-ir-138, iso8859-8, iso88598, iso_8859-8, iso_8859-8:1988, visual |
| ISO-8859-8-I | csiso88598i, iso-8859-8-i, logical |
| ISO-8859-10 | csisolatin6, iso-8859-10, iso-ir-157, iso8859-10, iso885910, l6, latin6 |
| ISO-8859-13 | iso-8859-13, iso8859-13, iso885913 |
| ISO-8859-14 | iso-8859-14, iso8859-14, iso885914 |
| ISO-8859-15 | csisolatin9, iso-8859-15, iso8859-15, iso885915, iso_8859-15, l9 |
| ISO-8859-16 | iso-8859-16 |
| KOI8-R | cskoi8r, koi, koi8, koi8-r, koi8_r |
| KOI8-U | koi8-ru, koi8-u |
| macintosh | csmacintosh, mac, macintosh, x-mac-roman |
| windows-874 | dos-874, iso-8859-11, iso8859-11, iso885911, tis-620, windows-874 |
| windows-1250 | cp1250, windows-1250, x-cp1250 |
| windows-1251 | cp1251, windows-1251, x-cp1251 |
| windows-1252 | ansi_x3.4-1968, ascii, cp1252, cp819, csisolatin1, ibm819, iso-8859-1, iso-ir-100, iso8859-1, iso88591, iso_8859-1, iso_8859-1:1987, l1, latin1, us-ascii, windows-1252, x-cp1252 |
| windows-1253 | cp1253, windows-1253, x-cp1253 |
| windows-1254 | cp1254, csisolatin5, iso-8859-9, iso-ir-148, iso8859-9, iso88599, iso_8859-9, iso_8859-9:1989, l5, latin5, windows-1254, x-cp1254 |
| windows-1255 | cp1255, windows-1255, x-cp1255 |
| windows-1256 | cp1256, windows-1256, x-cp1256 |
| windows-1257 | cp1257, windows-1257, x-cp1257 |
| windows-1258 | cp1258, windows-1258, x-cp1258 |
| x-mac-cyrillic | x-mac-cyrillic, x-mac-ukrainian |
| GBK | chinese, csgb2312, csiso58gb231280, gb2312, gb_2312, gb_2312-80, gbk, iso-ir-58, x-gbk |
| gb18030 | gb18030 |
| Big5 | big5, big5-hkscs, cn-big5, csbig5, x-x-big5 |
| EUC-JP | cseucpkdfmtjapanese, euc-jp, x-euc-jp |
| ISO-2022-JP | csiso2022jp, iso-2022-jp |
| Shift_JIS | csshiftjis, ms932, ms_kanji, shift-jis, shift_jis, sjis, windows-31j, x-sjis |
| EUC-KR | cseuckr, csksc56011987, euc-kr, iso-ir-149, korean, ks_c_5601-1987, ks_c_5601-1989, ksc5601, ksc_5601, windows-949 |
| replacement | csiso2022kr, hz-gb-2312, iso-2022-cn, iso-2022-cn-ext, iso-2022-kr, replacement |
| UTF-16BE | unicodefffe, utf-16be |
| UTF-16LE | csunicode, iso-10646-ucs-2, ucs-2, unicode, unicodefeff, utf-16, utf-16le |
| x-user-defined | x-user-defined |

### Laboratory

- A body that begins with a byte order mark completes `decode` with that mark's encoding, confidence `"certain"`, and `bom_bytes` 3 or 2. The rest of the body goes through that encoding's decoder in "replacement" mode.
- Any other body stays `unsupported` with the detail `"no byte order mark; encoding sniffing after BOM sniffing is not implemented"`.
- The two UTF-16 "not implemented" detail strings are removed.
- The laboratory encoding type becomes `encoding.Encoding`. Expectations and results use `name()`, and expectations parse with `fromName`.
- `environmentConsumers` is unchanged.

## Exact test cases

Notation:

- Inputs are hex bytes, and `|` separates chunks.
- Outputs are code points. A non-BMP code point is followed by its two UTF-16 units in parentheses.
- `E` is one error: U+FFFD in "replacement" mode. A row's error count equals its number of `E`s.
- A row runs in one call with `last` true unless it says otherwise.

1. **Names.** `name()` gives the 40 names in table order exactly. `fromName(name(e)) == e` for every `e`. `fromName("utf-8")` and `fromName("Utf-8")` are null.

2. **Label table.** `labels(e)` equals the frozen table, row by row and in order. There are 228 labels. Labels are unique across the table and are lowercase ASCII. For every `e`, the ASCII-lowercased `name(e)` is one of `labels(e)`.

3. **`getEncoding`, for `u8` and for `u16`.**
   - Every label maps to its encoding. So does its ASCII-uppercased form. So does the label surrounded on both sides by `09 0A 0C 0D 20`.
   - Each of these gives null: the empty label; `20`; `0B` + `utf-8`; `utf-8` + `00`; `utf-32`; `utf-7`; `utf_8`; `latin9`; `iso-8859-8 visual`; `x-user-defined` + `C2 A0`.
   - For `u16` only, U+212A + `oi8-r` and U+017F + `jis` give null.
   - Spot rows:
     - `utf-16` and `unicode` give UTF-16LE.
     - `unicodefffe` gives UTF-16BE.
     - `latin1`, `ascii`, and `us-ascii` give windows-1252.
     - `logical` gives ISO-8859-8-I, and `visual` gives ISO-8859-8.
     - `iso-2022-kr` gives replacement.
     - `x-mac-ukrainian` gives x-mac-cyrillic.
     - `tis-620` gives windows-874.

4. **`outputEncoding`.** replacement, UTF-16BE, and UTF-16LE give UTF-8. Every other encoding gives itself.

5. **UTF-8 decoder** (`Decoder(.utf_8, .replacement)`):

| Row | Input | Output |
| --- | --- | --- |
| A1 | (empty) | (empty), 0 errors |
| A2 | `41` | U+0041 |
| A3 | `00` | U+0000 |
| A4 | `7F 80` | U+007F E |
| A5 | `C2 80` | U+0080 |
| A6 | `DF BF` | U+07FF |
| A7 | `E0 A0 80` | U+0800 |
| A8 | `ED 9F BF` | U+D7FF |
| A9 | `EE 80 80` | U+E000 |
| A10 | `EF BF BF` | U+FFFF |
| A11 | `F0 90 80 80` | U+10000 (D800 DC00) |
| A12 | `F4 8F BF BF` | U+10FFFF (DBFF DFFF) |
| A13 | `F0 9F 92 A9` | U+1F4A9 (D83D DCA9) |
| A14 | `EF BF BD` | U+FFFD, 0 errors |
| A15 | `EF BB BF 41` | U+FEFF U+0041 |
| A16 | `C0 80` | E E |
| A17 | `C1 BF` | E E |
| A18 | `E0 80 80` | E E E |
| A19 | `E0 9F BF` | E E E |
| A20 | `ED A0 80` | E E E |
| A21 | `ED BF BF` | E E E |
| A22 | `F0 80 80 80` | E E E E |
| A23 | `F0 8F BF BF` | E E E E |
| A24 | `F4 90 80 80` | E E E E |
| A25 | `F5 80 80 80` | E E E E |
| A26 | `F8 88 80 80 80` | E E E E E |
| A27 | `FE FF` | E E |
| A28 | `C2 41` | E U+0041 |
| A29 | `E2 82 41` | E U+0041 |
| A30 | `F0 9F 92 41` | E U+0041 |
| A31 | `E2 82` | E |
| A32 | `F0 9F 92` | E |
| A33 | `C2` | E |
| A34 | `80 BF` | E E |
| A35 | `61 F1 80 80 E1 80 C2 62 80 63 80 BF 64` | U+0061 E E E U+0062 E U+0063 E E U+0064 |
| A36 | `F4 8F BF C0` | E E |

6. **UTF-16 decoders.**

   UTF-16LE:

| Row | Input | Output |
| --- | --- | --- |
| B1 | (empty) | (empty) |
| B2 | `41 00` | U+0041 |
| B3 | `FF FE` | U+FEFF |
| B4 | `3D D8 A9 DC` | U+1F4A9 |
| B5 | `00 D8 00 DC` | U+10000 |
| B6 | `FF DB FF DF` | U+10FFFF |
| B7 | `3D D8 41 00` | E U+0041 |
| B8 | `00 DC` | E |
| B9 | `00 DC 41 00` | E U+0041 |
| B10 | `41` | E |
| B11 | `3D D8` | E |
| B12 | `3D D8 41` | E |
| B13 | `3D D8 3D D8 A9 DC` | E U+1F4A9 |
| B14 | `FF D7 00 E0` | U+D7FF U+E000 |
| B15 | `00 DC 00 D8` | E E |

   UTF-16BE:

| Row | Input | Output |
| --- | --- | --- |
| C1 | `00 41` | U+0041 |
| C2 | `FE FF` | U+FEFF |
| C3 | `D8 3D DC A9` | U+1F4A9 |
| C4 | `D8 3D 00 41` | E U+0041 |
| C5 | `DC 00` | E |
| C6 | `00` | E |
| C7 | `D8 3D` | E |
| C8 | `D8 3D 00` | E |

7. **replacement and x-user-defined.**
   - D1: (empty) ⇒ (empty), 0 errors.
   - D2: `41` ⇒ E.
   - D3: `41 42 43` ⇒ E.
   - D4: `EF BB BF` ⇒ E.
   - D5: `41` | `42`, with `last` on the second call ⇒ E.
   - X1: `00 41 7F 80 81 FE FF` ⇒ U+0000 U+0041 U+007F U+F780 U+F781 U+F7FE U+F7FF, 0 errors.
   - X2: all 256 bytes in order ⇒ 0x00 to 0x7F unchanged, then U+F780 to U+F7FF, 0 errors.

8. **Fatal mode.** F1 to F4 and F7 use `Decoder(.utf_8, .fatal)`.
   - F1: `41 42` ⇒ U+0041 U+0042, `finished`.
   - F2: `41 C2 41 42` ⇒ `malformed`, written U+0041, read 3, errors 1.
   - F3: `41 FF 42` ⇒ `malformed`, written U+0041, read 2, errors 1.
   - F4: `F0 9F 92` ⇒ `malformed` at end-of-queue, nothing written, read 3, errors 1.
   - F5: UTF-16LE `41 00 00 DC` ⇒ `malformed`, written U+0041, read 4, errors 1.
   - F6: replacement. (empty) ⇒ `finished`. `41` ⇒ `malformed`, read 1.
   - F7: after F2, a call with `41` ⇒ `malformed`, read 0, written 0, errors 0.
   - F8: UTF-16BE `00 41 DC 00` ⇒ `malformed`, written U+0041, read 4, errors 1.

9. **The "decode" hook.** Each row gives input and fallback ⇒ encoding, BOM length, output.
   - G1: `EF BB BF 41`, UTF-8 ⇒ UTF-8, 3, U+0041.
   - G2: `EF BB BF 41`, UTF-16LE ⇒ UTF-8, 3, U+0041.
   - G3: `FE FF 00 41`, UTF-8 ⇒ UTF-16BE, 2, U+0041.
   - G4: `FF FE 41 00`, UTF-8 ⇒ UTF-16LE, 2, U+0041.
   - G5: `EF BB BF EF BB BF`, UTF-8 ⇒ UTF-8, 3, U+FEFF.
   - G6: `FF FE FF FE`, UTF-8 ⇒ UTF-16LE, 2, U+FEFF.
   - G7: `FE FF FF FE`, UTF-8 ⇒ UTF-16BE, 2, U+FFFE.
   - G8: `EF BB`, UTF-8 ⇒ UTF-8, 0, E.
   - G9: `FF FE`, UTF-8 ⇒ UTF-16LE, 2, (empty).
   - G10: `FE`, UTF-8 ⇒ UTF-8, 0, E.
   - G11: `FE FF 41`, UTF-8 ⇒ UTF-16BE, 2, E.
   - G12: `41 42 43`, UTF-16LE ⇒ UTF-16LE, 0, U+4241 E.
   - G13: `EF BB BF`, replacement ⇒ UTF-8, 3, (empty).
   - G14: `41`, replacement ⇒ replacement, 0, E.
   - G15: (empty), UTF-8 ⇒ UTF-8, 0, (empty).
   - G16: `41`, windows-1252 ⇒ `error.UnsupportedEncoding`, and `unsupportedOwner(.windows_1252)` is `"FP-0124"`.
   - G17: `FF FE 41 00`, windows-1252 ⇒ UTF-16LE, 2, U+0041.
   - G18: `EF BB BF FE FF`, UTF-8 ⇒ UTF-8, 3, E E.
   - BOM timing, with fallback UTF-8:
     - T1: `FF FE` with `last` false ⇒ 0 written, and `encoding()` is null. Then `41` with `last` false ⇒ `encoding()` is UTF-16LE, 0 written. Then `00` with `last` true ⇒ U+0041.
     - T2: `EF` | `BB` | `BF` | `41`, with `last` on the final call ⇒ UTF-8, 3, U+0041.
     - T3: `EF BB` with `last` false ⇒ `encoding()` is null. Then an empty call with `last` true ⇒ UTF-8, 0, E.

10. **UTF-8 hooks.**
    - H1: `utf8_decode` `EF BB BF 41` ⇒ U+0041.
    - H2: `utf8_decode` `FE FF 00 41` ⇒ E E U+0000 U+0041.
    - H3: `utf8_decode` `EF BB` ⇒ E.
    - H4: `utf8_decode` `EF BB BF EF BB BF` ⇒ U+FEFF.
    - H5: `without_bom` `EF BB BF 41` ⇒ U+FEFF U+0041.
    - H6: `without_bom_or_fail` `41 42` ⇒ U+0041 U+0042.
    - H7: `without_bom_or_fail` `41 C2` ⇒ `malformed`.
    - H8: `without_bom_or_fail` `EF BB BF` ⇒ U+FEFF.

11. **Unsupported encodings.** `Decoder.init` returns `error.UnsupportedEncoding` for each of the 35 index-based encodings. `unsupportedOwner` returns:
    - `"FP-0124"` for the 28 single-byte encodings;
    - `"FP-0125"` for GBK, gb18030, Big5, EUC-JP, ISO-2022-JP, Shift_JIS, and EUC-KR;
    - null for the 5 encodings that this task implements.

12. **Partitions.** The rows are every single-call row of cases 5 to 10 whose input has at most 13 bytes, except G16. T1 to T3, F6, and F7 are excluded.
    - Every partition into nonempty consecutive chunks, 2^(n−1) of them, gives the same output as one call. In replacement mode the error count is also the same. In fatal mode the status and the output before `malformed` are the same.
    - `last` is set only on the final chunk. A second run adds an empty final call that carries `last`.
    - Repeated calls with a 2-unit output buffer give the same output.

13. **Sweep.**
    - Input: every scalar value U+0000 to U+D7FF and U+E000 to U+10FFFF, in order. It is encoded as UTF-8 with `std.unicode.utf8Encode`, as UTF-16LE, and as UTF-16BE.
    - Each encoding decodes in 7-byte chunks to exactly that sequence in UTF-16, with 0 errors.
    - No output of this case, or of cases 5 to 10, contains an unpaired surrogate.
    - The sweep's inputs and outputs are allocated with `testing.allocator`. No test holds them on the stack.

14. **`web_string` regressions.**
    - These tests stay unchanged and pass: `web_string` tests 2 to 7, 14, 15, and 16; "code-unit indexes map back to UTF-8 byte offsets"; and FP-0047 cases 1 to 6.
    - New rows in `src/web_string.zig`:
      - `WebString.fromUtf8` and `WebString.fromUtf8Lossy` of `EF BB BF 41` each give U+FEFF U+0041.
      - `codeUnitIndexForUtf8Offset("\xED\xA0\x80", byteOffset(0))` returns `error.InvalidUtf8`.
    - A text scan in `src/encoding/tests.zig` reads `src/web_string.zig`. It finds no `Utf8Decoder`, `bytes_needed`, or `lower_boundary`, and it finds `@import("encoding/utf8.zig")`.

15. **Laboratory.** `utf16LeDigest` and `hexDigest` compute every digest in the test.
    - **Lab-1** (FP-0008 case 21, revised):
      - `fp0008-tokenize-no-bom.json` stays `unsupported` with the no-BOM detail.
      - `fp0008-decode-utf16le-bom.json` reports `fail`, stage `decode`, check `encoding`, expected `"UTF-8"`, observed `"UTF-16LE"`. `decode` is `completed` with `"certain"`, `bom_bytes` 2, `code_units` 1, `output_sha256` equal to `utf16LeDigest("<")`, and `detail` null.
      - `fp0008-decode-utf16be-bom.json` gives the same with `"UTF-16BE"`.
    - **Lab-2:** `fp0123-decode-utf16le.json`, body `FF FE 3C 00 70 00 3E 00`, decode expectation `"UTF-16LE"`, `"certain"`, `utf16LeDigest("<p>")` ⇒ `pass`, with `bom_bytes` 2 and `code_units` 3.
    - **Lab-3:** `fp0123-tokenize-utf16be.json`, body `FE FF 00 3C 00 70 00 3E` ⇒ `pass`, with `token_count` 2, `errors` `[]`, and the digest of this dump (each line ends in LF):

      ```text
      ["StartTag","p",[],false,[0,3]]
      ["EOF",[3,3]]
      ```

    - **Lab-4:** `fp0123-tokenize-utf16le-errors.json`, body `FF FE 61 00 00 DC 62 00 3D D8 A9 DC` ⇒ `pass`, with `code_units` 5, `token_count` 2, `errors` `[]`, and the digest of this dump:

      ```text
      ["Character","a\uFFFDb\uD83D\uDCA9",[0,5]]
      ["EOF",[5,5]]
      ```

    - **Lab-5:** `fp0123-decode-name-shift-jis.json`, body `<p>`, with a decode expectation naming `"Shift_JIS"`, is a valid case. It reports `unsupported` at `decode` with the no-BOM detail.
    - **Lab-6:** `std.testing.checkAllAllocationFailures` runs Lab-3 and Lab-4 as the test at `lab.zig:2983` does. Each induced failure reports `harness-error`, and nothing leaks. The run without induced failures reports `pass` with `decode` `completed`.
    - **Lab-7:** a `build.zig` exit-status case runs `run` on Lab-3 and gets exit status 0.
    - **Lab-8:** FP-0007 case 2 and FP-0008 cases 18, 23, 24, and 26 stay unchanged and pass.
    - **Lab-9:** `fp0123-decode-bom-only.json`, body `FF FE`, expectation `"UTF-16LE"`, `"certain"`, `utf16LeDigest("")` ⇒ `pass`, with `code_units` 0.
    - **Lab-10:** `fp0123-decode-name-lowercase.json`, body `FF FE 3C 00`, with a decode expectation naming `"utf-16le"`, is invalid. The subject is `expect.encoding` and the message is "expected a known name", as FP-0007 case 1 asserts for invalid fixtures.

16. **Isolation.**
    - `src/root.zig` exports `encoding`.
    - A test reads every `.zig` file under `src/encoding` and finds none of `export `, `callconv(`, `extern struct`, `extern union`, or `web_string.zig`. Each needle is built at comptime from two literals, such as `"call" ++ "conv("`, so `tests.zig` contains no needle.
    - In every file except `tests.zig`, the test also finds no `Allocator` and no `std.heap`.
    - In `utf8.zig`, every `@import` names `std`.

**Before the change:**

- Cases 1 to 13 and 16, and case 14's text scan, fail to compile. The staged `src/encoding/tests.zig` and the `src/root.zig` test reference name declarations that `src/encoding/root.zig` does not yet define. `tests-before.log` must show that compile error.
- Case 14's text scan also cannot pass on the base, because `web_string.zig:236` declares `Utf8Decoder`.
- `tests-before-lab.log` runs the laboratory and `web_string` tests on the base:
  - Lab-1, Lab-2, Lab-3, Lab-4, Lab-6, Lab-7, and Lab-9 fail there, because `lab.zig:1098-1104` makes every UTF-16 body `unsupported`. The base asserts that behavior at `lab.zig:3054-3073`.
  - Lab-5 fails there, because `lab.zig:194` and `lab.zig:566`, through `lab.zig:385`, reject `"Shift_JIS"`.
  - Lab-8, Lab-10, and case 14's other rows pass there. They are regression guards.

### Derivations

- **A18** `E0 80 80`: E0 sets the lower boundary to 0xA0. 80 is out of range, so it is restored and an error is returned. Each 80 then arrives with no bytes needed and is an error.
- **A20** `ED A0 80`: ED sets the upper boundary to 0x9F. A0 is out of range: restored, error. A0 and 80 then each error.
- **A24** `F4 90 80 80`: F4 sets the upper boundary to 0x8F. 90 is out of range: restored, error. Then three more errors.
- **A26** `F8 88 80 80 80`: F8 matches no lead range and is an error. 88 and each 80 arrive with no bytes needed and are errors, five in all.
- **A29** `E2 82 41`: E2 needs 2 bytes. 82 is in 0x80 to 0xBF. 41 is out of range: restored, error. Then U+0041.
- **A35** `61 F1 80 80 E1 80 C2 62 80 63 80 BF 64`:
  1. `a`.
  2. F1 needs 3, and two 80 bytes are seen. E1 is out of range: restored, error.
  3. E1 needs 2, and 80 is seen. C2 is out of range: restored, error.
  4. C2 needs 1. 62 is out of range: restored, error.
  5. `b`. 80 is an error. `c`. 80 and BF are errors. `d`.
- **A36** `F4 8F BF C0`: F4 sets the upper boundary to 0x8F. 8F is in range, and the boundaries reset. BF is in range. C0 is out of range: restored, error. C0 then errors alone.
- **B7** `3D D8 41 00`: 0xD83D is a leading surrogate. 0x0041 is not a trailing surrogate, so bytes `41 00` are restored in LE order (byte2, byte1), and an error is returned. Then U+0041.
- **B12** `3D D8 41`: the leading surrogate is set, and 41 becomes the leading byte. At end-of-queue one of them is non-null, so both are cleared and one error is returned.
- **B13** `3D D8 3D D8 A9 DC`: the second 0xD83D is not trailing: restored, error. 0xD83D then 0xDCA9 gives 0x10000 + (0x3D << 10) + 0xA9 = U+1F4A9.
- **B14** `FF D7 00 E0`: (0xD7 << 8) + 0xFF = U+D7FF, and (0xE0 << 8) + 0x00 = U+E000.
- **C4** `D8 3D 00 41`: BE restores byte1, byte2 = `00 41`.
- **D3** `41 42 43`: the first byte sets "replacement error returned" and returns an error. The next byte returns `finished`.
- **F2** `41 C2 41 42`: `A` (read 1). C2 continues (read 2). 41 errors and is restored (read 3). The call stops.
- **F8** `00 41 DC 00`: 0x0041 gives U+0041. 0xDC00 is a trailing surrogate with no leading surrogate, which is an error (read 4).
- **G7** `FE FF FF FE`: the byte order mark gives UTF-16BE. FF FE is 0xFFFE.
- **G8** `EF BB`: peek returns 2 bytes, so there is no byte order mark. UTF-8 needs 2 bytes, BB is seen, and end-of-queue gives one error.
- **G12** `41 42 43`, fallback UTF-16LE: there is no byte order mark. (0x42 << 8) + 0x41 = U+4241. 43 stays pending until end-of-queue gives an error.
- **H2** `FE FF 00 41`: the peek is not EF BB BF. FE and FF each error. Then U+0000 and U+0041.
- **T1** `FF FE`, then `41`, then `00`: no decision is possible before 3 bytes. After `41`, the byte order mark gives UTF-16LE, and 41 is the leading byte. `00` completes U+0041.
- **Lab-4** `FF FE 61 00 00 DC 62 00 3D D8 A9 DC`: U+0061; the lone 0xDC00 gives E (U+FFFD); U+0062; then U+1F4A9 as 2 units, for 5 units in all. U+FFFD raises no preprocessing error, and the pair is one code point (FP-0008, "Input model").

### Mutation controls

Each control is recorded as a `.diff`, applied with `git apply`, run, and reversed with `git apply -R`. File hashes are recorded before, during, and after each control.

| Control | Mutation | Cases that must fail |
| --- | --- | --- |
| M1 | The UTF-8 handler consumes the out-of-range byte instead of restoring it. | A28, A29, A30, and `web_string` test 6 |
| M2 | The ED upper boundary is not applied. | A20, A21, `web_string` tests 5 and 7, and case 14's `codeUnitIndexForUtf8Offset` row. `web_string.zig:466` and `:485` both decode ED A0 80. |
| M3 | A non-trailing unit after a leading surrogate is dropped instead of restored. | B7, B13, C4 |
| M4 | End-of-queue with both a leading byte and a leading surrogate reports two errors. | B12, C8 |
| M5 | The replacement decoder reports an error on empty input. | D1 |
| M6 | `Decode` decides the byte order mark from the first chunk without waiting for 3 bytes. | T1, T2, and case 12 on G1 |
| M7 | `getEncoding` does not trim ASCII whitespace. | Case 3's whitespace variants |
| M8 | The laboratory maps both UTF-16 byte order marks to UTF-16LE. | Lab-1's BE fixture, Lab-3 |
| M9 | Fatal mode writes U+FFFD and continues. | F2, F3, H7 |

### Stop rules

- If a frozen row contradicts `encoding.bs` at the pin, stop and report the row and the text. Never edit an expectation silently.
- If `encoding.bs` or `LICENSE` fetched at the pin has a blob ID other than the one above, stop.
- If removing `Utf8Decoder` changes any `web_string` result, stop and report it.
- If the unit-test run step in `tests-after.log` exceeds the one in `tests-base.log` by more than 10 seconds, stop and report both durations. Do not reduce coverage.

### Criterion mapping

| Plan criterion | Cases and evidence |
| --- | --- |
| 1. Pin, names, labels | 1 to 4; `raw/encoding-standard-pin.log`; `integrator-label-count.log` |
| 2. Five streaming decoders and both error modes | 5 to 8, 12, 13, 16; M1 to M5, M9 |
| 3. Hooks, and other encodings unsupported with owners | 9 to 11; M6 |
| 4. One UTF-8 decoder | 14; M1, M2 |
| 5. UTF-16 byte order marks in the laboratory | 15; M8 |
| 6. Errors and replacement exact | 5 to 10, 15 |
| 7. Added run-step time | The unit-test run-step durations that the build summaries of `tests-base.log` and `tests-after.log` report, and their difference in the README |

### Remaining obligations

- `FP-0124` owns the 28 single-byte decoders and their index data.
- `FP-0125` owns the seven CJK decoders and their index data.
- `FP-0126` owns sniffing after the byte order mark, the locale default, "change the encoding", and the WPT record.
- `FP-0026`'s frontier decomposition owns encoders, `TextDecoder`, `TextEncoder`, URL query encoding, form submission, and laboratory `Content-Type` plumbing.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0123/raw/`.
Run every Zig command with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
Use `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe` as the Zig executable.
Never delete or overwrite a log. Name each log of a failed attempt with the suffix `-attempt-N`, and list it with its cause in the README.

0. Before staging any change, delete `out/fp0123-base`. Then record `tests-base.log` with `HEAD` and `zig build test --summary all --cache-dir out/fp0123-base` on the base. It must exit with status 0.
1. Write cases 1 to 16 before the implementation. Record `tests-before.log` with `HEAD`, the staging command, the blob ID of every staged file, and `zig build test --summary all --cache-dir out/fp0123-before`. It must fail with the compile error that "Before the change" names.
2. Stage only these files:
   - the case 15 tests in `src/lab.zig`, which use only base declarations;
   - case 14's new rows in `src/web_string.zig`;
   - the `tests/lab/fp0123-*.json` fixtures;
   - the `build.zig` entries.

   Then record `tests-before-lab.log` with `HEAD`, the staging command, the blob ID of every staged file, and `zig build test --summary all --cache-dir out/fp0123-before-lab`. It must show Lab-1 to Lab-7 and Lab-9 failing, and Lab-8, Lab-10, and case 14's other rows passing.
3. Delete `out/fp0123-after`. Then record `tests-after.log` with `cmd /d /c ver` and `zig build test --summary all --cache-dir out/fp0123-after`. It must exit with status 0.
4. Record `fmt.log` with `zig fmt --check build.zig src tests`. It must exit with status 0.
5. Record `controller-tests-after.log` with `node --version` and `node tools/fairpane.mjs test`.
6. Record `mutation.log`, and `mutation-M1.diff` through `mutation-M9.diff`.
7. Write `engineering/evidence/FP-0123/README.md` with:
   - the worktree `HEAD`;
   - the criterion mapping;
   - the unit-test run-step durations of `tests-base.log` and `tests-after.log`, and their difference;
   - each control's result;
   - every attempt;
   - every resolved ambiguity.

The integrator does the following.

1. Before freeze, record `raw/encoding-standard-pin.log`:
   1. Fetch `encoding.bs` and `LICENSE` at the commit into `out/fp0123-encoding/`.
   2. Require the blob IDs above with `git hash-object`.
   3. Record each file's SHA-256 with `cmd /d /c certutil -hashfile <file> SHA256`.
   4. Record the "Last Updated" date of <https://encoding.spec.whatwg.org/>.
   5. Compare `LICENSE` byte for byte with `src/html/entities.LICENSE`, and apply the attribution decision above.
   6. Copy both SHA-256 values and the date into this contract.
2. Record `HEAD` and `git status --porcelain=v1 --ignored --untracked-files=all` for every source root in `raw/integration-binding.log`, before and after the gates.
3. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0123/gates`. Report the `zig-test` gate duration from its receipt next to criterion 7.
4. Record an uncached `integration-tests.log`.
5. Record `integrator-label-count.log`. It counts the names and labels in `encodings.json` at the pin, fetched to `out/` and not committed, and requires 40 and 228.

## Authority

Writable paths are `src`, `tests`, `build.zig`, `specs/sources.json`, and `engineering/evidence/FP-0123/`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
`specs/applicability/wpt.json` stays unchanged.
The integrator alone updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
Required reviewers are `fairpane-review` and `fairpane-spec`.

## Non-goals

- No index import, no single-byte or CJK decoder, and no sniffing after the byte order mark.
- No encoder, no `TextDecoder` or `TextEncoder`, and no C ABI, `include`, or `api` change.
- No laboratory case or result format change, and no `decoder_errors` field.
- No WPT item runs.
- No SIMD path and no performance claim.
