/**
 * The Unicode property tables: parsing of the imported UCD files and deterministic generation of `src/unicode/tables.zig`.
 * `ucd-generate` writes the table; `ucd-check` regenerates it in memory and names the first differing line.
 */
import fs from 'node:fs';
import path from 'node:path';
import { sha256, safePath } from './lib.mjs';

export const UCD_VERSION = '18.0.0';
export const UCD_DIR = 'src/unicode/ucd';
export const UCD_LICENSE = `${UCD_DIR}/license.txt`;
export const GENERATED_PATH = 'src/unicode/tables.zig';
/** The eleven imported UCD files, in the order the generated header lists them. */
export const UCD_FILES = Object.freeze([
  `${UCD_DIR}/Scripts.txt`,
  `${UCD_DIR}/ScriptExtensions.txt`,
  `${UCD_DIR}/PropertyValueAliases.txt`,
  `${UCD_DIR}/extracted/DerivedBidiClass.txt`,
  `${UCD_DIR}/extracted/DerivedJoiningType.txt`,
  `${UCD_DIR}/extracted/DerivedGeneralCategory.txt`,
  `${UCD_DIR}/IndicSyllabicCategory.txt`,
  `${UCD_DIR}/IndicPositionalCategory.txt`,
  `${UCD_DIR}/auxiliary/GraphemeBreakProperty.txt`,
  `${UCD_DIR}/DerivedCoreProperties.txt`,
  `${UCD_DIR}/emoji/emoji-data.txt`,
]);
const ALIASES_FILE = `${UCD_DIR}/PropertyValueAliases.txt`;

/**
 * The generated enumerations: Zig type name, table name prefix, `PropertyValueAliases.txt` property, and source file.
 * `field` marks a file that holds several properties, whose lines name the property in their first value field.
 */
const PROPERTIES = Object.freeze([
  { type: 'GeneralCategory', name: 'general_category', property: 'gc', file: `${UCD_DIR}/extracted/DerivedGeneralCategory.txt`, onlyOccurring: true },
  { type: 'Script', name: 'script', property: 'sc', file: `${UCD_DIR}/Scripts.txt` },
  { type: 'BidiClass', name: 'bidi_class', property: 'bc', file: `${UCD_DIR}/extracted/DerivedBidiClass.txt` },
  { type: 'JoiningType', name: 'joining_type', property: 'jt', file: `${UCD_DIR}/extracted/DerivedJoiningType.txt` },
  { type: 'IndicSyllabicCategory', name: 'indic_syllabic_category', property: 'InSC', file: `${UCD_DIR}/IndicSyllabicCategory.txt` },
  { type: 'IndicPositionalCategory', name: 'indic_positional_category', property: 'InPC', file: `${UCD_DIR}/IndicPositionalCategory.txt` },
  { type: 'GraphemeClusterBreak', name: 'grapheme_cluster_break', property: 'GCB', file: `${UCD_DIR}/auxiliary/GraphemeBreakProperty.txt`, onlyOccurring: true },
  { type: 'IndicConjunctBreak', name: 'indic_conjunct_break', property: 'InCB', file: `${UCD_DIR}/DerivedCoreProperties.txt`, field: true },
]);
/** The generated binary properties: table name prefix, property name in the file, and source file. */
const BINARY_PROPERTIES = Object.freeze([
  { name: 'extended_pictographic', property: 'Extended_Pictographic', file: `${UCD_DIR}/emoji/emoji-data.txt` },
]);
const CODE_POINTS = 0x110000;
const UNSET = 0xFFFF;
/** The `ScriptExtensions.txt` value for a code point whose extensions are its Script value. */
const SCRIPT_VALUE = '<script>';

export class UcdError extends Error {
  constructor(message) { super(message); this.name = 'UcdError'; }
}
function fail(file, line, message) { throw new UcdError(`${file} line ${line}: ${message}`); }

/**
 * Read `PropertyValueAliases.txt`. The result maps each property to its values in file order,
 * each with its short alias (the second field) and every alias field, and to a map from every alias to the short alias.
 */
export function parseAliases(text, file) {
  const properties = new Map();
  text.split('\n').forEach((raw, i) => {
    const body = raw.replace(/#.*$/, '').trim();
    if (!body) return;
    const fields = body.split(';').map(f => f.trim());
    if (fields.length < 3) fail(file, i + 1, 'an alias line needs a property, a short alias, and a long alias');
    const [property, short, ...rest] = fields;
    if (!properties.has(property)) properties.set(property, { values: [], lookup: new Map() });
    const p = properties.get(property);
    const aliases = [short, ...rest].filter(Boolean);
    p.values.push({ short, aliases });
    for (const alias of aliases) {
      if (p.lookup.has(alias) && p.lookup.get(alias) !== short) fail(file, i + 1, `alias "${alias}" of ${property} names two values`);
      p.lookup.set(alias, short);
    }
  });
  return properties;
}

const RANGE = /^([0-9A-Fa-f]+)(?:\.\.([0-9A-Fa-f]+))?$/;
function parseRange(text, file, line) {
  const m = RANGE.exec(text.trim());
  if (!m) fail(file, line, `malformed code point range "${text.trim()}"`);
  const first = parseInt(m[1], 16), last = m[2] === undefined ? first : parseInt(m[2], 16);
  for (const [digits, value] of [[m[1], first], [m[2], last]]) {
    if (digits !== undefined && value > 0x10FFFF) fail(file, line, `code point ${digits.toUpperCase()} is above 10FFFF`);
  }
  if (first > last) fail(file, line, 'the range starts after its end');
  return { first, last };
}

/**
 * Call `visit` with each data line and each `# @missing:` line of a UCD file, in file order. Each entry has the range,
 * the trimmed value fields after the range, the line number, and whether the line is an `@missing` line.
 * Comments are stripped before the fields are split, so `Extended_Pictographic# comment` has the field `Extended_Pictographic`.
 */
function forEachLine(text, file, visit) {
  text.split('\n').forEach((raw, i) => {
    const line = i + 1, trimmed = raw.replace(/\r$/, '');
    const missingMatch = /^#\s*@missing:(.*)$/.exec(trimmed);
    let body;
    if (missingMatch) body = missingMatch[1].replace(/#.*$/, '');
    else {
      body = trimmed.replace(/#.*$/, '');
      if (!body.trim()) return;
    }
    const semicolon = body.indexOf(';');
    if (semicolon < 0) fail(file, line, 'the data line has no ";"');
    const range = parseRange(body.slice(0, semicolon), file, line);
    const fields = body.slice(semicolon + 1).split(';').map(f => f.trim());
    visit({ ...range, fields, line, missing: Boolean(missingMatch) });
  });
}

/**
 * Read the assignments of a single-property UCD file: every `# @missing:` line in file order, then every data line in file order.
 * Each later assignment overrides earlier ones for its range, as UAX #44 section 4.2.10 states for `@missing` lines.
 */
function assignments(text, file) {
  const missing = [], data = [];
  forEachLine(text, file, l => {
    if (l.fields.length !== 1 || !l.fields[0]) fail(file, l.line, 'a line needs exactly one value');
    (l.missing ? missing : data).push({ first: l.first, last: l.last, value: l.fields[0], line: l.line });
  });
  return [...missing, ...data];
}

/** Resolve assignments, in order, to a dense table of short aliases. Every code point needs a value. */
function denseProperty(list, file, aliases) {
  const names = [], index = new Map(), dense = new Uint16Array(CODE_POINTS).fill(UNSET);
  for (const a of list) {
    const short = aliases.lookup.get(a.value);
    if (short === undefined) fail(file, a.line, `unknown value "${a.value}"`);
    if (!index.has(short)) { index.set(short, names.length); names.push(short); }
    dense.fill(index.get(short), a.first, a.last + 1);
  }
  const gap = dense.indexOf(UNSET);
  if (gap >= 0) throw new UcdError(`${file}: U+${gap.toString(16).toUpperCase().padStart(4, '0')} has no value and no @missing default.`);
  return { names, dense, valueAt: cp => names[dense[cp]] };
}

/**
 * Parse a single-property UCD file into a dense table of short aliases.
 * `aliases` is the `parseAliases` entry of the property. Every code point needs a value.
 */
export function parseProperty(text, { file, aliases }) {
  return denseProperty(assignments(text, file), file, aliases);
}

/**
 * Parse one enumerated property of a file that holds several, such as `InCB` in `DerivedCoreProperties.txt`.
 * A data or `@missing` line whose first value field is exactly `property` must have exactly one more field, its value,
 * which resolves through `aliases`. A line whose first field names another property is skipped.
 * `@missing` lines apply first, in file order, then data lines. Every code point needs a value.
 */
export function parseFieldProperty(text, { file, aliases, property }) {
  const missing = [], data = [];
  forEachLine(text, file, l => {
    if (l.fields[0] !== property) return;
    if (l.fields.length < 2 || !l.fields[1]) fail(file, l.line, `the ${property} line has no value`);
    if (l.fields.length > 2) fail(file, l.line, `the ${property} line has more than one value`);
    (l.missing ? missing : data).push({ first: l.first, last: l.last, value: l.fields[1], line: l.line });
  });
  return denseProperty([...missing, ...data], file, aliases);
}

/**
 * Parse one binary property of a file that lists only its true ranges, such as `Extended_Pictographic` in `emoji-data.txt`.
 * A line whose only value field is exactly `property` makes its range true. A line whose first field names another property is skipped,
 * and a line that gives `property` a value fails. Every code point that no line lists is false.
 */
export function parseBinaryProperty(text, { file, property }) {
  const dense = new Uint8Array(CODE_POINTS);
  forEachLine(text, file, l => {
    if (l.fields[0] !== property) return;
    if (l.fields.length !== 1) fail(file, l.line, `the binary property ${property} takes no value`);
    dense.fill(1, l.first, l.last + 1);
  });
  return { dense, valueAt: cp => dense[cp] === 1 };
}

/**
 * Parse `ScriptExtensions.txt`. Each value is a space-separated list of Script aliases, and `<script>` marks code points
 * whose Script_Extensions value is their Script value. The result's `dense` holds a set index or UNSET for `<script>`.
 */
export function parseExtensions(text, { file, aliases }) {
  const sets = [], index = new Map(), dense = new Uint16Array(CODE_POINTS).fill(UNSET);
  let covered = new Uint8Array(CODE_POINTS);
  for (const a of assignments(text, file)) {
    let slot = UNSET;
    if (a.value !== SCRIPT_VALUE) {
      const shorts = a.value.split(/\s+/).map(name => {
        const short = aliases.lookup.get(name);
        if (short === undefined) fail(file, a.line, `unknown value "${name}"`);
        return short;
      });
      const key = [...new Set(shorts)].sort().join(' ');
      if (!index.has(key)) { index.set(key, sets.length); sets.push([...new Set(shorts)]); }
      slot = index.get(key);
    }
    dense.fill(slot, a.first, a.last + 1);
    covered.fill(1, a.first, a.last + 1);
  }
  const gap = covered.indexOf(0);
  if (gap >= 0) throw new UcdError(`${file}: U+${gap.toString(16).toUpperCase().padStart(4, '0')} has no value and no @missing default.`);
  covered = null;
  return { sets, dense };
}

// Zig generation.
const ZIG_KEYWORDS = new Set(['addrspace', 'align', 'allowzero', 'and', 'anyframe', 'anytype', 'asm', 'break', 'callconv', 'catch', 'comptime',
  'const', 'continue', 'defer', 'else', 'enum', 'errdefer', 'error', 'export', 'extern', 'fn', 'for', 'if', 'inline', 'linksection', 'noalias',
  'noinline', 'nosuspend', 'opaque', 'or', 'orelse', 'packed', 'pub', 'resume', 'return', 'struct', 'suspend', 'switch', 'test', 'threadlocal',
  'try', 'union', 'unreachable', 'var', 'volatile', 'while', 'true', 'false', 'null', 'undefined', 'type', 'void', 'bool', 'noreturn', 'anyerror',
  'anyopaque', 'isize', 'usize', 'c_int']);
const identifier = name => /^[A-Za-z_][A-Za-z0-9_]*$/.test(name) && !ZIG_KEYWORDS.has(name) && !/^[iu]\d+$/.test(name) ? name : `@"${name}"`;
const hex = cp => `0x${cp.toString(16).toUpperCase().padStart(6, '0')}`;
const zigString = s => JSON.stringify(s);

/** Emit the start of each run of equal values in `dense`, as `[start, value]` pairs. */
function runs(dense) {
  const out = [];
  for (let cp = 0; cp < dense.length; cp++) if (cp === 0 || dense[cp] !== dense[cp - 1]) out.push([cp, dense[cp]]);
  return out;
}

function enumBlock(type, tags, aliasTable) {
  const backing = tags.length <= 256 ? 'u8' : 'u16';
  return [
    `pub const ${type} = enum(${backing}) {`,
    ...tags.map(t => `    ${identifier(t)},`),
    '',
    '    /// Matches `name` exactly against every alias field of this property in `PropertyValueAliases.txt`.',
    `    pub fn fromAlias(name: []const u8) ?${type} {`,
    `        return findAlias(${type}, &${aliasTable}, name);`,
    '    }',
    '};',
  ];
}

function aliasBlock(type, table, entries) {
  return [
    `pub const ${table} = [_]Alias(${type}){`,
    ...entries.map(([alias, short]) => `    .{ .name = ${zigString(alias)}, .value = .${identifier(short)} },`),
    '};',
  ];
}

const PRELUDE = [
  '/// One alias of a property value.',
  'pub fn Alias(comptime T: type) type {',
  '    return struct { name: []const u8, value: T };',
  '}',
  '',
  '/// A run of code points that starts at `start` and ends before the next range\'s start.',
  'pub fn Range(comptime T: type) type {',
  '    return struct { start: u21, value: T };',
  '}',
  '',
  '/// A run of code points with one Script_Extensions set. `set` indexes `script_extension_sets`, or is `script_value`',
  '/// when the Script_Extensions value is the code point\'s Script value.',
  'pub const ScriptExtensionRange = struct { start: u21, set: u16 };',
  'pub const script_value: u16 = 0xFFFF;',
  '',
  '/// Binary search over aliases sorted by their UTF-8 bytes.',
  'fn findAlias(comptime T: type, aliases: []const Alias(T), name: []const u8) ?T {',
  '    var low: usize = 0;',
  '    var high: usize = aliases.len;',
  '    while (low < high) {',
  '        const middle = low + (high - low) / 2;',
  '        switch (orderBytes(aliases[middle].name, name)) {',
  '            .lt => low = middle + 1,',
  '            .gt => high = middle,',
  '            .eq => return aliases[middle].value,',
  '        }',
  '    }',
  '    return null;',
  '}',
  '',
  'const Order = enum { lt, eq, gt };',
  '',
  'fn orderBytes(a: []const u8, b: []const u8) Order {',
  '    const n = @min(a.len, b.len);',
  '    for (a[0..n], b[0..n]) |x, y| {',
  '        if (x != y) return if (x < y) .lt else .gt;',
  '    }',
  '    if (a.len == b.len) return .eq;',
  '    return if (a.len < b.len) .lt else .gt;',
  '}',
];

/**
 * Generate `src/unicode/tables.zig` from the input bytes. `inputs` maps each path in UCD_FILES and UCD_LICENSE to its bytes.
 */
export function generate(inputs) {
  const text = file => {
    const bytes = inputs.get(file);
    if (!bytes) throw new UcdError(`Missing input ${file}.`);
    return bytes.toString('utf8');
  };
  const aliases = parseAliases(text(ALIASES_FILE), ALIASES_FILE);
  const lines = [
    `//! Generated by tools/ucd.mjs from Unicode ${UCD_VERSION}. Do not edit.`,
    '//!',
    '//! Inputs, each with its byte size and SHA-256:',
    ...[...UCD_FILES, UCD_LICENSE].map(file => `//! ${file}: ${inputs.get(file).length} bytes, SHA-256 ${sha256(inputs.get(file))}`),
    '//!',
    `//! The notice below is ${UCD_LICENSE}, which governs the input files and these tables.`,
    '',
    ...text(UCD_LICENSE).replace(/\r\n/g, '\n').replace(/\n+$/, '').split('\n').map(l => (l.trimEnd() ? `// ${l.trimEnd()}` : '//')),
    '',
    `pub const version = ${zigString(UCD_VERSION)};`,
    '',
    ...PRELUDE,
  ];
  const parsed = new Map();
  for (const p of PROPERTIES) {
    const values = aliases.get(p.property);
    if (!values) throw new UcdError(`${ALIASES_FILE} has no values for ${p.property}.`);
    const result = p.field
      ? parseFieldProperty(text(p.file), { file: p.file, aliases: values, property: p.property })
      : parseProperty(text(p.file), { file: p.file, aliases: values });
    const occurring = new Set(result.names);
    const tags = values.values.map(v => v.short).filter(short => !p.onlyOccurring || occurring.has(short));
    for (const name of result.names) if (!tags.includes(name)) throw new UcdError(`${p.file}: value ${name} is not a ${p.property} value.`);
    parsed.set(p.property, { ...result, tags });
    const aliasEntries = [];
    for (const v of values.values) if (tags.includes(v.short)) for (const alias of new Set(v.aliases)) aliasEntries.push([alias, v.short]);
    aliasEntries.sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
    const tableName = `${p.name}_aliases`;
    lines.push('', ...enumBlock(p.type, tags, tableName), '', ...aliasBlock(p.type, tableName, aliasEntries), '',
      `pub const ${p.name}_ranges = [_]Range(${p.type}){`,
      ...runs(result.dense).map(([start, v]) => `    .{ .start = ${hex(start)}, .value = .${identifier(result.names[v])} },`),
      '};');
  }

  const extFile = `${UCD_DIR}/ScriptExtensions.txt`;
  const scripts = parsed.get('sc');
  const order = new Map(scripts.tags.map((t, i) => [t, i]));
  const ext = parseExtensions(text(extFile), { file: extFile, aliases: aliases.get('sc') });
  const sets = ext.sets.map(set => [...set].sort((a, b) => order.get(a) - order.get(b)));
  lines.push('', '/// Each Script_Extensions set that `ScriptExtensions.txt` lists, in ascending `Script` order.',
    'pub const script_extension_sets = [_][]const Script{',
    ...sets.map(set => `    &.${set.length === 1 ? `{.${identifier(set[0])}}` : `{ ${set.map(s => `.${identifier(s)}`).join(', ')} }`},`),
    '};', '',
    'pub const script_extension_ranges = [_]ScriptExtensionRange{',
    ...runs(ext.dense).map(([start, v]) => `    .{ .start = ${hex(start)}, .set = ${v === UNSET ? 'script_value' : v} },`),
    '};');
  for (const p of BINARY_PROPERTIES) {
    const result = parseBinaryProperty(text(p.file), { file: p.file, property: p.property });
    lines.push('', `/// \`${p.property}\` from \`${p.file.slice(`${UCD_DIR}/`.length)}\`. A code point that the file does not list is false.`,
      `pub const ${p.name}_ranges = [_]Range(bool){`,
      ...runs(result.dense).map(([start, v]) => `    .{ .start = ${hex(start)}, .value = ${v === 1} },`),
      '};');
  }
  lines.push('');
  return lines.join('\n');
}

function readInputs(root) {
  const inputs = new Map();
  for (const file of [...UCD_FILES, UCD_LICENSE]) inputs.set(file, fs.readFileSync(safePath(root, file)));
  return inputs;
}

/** Write `src/unicode/tables.zig` from the imported UCD files. */
export function ucdGenerate(root) {
  const output = generate(readInputs(root));
  fs.writeFileSync(safePath(root, GENERATED_PATH, { mustExist: false }), output);
  return { result: 'written', version: UCD_VERSION, inputs: [...UCD_FILES, UCD_LICENSE], file: GENERATED_PATH, bytes: Buffer.byteLength(output) };
}

/** The first line, counted from one, at which two byte buffers differ. */
function firstDifferentLine(expected, actual) {
  const length = Math.min(expected.length, actual.length);
  let line = 1;
  for (let i = 0; i < length; i++) {
    if (expected[i] !== actual[i]) return line;
    if (expected[i] === 0x0a) line++;
  }
  return line;
}

/** Regenerate in memory and compare with the committed table byte for byte. */
export function ucdCheck(root) {
  const expected = Buffer.from(generate(readInputs(root)), 'utf8'), file = path.join(root, GENERATED_PATH);
  if (!fs.existsSync(file)) return { result: 'stale', differences: [{ file: GENERATED_PATH, line: null, problem: 'missing' }] };
  const actual = fs.readFileSync(file);
  return actual.equals(expected)
    ? { result: 'pass', version: UCD_VERSION, file: GENERATED_PATH }
    : { result: 'stale', differences: [{ file: GENERATED_PATH, line: firstDifferentLine(expected, actual), problem: 'differs from the generator output' }],
      instruction: 'Run node tools/fairpane.mjs ucd-generate and review the change.' };
}
