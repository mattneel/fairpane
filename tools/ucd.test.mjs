#!/usr/bin/env node
/**
 * Unicode property generator tests for FP-0013 cases 1 through 4 and FP-0108 cases 1 through 4.
 * Run standalone with `node tools/ucd.test.mjs`, or through `node tools/fairpane.mjs test`.
 * The Zig part of FP-0013 case 3 and FP-0108 case 7, the exhaustive comparisons of `lookup` with an independent parser, run in `zig build test`.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { GENERATED_PATH, UCD_FILES, UCD_LICENSE, UcdError, parseAliases, parseProperty } from './ucd.mjs';
// FP-0108 generator functions are read through the namespace, so a missing export fails only the case that calls it.
import * as ucd from './ucd.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const temporary = [];

function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-ucd-'));
  temporary.push(dir); return dir;
}
function ucdCheckIn(dir) {
  return spawnSync(process.execPath, [path.join(dir, 'tools/fairpane.mjs'), 'ucd-check'], { cwd: dir, encoding: 'utf8', windowsHide: true });
}
/** Copy the controller, the UCD inputs, and the generated table into a fresh directory. */
function controllerCopy() {
  const dir = temp();
  const files = [...UCD_FILES, UCD_LICENSE, GENERATED_PATH,
    ...fs.readdirSync(path.join(root, 'tools')).filter(name => name.endsWith('.mjs')).map(name => `tools/${name}`)];
  for (const file of files) {
    fs.mkdirSync(path.join(dir, path.dirname(file)), { recursive: true });
    fs.copyFileSync(path.join(root, file), path.join(dir, file));
  }
  return dir;
}

const FIXTURE_ALIASES = [
  '# PropertyValueAliases fixture',
  'bc ; AL                               ; Arabic_Letter',
  'bc ; EN                               ; European_Number',
  'bc ; L                                ; Left_To_Right',
  'bc ; R                                ; Right_To_Left',
  '',
].join('\n');
const FIXTURE_DATA = [
  '# DerivedBidiClass fixture',
  '# @missing: 0000..10FFFF; Left_To_Right',
  '# @missing: 0590..05FF; Right_To_Left',
  '',
  '0041..005A    ; AL # a range line',
  '05D0          ; EN',
  '0600 ; Arabic_Letter # a trailing comment naming a long alias',
  '',
].join('\n');
const FIXTURE_INCB_ALIASES = [
  'InCB; Consonant ; Consonant',
  'InCB; Extend ; Extend',
  'InCB; Linker ; Linker',
  'InCB; None ; None',
  '',
].join('\n');
const FIXTURE_INCB = [
  '# @missing: 0000..10FFFF; InCB; None',
  '0041          ; Alphabetic # x',
  '0915..0939    ; InCB; Consonant # Lo',
  '094D          ; InCB; Linker',
  '0300..0301    ; InCB; Extend',
  '',
].join('\n');
const FIXTURE_EXTPICT = [
  '0041..0043    ; Extended_Pictographic# a',
  '0044          ; Emoji                # b',
  '00A9          ; Extended_Pictographic',
  '',
].join('\n');

function rejects(fn, pattern) {
  assert.throws(fn, e => {
    assert.ok(e instanceof UcdError, `Expected a UcdError, got ${e?.stack ?? e}`);
    assert.match(e.message, pattern);
    return true;
  });
  try { fn(); } catch (e) { return e.message; }
  return null;
}

export const ucdCases = [
  ['FP-0013 case 1: @missing lines apply in order, then data lines, and every value resolves through PropertyValueAliases.txt', () => {
    const aliases = parseAliases(FIXTURE_ALIASES, 'Fixture-aliases.txt').get('bc');
    const parsed = parseProperty(FIXTURE_DATA, { file: 'Fixture.txt', aliases });
    const probes = [[0x0000, 'L'], [0x10FFFF, 'L'], [0x0590, 'R'], [0x05FF, 'R'], [0x0041, 'AL'], [0x005A, 'AL'], [0x05D0, 'EN'], [0x0600, 'AL']];
    for (const [cp, value] of probes) assert.equal(parsed.valueAt(cp), value, `U+${cp.toString(16).toUpperCase()}`);
    assert.equal(parsed.valueAt(0x0040), 'L');
    assert.equal(parsed.valueAt(0x05D1), 'R');
  }],
  ['FP-0013 case 2: a line without ";", a reversed range, 110000, and an unknown value each fail with a distinct message naming the line', () => {
    const aliases = parseAliases(FIXTURE_ALIASES, 'Fixture-aliases.txt').get('bc');
    const parse = line => () => parseProperty(`# header\n\n${line}\n`, { file: 'Fixture.txt', aliases });
    const messages = [
      rejects(parse('0041 AL'), /Fixture\.txt line 3: the data line has no ";"/),
      rejects(parse('005A..0041 ; AL'), /Fixture\.txt line 3: the range starts after its end/),
      rejects(parse('110000 ; AL'), /Fixture\.txt line 3: code point 110000 is above 10FFFF/),
      rejects(parse('0041 ; Nope'), /Fixture\.txt line 3: unknown value "Nope"/),
    ];
    assert.equal(new Set(messages).size, messages.length);
    rejects(() => parseProperty('# @missing: 0000..10FFFF; Nope\n', { file: 'Fixture.txt', aliases }), /Fixture\.txt line 1: unknown value "Nope"/);
  }],
  ['FP-0013 case 3 (amended by FP-0108 case 1): ucd-check passes on the committed files, every input names version 18.0.0, and the Zig reference test embeds every input', () => {
    const r = spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'ucd-check'], { cwd: root, encoding: 'utf8', windowsHide: true });
    assert.equal(r.status, 0, r.stdout + r.stderr);
    assert.equal(JSON.parse(r.stdout).result, 'pass');
    assert.deepEqual(UCD_FILES, [
      'src/unicode/ucd/Scripts.txt',
      'src/unicode/ucd/ScriptExtensions.txt',
      'src/unicode/ucd/PropertyValueAliases.txt',
      'src/unicode/ucd/extracted/DerivedBidiClass.txt',
      'src/unicode/ucd/extracted/DerivedJoiningType.txt',
      'src/unicode/ucd/extracted/DerivedGeneralCategory.txt',
      'src/unicode/ucd/IndicSyllabicCategory.txt',
      'src/unicode/ucd/IndicPositionalCategory.txt',
      'src/unicode/ucd/auxiliary/GraphemeBreakProperty.txt',
      'src/unicode/ucd/DerivedCoreProperties.txt',
      'src/unicode/ucd/emoji/emoji-data.txt',
    ]);
    for (const file of UCD_FILES) {
      const lines = fs.readFileSync(path.join(root, file), 'utf8').split('\n');
      if (file === 'src/unicode/ucd/emoji/emoji-data.txt') {
        // emoji-data.txt names no version on line 1; its version is on line 8.
        assert.equal(lines[0], '# emoji-data.txt', file);
        assert.equal(lines[7], '# Version: 18.0.0', file);
      } else {
        assert.equal(lines[0], `# ${path.posix.basename(file, '.txt')}-18.0.0.txt`, file);
      }
    }
    const generated = fs.readFileSync(path.join(root, GENERATED_PATH), 'utf8');
    assert.match(generated, /^\/\/! Generated by tools\/ucd\.mjs from Unicode 18\.0\.0\. Do not edit\.\n/);
    const reference = fs.readFileSync(path.join(root, 'src/unicode/reference_test.zig'), 'utf8');
    assert.match(reference, /test "FP-0013 case 3: /);
    for (const file of UCD_FILES) assert.ok(reference.includes(`@embedFile("${file.slice('src/unicode/'.length)}")`), file);
    assert.ok(!reference.includes('fromAlias'), 'The reference test must not resolve values through the module under test.');
  }],
  ['FP-0013 case 4: one changed byte of tables.zig or of a UCD file makes ucd-check exit with status 1 and name the file and line', () => {
    const dir = controllerCopy();
    const clean = ucdCheckIn(dir);
    assert.equal(clean.status, 0, clean.stdout + clean.stderr);
    const table = path.join(dir, GENERATED_PATH), original = fs.readFileSync(table), lines = original.toString('utf8').split('\n');
    const line = lines.findIndex(text => /^\s+\.\{ \.start = 0x/.test(text)) + 1;
    assert.ok(line > 0);
    const changed = Buffer.from(lines.map((text, i) => i === line - 1 ? text.replace('.start = 0x', '.start = 0X') : text).join('\n'));
    assert.equal(changed.length, original.length);
    fs.writeFileSync(table, changed);
    const stale = ucdCheckIn(dir);
    assert.equal(stale.status, 1, stale.stdout + stale.stderr);
    assert.deepEqual(JSON.parse(stale.stdout).differences, [{ file: GENERATED_PATH, line, problem: 'differs from the generator output' }]);
    fs.writeFileSync(table, original);
    assert.equal(ucdCheckIn(dir).status, 0);

    // A changed comment byte in one input changes only that input's header digest line.
    const input = path.join(dir, 'src/unicode/ucd/Scripts.txt'), bytes = fs.readFileSync(input), at = bytes.indexOf('# Scripts-18.0.0.txt') + 2;
    bytes[at] = 0x73; // "S" becomes "s"
    fs.writeFileSync(input, bytes);
    const digest = ucdCheckIn(dir);
    assert.equal(digest.status, 1, digest.stdout + digest.stderr);
    const [difference] = JSON.parse(digest.stdout).differences;
    assert.equal(difference.file, GENERATED_PATH);
    assert.match(lines[difference.line - 1], /^\/\/! src\/unicode\/ucd\/Scripts\.txt: \d+ bytes, SHA-256 [0-9a-f]{64}$/);
  }],
  ['FP-0108 case 2: parseFieldProperty reads only the InCB lines of a multi-property file and applies the @missing default', () => {
    const aliases = parseAliases(FIXTURE_INCB_ALIASES, 'Fixture-aliases.txt').get('InCB');
    const parsed = ucd.parseFieldProperty(FIXTURE_INCB, { file: 'Fixture.txt', aliases, property: 'InCB' });
    const probes = [[0x0041, 'None'], [0x0914, 'None'], [0x0915, 'Consonant'], [0x0939, 'Consonant'], [0x093A, 'None'],
      [0x094D, 'Linker'], [0x0300, 'Extend'], [0x0301, 'Extend'], [0x10FFFF, 'None']];
    for (const [cp, value] of probes) assert.equal(parsed.valueAt(cp), value, `U+${cp.toString(16).toUpperCase()}`);
  }],
  ['FP-0108 case 3: parseBinaryProperty sets only the lines whose single field is the property, and every other code point is false', () => {
    const parsed = ucd.parseBinaryProperty(FIXTURE_EXTPICT, { file: 'Fixture.txt', property: 'Extended_Pictographic' });
    const probes = [[0x0040, false], [0x0041, true], [0x0043, true], [0x0044, false], [0x00A9, true], [0x10FFFF, false]];
    for (const [cp, value] of probes) assert.equal(parsed.valueAt(cp), value, `U+${cp.toString(16).toUpperCase()}`);
  }],
  ['FP-0108 case 4: a missing InCB value, an unknown value, an extra value, and a binary line with a value each fail with a distinct message naming the line', () => {
    const aliases = parseAliases(FIXTURE_INCB_ALIASES, 'Fixture-aliases.txt').get('InCB');
    // The unchanged fixture parses, so each failure below comes from its one changed line.
    assert.equal(ucd.parseFieldProperty(FIXTURE_INCB, { file: 'Fixture.txt', aliases, property: 'InCB' }).valueAt(0x094D), 'Linker');
    const field = line => () => ucd.parseFieldProperty(`# header\n\n${line}\n`, { file: 'Fixture.txt', aliases, property: 'InCB' });
    const binary = line => () => ucd.parseBinaryProperty(`# header\n\n${line}\n`, { file: 'Fixture.txt', property: 'Extended_Pictographic' });
    const messages = [
      rejects(field('0915 ; InCB'), /^Fixture\.txt line 3: /),
      rejects(field('0915 ; InCB; Nope'), /^Fixture\.txt line 3: unknown value "Nope"/),
      rejects(field('0915 ; InCB; Linker; Extra'), /^Fixture\.txt line 3: /),
      rejects(binary('0041 ; Extended_Pictographic; Y'), /^Fixture\.txt line 3: /),
    ];
    assert.equal(new Set(messages).size, messages.length, JSON.stringify(messages));
    rejects(() => ucd.parseFieldProperty('# @missing: 0000..10FFFF; InCB\n', { file: 'Fixture.txt', aliases, property: 'InCB' }), /^Fixture\.txt line 1: /);
  }],
].map(([name, fn]) => ({ name, fn }));

export function removeUcdFixtures() {
  const failures = [];
  for (const dir of temporary.splice(0).reverse()) {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { failures.push(`${dir}: ${e.message}`); }
  }
  return failures;
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  console.log('TAP version 13');
  let failures = 0;
  for (const [i, c] of ucdCases.entries()) {
    try { await c.fn(); console.log(`ok ${i + 1} - ${c.name}`); }
    catch (e) { failures++; console.log(`not ok ${i + 1} - ${c.name}\n  ---\n  message: ${JSON.stringify(e.message)}\n  ...`); }
  }
  for (const problem of removeUcdFixtures()) { failures++; console.error(`Temporary fixture cleanup failed: ${problem}`); }
  console.log(`1..${ucdCases.length}\n# tests ${ucdCases.length}\n# pass ${ucdCases.length - failures}\n# fail ${failures}`);
  process.exitCode = failures ? 1 : 0;
}
