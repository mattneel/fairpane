#!/usr/bin/env node
/**
 * ABI schema, generator, and failure-scenario tests for FP-0021.
 * Run standalone with `node tools/abi.test.mjs`, or through `node tools/fairpane.mjs test`.
 * Cases 6, 7, 8, 12, and 13 also run in Zig and C through the `zig-test` and `c-abi` gates.
 * Their controller parts check that those sources cover the schema and every scenario.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {
  AbiError, GENERATED_FILES, SCENARIOS_PATH, SCHEMA_PATH, generate, scenarioMarkers, structureLayout,
  validateScenarios, validateSchema, zigTypeName,
} from './abi.mjs';
import * as abi from './abi.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const readText = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const schema = () => JSON.parse(readText(SCHEMA_PATH));
const scenarios = () => JSON.parse(readText(SCENARIOS_PATH));
const named = (list, name) => list.find(item => item.name === name);
const u32 = { kind: 'integer', bits: 32, signed: false, range: [0, 4294967295] };
const temporary = [];

function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-abi-'));
  temporary.push(dir); return dir;
}
function rejects(fn, pattern) {
  assert.throws(fn, e => {
    assert.ok(e instanceof AbiError, `Expected an AbiError, got ${e?.stack ?? e}`);
    assert.match(e.message, pattern);
    return true;
  });
}
/** Rebuild every object with its keys in reverse order. Arrays keep their order. */
function reverseKeys(value) {
  if (Array.isArray(value)) return value.map(reverseKeys);
  if (value === null || typeof value !== 'object') return value;
  return Object.fromEntries(Object.keys(value).reverse().map(key => [key, reverseKeys(value[key])]));
}
/** Copy the controller, the schema, the scenarios, and the generated files into a fresh directory. */
function controllerCopy() {
  const dir = temp();
  const files = [SCHEMA_PATH, SCENARIOS_PATH, ...GENERATED_FILES,
    ...fs.readdirSync(path.join(root, 'tools')).filter(name => name.endsWith('.mjs')).map(name => `tools/${name}`)];
  for (const file of files) {
    fs.mkdirSync(path.join(dir, path.dirname(file)), { recursive: true });
    fs.copyFileSync(path.join(root, file), path.join(dir, file));
  }
  return dir;
}
function abiCheckIn(dir) {
  return spawnSync(process.execPath, [path.join(dir, 'tools/fairpane.mjs'), 'abi-check'], { cwd: dir, encoding: 'utf8', windowsHide: true });
}
/** Map each field of a generated C structure to the type part of its declaration. */
function cFields(header, name) {
  const block = header.split(`typedef struct ${name} {\n`)[1]?.split(`\n} ${name};`)[0];
  assert.ok(block, `The header declares no structure ${name}.`);
  return new Map(block.split('\n').filter(line => !/^\s*(\/\*|\*)/.test(line)).map(line => {
    const m = /^ {4}(.+?) ?(\w+);$/.exec(line);
    assert.ok(m, `Unexpected structure line: ${line}`);
    return [m[2], m[1]];
  }));
}
/** Map each field of a generated Zig extern structure to its type. */
function zigFields(source, name) {
  const block = source.split(`pub const ${name} = extern struct {\n`)[1]?.split('\n};')[0];
  assert.ok(block, `The Zig file declares no structure ${name}.`);
  return new Map(block.split('\n').filter(line => !/^\s*\/\/\//.test(line)).map(line => {
    const m = /^ {4}(\w+): (.+),$/.exec(line);
    assert.ok(m, `Unexpected structure line: ${line}`);
    return [m[1], m[2]];
  }));
}
/** The C comment block that documents the generated declaration of the function `symbol`. */
function cComment(header, symbol) {
  const at = header.indexOf(` ${symbol}(`);
  assert.ok(at >= 0, `The header declares no function ${symbol}.`);
  const before = header.slice(0, at);
  return before.slice(before.lastIndexOf('/*'), before.lastIndexOf('*/') + 2);
}
/** The doc comment lines that document the generated Zig function type `symbol`, without their comment markers. */
function zigComment(source, symbol) {
  const lines = source.split('\n');
  const at = lines.findIndex(line => line.startsWith(`    pub const ${symbol} = fn `));
  assert.ok(at >= 0, `The Zig file declares no function type ${symbol}.`);
  let start = at;
  while (start > 0 && lines[start - 1].startsWith('    ///')) start--;
  return lines.slice(start, at).map(line => line.slice('    /// '.length)).join('\n');
}
/** The text from `opening` to the first closing brace at the start of a line. */
function blockOf(source, opening) {
  const start = source.indexOf(opening);
  assert.ok(start >= 0, `No block starts with ${opening}`);
  return source.slice(start, source.indexOf('\n}', start));
}
/** The number of calls to `symbol` in `source`. */
const callCount = (source, symbol) => source.split(new RegExp(`\\b${symbol}\\(`)).length - 1;
/** A minimal static library whose archive symbol table lists `symbols` in the GNU or the BSD layout. */
function archive(symbols, layout) {
  const header = (name, size) => Buffer.from(`${name.padEnd(16)}${'0'.padEnd(12)}${'0'.padEnd(6)}${'0'.padEnd(6)}${'644'.padEnd(8)}${String(size).padEnd(10)}\`\n`, 'latin1');
  const even = bytes => bytes.length % 2 ? Buffer.concat([bytes, Buffer.from('\n')]) : bytes;
  const names = Buffer.from(symbols.map(symbol => `${symbol}\0`).join(''), 'latin1');
  let name, table;
  if (layout === 'gnu') {
    // A big-endian count and one member offset per symbol, then the names. The offsets stay zero because no reader follows them here.
    const counts = Buffer.alloc(4 + 4 * symbols.length);
    counts.writeUInt32BE(symbols.length, 0);
    name = '/';
    table = Buffer.concat([counts, names]);
  } else {
    // A BSD extended name, the little-endian ranlib entries with string offsets, then the string table.
    const label = Buffer.from('__.SYMDEF SORTED\0\0\0\0', 'latin1');
    const ranlib = Buffer.alloc(4 + 8 * symbols.length + 4);
    ranlib.writeUInt32LE(8 * symbols.length, 0);
    let offset = 0;
    for (const [i, symbol] of symbols.entries()) { ranlib.writeUInt32LE(offset, 4 + 8 * i); offset += symbol.length + 1; }
    ranlib.writeUInt32LE(names.length, 4 + 8 * symbols.length);
    name = `#1/${label.length}`;
    table = Buffer.concat([label, ranlib, names]);
  }
  const object = Buffer.from('not an object file\n');
  return Buffer.concat([Buffer.from('!<arch>\n', 'latin1'), header(name, table.length), even(table), header('a.o/', object.length), even(object)]);
}

export const abiCases = [
  ['FP-0021 case 1: Generating from the committed schema reproduces the committed include/fairpane.h and src/abi_generated.zig byte for byte', () => {
    const generated = generate(schema());
    assert.deepEqual(Object.keys(generated), GENERATED_FILES);
    for (const file of GENERATED_FILES) {
      assert.ok(Buffer.from(generated[file], 'utf8').equals(fs.readFileSync(path.join(root, file))), `${file} differs from the generator output.`);
    }
    assert.match(generated['include/fairpane.h'], /^\/\* Generated by tools\/abi\.mjs from api\/fairpane\.schema\.json\. Do not edit\./);
    assert.match(generated['src/abi_generated.zig'], /^\/\/! Generated by tools\/abi\.mjs from api\/fairpane\.schema\.json\. Do not edit\./);
    assert.equal(fs.existsSync(path.join(root, 'api/bootstrap.json')), false);
  }],
  ['FP-0021 case 2: Changing one byte of either generated file makes abi-check exit with status 1 and name the file', () => {
    const dir = controllerCopy();
    const clean = abiCheckIn(dir);
    assert.equal(clean.status, 0, clean.stdout + clean.stderr);
    for (const file of GENERATED_FILES) {
      const target = path.join(dir, file), original = fs.readFileSync(target), changed = Buffer.from(original);
      let at = Math.floor(changed.length / 2);
      while (!/[a-z]/.test(String.fromCharCode(changed[at]))) at++;
      changed[at] ^= 0x20;
      fs.writeFileSync(target, changed);
      const stale = abiCheckIn(dir);
      assert.equal(stale.status, 1, stale.stdout + stale.stderr);
      assert.ok(stale.stdout.includes(file), `abi-check did not name ${file}: ${stale.stdout}`);
      for (const other of GENERATED_FILES.filter(name => name !== file)) assert.ok(!stale.stdout.includes(other), `abi-check named the unchanged ${other}.`);
      fs.writeFileSync(target, original);
    }
    assert.equal(abiCheckIn(dir).status, 0);
  }],
  ['FP-0021 case 3: Generation is deterministic across two runs and across schema key order', () => {
    const first = generate(schema()), second = generate(schema()), reversed = generate(reverseKeys(schema()));
    for (const file of GENERATED_FILES) {
      assert.equal(second[file], first[file]);
      assert.equal(reversed[file], first[file]);
    }
    assert.notDeepEqual(Object.keys(reverseKeys(schema())), Object.keys(schema()));
  }],
  ['FP-0021 case 4: The validator rejects an unknown kind, a pointer without ownership or lifetime, an inverted range, a duplicate name, and a structure without struct_size', () => {
    validateSchema(schema());
    const unknownKind = schema();
    named(named(unknownKind.functions, 'engine_step').parameters, 'budget').type = { kind: 'pointer' };
    rejects(() => validateSchema(unknownKind), /engine_step\.budget.*unknown kind "pointer"/);
    const noOwnership = schema();
    delete named(named(noOwnership.functions, 'document_load').parameters, 'url').ownership;
    rejects(() => validateSchema(noOwnership), /document_load\.url.*ownership/);
    const noLifetime = schema();
    delete named(named(noLifetime.structures, 'document_info').fields, 'body').lifetime;
    rejects(() => validateSchema(noLifetime), /document_info\.body.*lifetime/);
    const inverted = schema();
    named(named(inverted.functions, 'engine_step').parameters, 'budget').type.range = [10, 1];
    rejects(() => validateSchema(inverted), /engine_step\.budget.*inverted range/);
    const duplicate = schema();
    duplicate.structures.push(structuredClone(named(duplicate.structures, 'event')));
    rejects(() => validateSchema(duplicate), /duplicate name "event"/);
    const duplicateC = schema();
    duplicateC.constants.push({ ...structuredClone(duplicateC.constants[0]), name: 'status_ok' });
    rejects(() => validateSchema(duplicateC), /duplicate name "FP_STATUS_OK"/);
    const unsized = schema();
    named(unsized.structures, 'response').fields.shift();
    rejects(() => validateSchema(unsized), /response.*struct_size/);
  }],
  ['FP-0021 case 5: The schema distinguishes text, web_string, bytes, identifier, handle, ranged integer, and optional values, and the generator maps each one to distinct C and Zig declarations', () => {
    const fixture = schema();
    const pointer = { direction: 'out', nullability: 'nullable', ownership: 'owned_by_engine', lifetime: 'engine_destroy' };
    fixture.structures.push({ name: 'kind_fixture', description: 'A fixture with one value of each kind.', fields: [
      { name: 'struct_size', type: u32 },
      { name: 'count', type: { kind: 'integer', bits: 32, signed: true, range: [-5, 5] } },
      { name: 'document', type: { kind: 'identifier', family: 'document' } },
      { name: 'engine', type: { kind: 'handle', handle: 'engine' }, ...pointer },
      { name: 'payload', type: { kind: 'bytes' }, ...pointer },
      { name: 'label', type: { kind: 'text' }, ...pointer },
      { name: 'title', type: { kind: 'web_string' }, ...pointer },
      { name: 'request', type: { kind: 'optional', absent: 'zero', value: { kind: 'identifier', family: 'request' } } },
    ] });
    validateSchema(fixture);
    const generated = generate(fixture);
    const c = cFields(generated['include/fairpane.h'], 'fp_kind_fixture');
    const zig = zigFields(generated['src/abi_generated.zig'], 'KindFixture');
    const expected = {
      count: ['int32_t', 'i32'], document: ['fp_document_id', 'DocumentId'], engine: ['fp_engine *', '?*Engine'],
      payload: ['const uint8_t *', '?[*]const u8'], label: ['const char *', '?[*]const c_char'],
      title: ['const uint16_t *', '?[*]const u16'], request: ['FP_OPTIONAL(fp_request_id)', 'Optional(RequestId)'],
    };
    for (const [field, [cType, zigType]] of Object.entries(expected)) {
      assert.equal(c.get(field), cType, `C field ${field}`);
      assert.equal(zig.get(field), zigType, `Zig field ${field}`);
    }
    for (const field of ['payload', 'label', 'title']) {
      assert.equal(c.get(`${field}_len`), 'size_t');
      assert.equal(zig.get(`${field}_len`), 'usize');
    }
    assert.equal(new Set(Object.keys(expected).map(field => c.get(field))).size, 7);
    assert.equal(new Set(Object.keys(expected).map(field => zig.get(field))).size, 7);
    const optionalZero = structuredClone(fixture);
    named(optionalZero.structures, 'kind_fixture').fields.at(-1).type.value = { kind: 'integer', bits: 32, signed: false, range: [0, 7] };
    rejects(() => validateSchema(optionalZero), /kind_fixture\.request.*zero/);
  }],
  ['FP-0021 case 6: The generated Zig declarations assert the size and every field offset of every structure', () => {
    const s = schema(), source = generate(s)['src/abi_generated.zig'];
    const expression = (wide, narrow) => wide === narrow ? `${wide}` : `layout(${wide}, ${narrow})`;
    for (const structure of s.structures) {
      const wide = structureLayout(s, structure.name, 8), narrow = structureLayout(s, structure.name, 4);
      const zig = zigTypeName(structure.name);
      assert.ok(source.includes(`if (@sizeOf(${zig}) != ${expression(wide.size, narrow.size)}) @compileError(`), `${zig} size`);
      assert.equal(wide.offsets.length, narrow.offsets.length);
      for (const [i, { name, offset }] of wide.offsets.entries()) {
        assert.ok(source.includes(`if (@offsetOf(${zig}, "${name}") != ${expression(offset, narrow.offsets[i].offset)}) @compileError(`), `${zig}.${name} offset`);
      }
    }
    // The C smoke test asserts these layouts against the generated header with static assertions.
    const at = (name, field) => structureLayout(s, name, 8).offsets.find(o => o.name === field).offset;
    assert.deepEqual(['capabilities', 'engine_options', 'step_outcome'].map(name => structureLayout(s, name, 8).size), [16, 16, 32]);
    assert.deepEqual([at('response', 'body'), at('document_info', 'body'), at('event', 'reject_reason'), at('event', 'url')], [16, 8, 36, 40]);
  }],
  ['FP-0021 case 7: The C smoke test runs every C-expressible failure scenario and names each identifier it covers', () => {
    const source = readText('tests/c/abi_smoke.c');
    assert.match(source, /^#include "fairpane\.h"$/m);
    const expected = scenarios().scenarios.filter(item => item.expressible_in_c).map(item => item.id);
    assert.ok(expected.length > 0);
    assert.deepEqual([...scenarioMarkers(source)].sort(), [...expected].sort());
    const main = source.split('int main(void) {')[1];
    assert.ok(main, 'The C smoke test has no main function.');
    for (const id of expected) assert.ok(main.includes(`    scenario_${id.replaceAll('-', '_')}();\n`), `main does not run ${id}.`);
  }],
  ['FP-0021 case 8: The Zig scenario test runs every failure scenario through the generated declarations', () => {
    const source = readText('src/abi_scenarios.zig');
    assert.match(source, /@import\("abi_generated\.zig"\)/);
    const expected = scenarios().scenarios.map(item => item.id);
    assert.deepEqual([...scenarioMarkers(source)].sort(), [...expected].sort());
    for (const id of expected) assert.match(source, new RegExp(`^test "Scenario ${id}: `, 'm'));
    assert.match(readText('src/root.zig'), /_ = @import\("abi_scenarios\.zig"\);/);
  }],
  ['FP-0021 case 9: Every failure scenario has an identifier, calls, and expected outcomes, and the validator rejects one without them', () => {
    const s = schema(), committed = scenarios();
    validateScenarios(committed, s);
    for (const item of committed.scenarios) {
      assert.match(item.id, /^[a-z0-9]+(?:-[a-z0-9]+)*$/);
      assert.ok(item.calls.length > 0 && item.effects.length > 0, item.id);
      for (const call of item.calls) assert.ok(call.function && call.status, item.id);
    }
    const mutate = change => { const copy = structuredClone(committed); change(copy.scenarios[0], copy); return copy; };
    rejects(() => validateScenarios(mutate(item => { delete item.id; }), s), /identifier/);
    rejects(() => validateScenarios(mutate(item => { item.calls = []; }), s), /calls/);
    rejects(() => validateScenarios(mutate(item => { delete item.calls; }), s), /calls/);
    rejects(() => validateScenarios(mutate(item => { delete item.effects; }), s), /effects/);
    rejects(() => validateScenarios(mutate(item => { delete item.calls[0].status; }), s), /status/);
    rejects(() => validateScenarios(mutate(item => { item.calls[0].function = 'fp_unknown'; }), s), /unknown function "fp_unknown"/);
    rejects(() => validateScenarios(mutate(item => { item.calls.push({ function: 'fp_abi_revision', arguments: 'none', status: 'ok' }); }), s), /fp_abi_revision.*status "ok"/);
    rejects(() => validateScenarios(mutate((item, copy) => { copy.scenarios.push(structuredClone(item)); }), s), /duplicate scenario/);
    rejects(() => validateScenarios(mutate((_, copy) => { copy.scenarios = copy.scenarios.filter(item => item.situation !== 'foreign_unwind'); }), s), /foreign_unwind/);
  }],
  ['FP-0021 case 10: The validator rejects consumed_on_success on an output parameter, and the generated C and Zig text states the consumption rule for fp_engine_destroy', () => {
    const s = schema();
    assert.equal(named(named(s.functions, 'engine_destroy').parameters, 'engine').ownership, 'consumed_on_success');
    validateSchema(s);
    const output = schema();
    named(named(output.functions, 'engine_create').parameters, 'out_engine').ownership = 'consumed_on_success';
    rejects(() => validateSchema(output), /engine_create\.out_engine.*consumed_on_success/);
    const received = schema();
    named(named(received.functions, 'engine_create').parameters, 'out_engine').receives.ownership = 'consumed_on_success';
    rejects(() => validateSchema(received), /engine_create\.out_engine\.receives.*consumed_on_success/);
    const structure = schema();
    named(named(structure.functions, 'engine_create').parameters, 'options').ownership = 'consumed_on_success';
    rejects(() => validateSchema(structure), /engine_create\.options.*consumed_on_success/);
    const field = schema();
    named(named(field.structures, 'document_info').fields, 'body').ownership = 'consumed_on_success';
    rejects(() => validateSchema(field), /document_info\.body.*consumed_on_success/);

    // Each identifier family names the lifetime that ends its identifiers.
    assert.deepEqual(s.identifiers.map(family => [family.name, family.lifetime]), [['document', 'document_destroy'], ['request', 'request_end']]);
    assert.deepEqual(named(s.lifetimes, 'document_destroy').ended_by, ['document_destroy', 'engine_destroy']);
    const noLifetime = schema();
    delete noLifetime.identifiers[0].lifetime;
    rejects(() => validateSchema(noLifetime), /identifiers\.document.*lifetime/);
    const unknownLifetime = schema();
    unknownLifetime.identifiers[1].lifetime = 'forever';
    rejects(() => validateSchema(unknownLifetime), /identifiers\.request.*lifetime/);

    const generated = generate(s), header = generated['include/fairpane.h'], zig = generated['src/abi_generated.zig'];
    assert.match(cComment(header, 'fp_engine_destroy'), /\n \* engine: input, non-null, consumed on success\. A call that returns FP_STATUS_OK ends the handle, and a call that returns any other status leaves the handle with the caller\./);
    assert.match(zigComment(zig, 'fp_engine_destroy'), /^engine: input, non-null, consumed on success\. A call that returns `Status\.ok` ends the handle, and a call that returns any other status leaves the handle with the caller\./m);
    assert.match(cComment(header, 'fp_document_create'), /\n \* engine: input, non-null, borrowed\. Ends when the call returns\./);
    assert.ok(header.includes(' * Ends when fp_document_destroy destroys the document or fp_engine_destroy destroys its engine.\n */\ntypedef uint64_t fp_document_id;'));
    assert.ok(zig.includes('/// Ends when `functions.fp_document_destroy` destroys the document or `functions.fp_engine_destroy` destroys its engine.\npub const DocumentId = enum(u64) { _ };'));
  }],
  ['FP-0021 case 11: The validator rejects an unknown reference and an unreferenced function name, and the generated header contains no schema-only name outside a C name', () => {
    const unknown = schema();
    named(unknown.structures, 'document_info').description = 'Output of {function:document_fetch}.';
    rejects(() => validateSchema(unknown), /document_info.*unknown reference "\{function:document_fetch\}"/);
    const unknownKind = schema();
    named(unknownKind.structures, 'document_info').description = 'Output of {routine:document_get}.';
    rejects(() => validateSchema(unknownKind), /document_info.*unknown reference "\{routine:document_get\}"/);
    const bare = schema();
    named(bare.structures, 'document_info').description = 'Output of document_get.';
    rejects(() => validateSchema(bare), /document_info.*names "document_get" without a reference/);
    const bareConstant = schema();
    named(named(bareConstant.structures, 'step_outcome').fields, 'next_deadline').description = 'Always the deadline_none constant.';
    rejects(() => validateSchema(bareConstant), /step_outcome\.next_deadline.*names "deadline_none" without a reference/);
    const bareStatus = schema();
    named(bareStatus.threads, 'owner').description = 'A call from another thread returns wrong_thread.';
    rejects(() => validateSchema(bareStatus), /threads\.owner.*names "wrong_thread" without a reference/);
    const bareEvent = schema();
    named(named(bareEvent.structures, 'event').fields, 'url').description = 'The URL of a request_issued event.';
    rejects(() => validateSchema(bareEvent), /event\.url.*names "request_issued" without a reference/);

    const s = schema(), generated = generate(s), header = generated['include/fairpane.h'], zig = generated['src/abi_generated.zig'];
    // Structure members and parameters keep their schema names in C, so only other multiword schema names are schema-only.
    const members = new Set([
      ...s.structures.flatMap(st => st.fields.flatMap(f => [f.name, `${f.name}_len`])),
      ...s.functions.flatMap(fn => fn.parameters.flatMap(p => [p.name, `${p.name}_len`, `${p.name}_size`])),
    ]);
    const schemaOnly = new Set([
      ...['functions', 'constants', 'enumerations', 'structures', 'handles', 'identifiers', 'lifetimes', 'threads'].flatMap(key => s[key].map(item => item.name)),
      ...s.statuses.members.map(m => m.name), ...s.enumerations.flatMap(e => e.members.map(m => m.name)), ...s.events.map(e => e.kind),
    ].filter(name => name.includes('_') && !members.has(name)));
    assert.ok(schemaOnly.has('document_get') && schemaOnly.has('deadline_none') && schemaOnly.has('request_issued'));
    assert.deepEqual([...new Set(header.match(/[A-Za-z0-9_]+/g).filter(word => schemaOnly.has(word)))], []);
    for (const text of ['Output of fp_document_get.', 'Always FP_DEADLINE_NONE.', 'Queues a rejection with a FP_REJECT_* value.',
      'struct_size must be at least sizeof(fp_engine_options).', 'For a FP_EVENT_REQUEST_ISSUED event', 'the kind is FP_EVENT_NONE.',
      'Every function except fp_abi_revision returns one.', 'returns FP_STATUS_WRONG_THREAD.']) {
      assert.ok(header.includes(text), `The header lacks "${text}".`);
    }
    for (const text of ['Output of `functions.fp_document_get`.', 'Always `deadline_none`.', 'Queues a rejection with a `RejectReason` value.',
      'struct_size must be at least `@sizeOf(EngineOptions)`.', 'For a `EventKind.request_issued` event', 'the kind is `EventKind.none`.',
      'returns `Status.wrong_thread`.']) {
      assert.ok(zig.includes(text), `The Zig file lacks "${text}".`);
    }
  }],
  ['FP-0021 case 12: The generated C static assertions check the size and every member offset of every structure, and the C smoke test compiles them', () => {
    assert.ok(GENERATED_FILES.includes('tests/c/abi_layout.h'));
    const s = schema(), source = generate(s)['tests/c/abi_layout.h'];
    assert.ok(source, 'The generator emits no tests/c/abi_layout.h.');
    assert.match(source, /^\/\* Generated by tools\/abi\.mjs from api\/fairpane\.schema\.json\. Do not edit\./);
    const expression = (wide, narrow) => wide === narrow ? `${wide}` : `(sizeof(void *) == 8 ? ${wide} : ${narrow})`;
    for (const structure of s.structures) {
      const wide = structureLayout(s, structure.name, 8), narrow = structureLayout(s, structure.name, 4), c = `fp_${structure.name}`;
      assert.ok(source.includes(`_Static_assert(sizeof(${c}) == ${expression(wide.size, narrow.size)}, `), `${c} size`);
      for (const [i, { name, offset }] of wide.offsets.entries()) {
        assert.ok(source.includes(`_Static_assert(offsetof(${c}, ${name}) == ${expression(offset, narrow.offsets[i].offset)}, `), `${c}.${name} offset`);
      }
    }
    const smoke = readText('tests/c/abi_smoke.c');
    assert.match(smoke, /^#include "abi_layout\.h"$/m);
    // The generated assertions replace the hand-written subset.
    assert.doesNotMatch(smoke, /_Static_assert\(/);
  }],
  ['FP-0021 case 13: From a foreign thread, the C and Zig scenarios call each owner function with an invalid argument and expect wrong_thread', () => {
    const s = schema();
    const owner = s.functions.filter(fn => fn.thread === 'owner').map(fn => fn.name);
    // A function whose only parameter is the engine has no other argument that the call could make invalid.
    const withArguments = s.functions.filter(fn => fn.thread === 'owner' && fn.parameters.some(p => p.type.kind !== 'handle')).map(fn => fn.name);
    assert.deepEqual(owner.filter(name => !withArguments.includes(name)), ['engine_destroy']);
    const scenario = scenarios().scenarios.find(item => item.id === 'wrong-thread');
    for (const name of owner) {
      const calls = scenario.calls.filter(call => call.function === `fp_${name}` && call.status === 'wrong_thread');
      assert.ok(calls.length >= (withArguments.includes(name) ? 2 : 1), `The wrong-thread scenario lacks an invalid-argument call for fp_${name}.`);
    }
    const c = blockOf(readText('tests/c/abi_smoke.c'), 'static void run_foreign_calls(');
    const zig = blockOf(readText('src/abi_scenarios.zig'), 'const ForeignThread = struct {');
    for (const name of owner) {
      const expected = withArguments.includes(name) ? 2 : 1;
      assert.ok(callCount(c, `fp_${name}`) >= expected, `The C foreign thread calls fp_${name} fewer than ${expected} times.`);
      assert.ok(callCount(zig, `fp_${name}`) >= expected, `The Zig foreign thread calls fp_${name} fewer than ${expected} times.`);
    }
  }],
  ['FP-0021 revision 1 status sets: abi_generated.zig carries each function status set, and src/c_api.zig checks every export against it', () => {
    const s = schema(), sets = blockOf(generate(s)['src/abi_generated.zig'], 'pub const statuses = struct {');
    for (const fn of s.functions) {
      const list = fn.statuses.map(status => `.${status}`).join(', ');
      assert.ok(sets.includes(`\n    pub const fp_${fn.name}: []const Status = &.{${list ? ` ${list} ` : ''}};`), `fp_${fn.name} status set`);
    }
    const api = readText('src/c_api.zig');
    assert.match(api, /@field\(abi\.statuses, symbol\)/);
    for (const fn of s.functions.filter(fn => fn.returns === 'status')) assert.ok(api.includes(`finish("fp_${fn.name}", `), `fp_${fn.name} does not return through finish.`);
  }],
  ['FP-0021 revision 1 export check: abi-exports fails when a library exports an fp_ symbol that the schema does not declare', () => {
    const s = schema(), declared = s.functions.map(fn => `fp_${fn.name}`), others = ['memcpy', '__zig_probe_stack'];
    for (const [layout, mangle] of [['gnu', name => name], ['bsd', name => `_${name}`]]) {
      const symbols = [...declared, ...others].map(mangle);
      assert.deepEqual(abi.archiveSymbols(archive(symbols, layout)), symbols, layout);
      assert.deepEqual(abi.exportProblems(s, symbols), { unexpected: [], missing: [] }, layout);
      assert.deepEqual(abi.exportProblems(s, [...symbols, mangle('fp_extra')]), { unexpected: ['fp_extra'], missing: [] }, layout);
      assert.deepEqual(abi.exportProblems(s, symbols.filter(symbol => symbol !== mangle('fp_engine_step'))), { unexpected: [], missing: ['fp_engine_step'] }, layout);
    }
    rejects(() => abi.archiveSymbols(Buffer.from('not an archive')), /archive/);
    rejects(() => abi.archiveSymbols(archive([], 'gnu').subarray(0, 70)), /archive/);

    const dir = controllerCopy(), library = path.join(dir, 'out', 'libfairpane.a');
    fs.mkdirSync(path.dirname(library), { recursive: true });
    const exportsIn = () => spawnSync(process.execPath, [path.join(dir, 'tools/fairpane.mjs'), 'abi-exports', 'out/libfairpane.a'], { cwd: dir, encoding: 'utf8', windowsHide: true });
    fs.writeFileSync(library, archive([...declared, 'fp_extra'], 'gnu'));
    const extra = exportsIn();
    assert.equal(extra.status, 1, extra.stdout + extra.stderr);
    assert.match(extra.stdout, /"fp_extra"/);
    fs.writeFileSync(library, archive([...declared, ...others], 'gnu'));
    const exact = exportsIn();
    assert.equal(exact.status, 0, exact.stdout + exact.stderr);
  }],
].map(([name, fn]) => ({ name, fn }));

export function removeAbiFixtures() {
  const failures = [];
  for (const dir of temporary.splice(0).reverse()) {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { failures.push(`${dir}: ${e.message}`); }
  }
  return failures;
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  console.log('TAP version 13');
  let failures = 0;
  for (const [i, c] of abiCases.entries()) {
    try { await c.fn(); console.log(`ok ${i + 1} - ${c.name}`); }
    catch (e) { failures++; console.log(`not ok ${i + 1} - ${c.name}\n  ---\n  message: ${JSON.stringify(e.message)}\n  ...`); }
  }
  for (const problem of removeAbiFixtures()) { failures++; console.error(`Temporary fixture cleanup failed: ${problem}`); }
  console.log(`1..${abiCases.length}\n# tests ${abiCases.length}\n# pass ${abiCases.length - failures}\n# fail ${failures}`);
  process.exitCode = failures ? 1 : 0;
}
