/**
 * The public C ABI schema: validation, deterministic generation of the C header and the Zig declarations,
 * the staleness check, and validation of the shared failure scenarios.
 * The module uses only the Node standard library.
 *
 * Generation reads collections in array order and never iterates object keys,
 * so the same schema produces byte-identical files regardless of key order.
 */
import fs from 'node:fs';
import path from 'node:path';
import { readJson, safePath } from './lib.mjs';

export const SCHEMA_PATH = 'api/fairpane.schema.json';
export const SCENARIOS_PATH = 'api/failure-scenarios.json';
export const GENERATED_FILES = Object.freeze(['include/fairpane.h', 'src/abi_generated.zig']);

export class AbiError extends Error {
  constructor(message) { super(message); this.name = 'AbiError'; }
}
function check(condition, message) { if (!condition) throw new AbiError(message); }

const KINDS = new Set(['integer', 'enumeration', 'handle', 'identifier', 'bytes', 'text', 'web_string', 'structure', 'optional']);
/** Kinds whose values are pointers. */
const POINTER_KINDS = new Set(['handle', 'bytes', 'text', 'web_string']);
/** Pointer kinds that carry a length. */
const RANGE_KINDS = new Set(['bytes', 'text', 'web_string']);
const OWNERSHIPS = ['borrowed', 'owned_by_engine', 'transferred_to_caller'];
const NULLABILITIES = ['non_null', 'null_when_empty', 'nullable'];
const DIRECTIONS = ['in', 'out'];
const PRESENCES = ['always', 'optional'];
const INTEGER_BITS = [8, 16, 32, 64];
const NAME = /^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/;
const SCENARIO_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
/** The situations that the FP-0021 contract requires the failure scenarios to cover. */
export const SCENARIO_SITUATIONS = Object.freeze(['identifier', 'thread', 'cancellation', 'teardown', 'allocation_failure',
  'invalid_argument', 'bounds', 'foreign_unwind']);

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const pascal = name => name.split('_').map(part => part[0].toUpperCase() + part.slice(1)).join('');
/** The Zig type name of a schema structure, enumeration, or handle name. */
export const zigTypeName = pascal;

function onlyKeys(value, allowed, where) {
  for (const key of Object.keys(value)) check(allowed.includes(key), `${where}: unexpected key "${key}".`);
}
function text(value, where) {
  check(typeof value === 'string' && value.trim() === value && value.length > 0 && !/[\x00-\x1f]|\*\//.test(value),
    `${where}: a description must be one nonempty line without control characters or a comment terminator.`);
}
function name(value, where) {
  check(typeof value === 'string' && NAME.test(value), `${where}: "${value}" is not a lowercase snake_case name.`);
}
/** Check names for duplicates within one list. */
function uniqueNames(list, where) {
  check(Array.isArray(list), `${where} must be a list.`);
  const seen = new Set();
  for (const item of list) {
    check(isObject(item), `${where} holds a non-object entry.`);
    name(item.name, `${where}.${item.name}`);
    check(!seen.has(item.name), `${where}: duplicate name "${item.name}".`);
    seen.add(item.name);
  }
  return new Map(list.map(item => [item.name, item]));
}
function bigInteger(value, where) {
  check(Number.isSafeInteger(value) || (typeof value === 'string' && /^-?(?:0|[1-9][0-9]*)$/.test(value)),
    `${where}: an integer must be a safe JSON integer or a decimal string.`);
  return BigInt(value);
}
function integerLimits(type) {
  const bits = BigInt(type.bits);
  return type.signed ? [-(1n << (bits - 1n)), (1n << (bits - 1n)) - 1n] : [0n, (1n << bits) - 1n];
}

/** The schema context that validation builds and generation reads. */
function index(schema) {
  return {
    schema,
    prefix: schema.prefix,
    threads: new Map(schema.threads.map(t => [t.name, t])),
    lifetimes: new Map(schema.lifetimes.map(l => [l.name, l])),
    enumerations: new Map(schema.enumerations.map(e => [e.name, e])),
    handles: new Map(schema.handles.map(h => [h.name, h])),
    identifiers: new Map(schema.identifiers.map(i => [i.name, i])),
    structures: new Map(schema.structures.map(s => [s.name, s])),
    functions: new Map(schema.functions.map(f => [f.name, f])),
  };
}

function validateInteger(type, where) {
  onlyKeys(type, ['kind', 'bits', 'signed', 'range'], where);
  check(INTEGER_BITS.includes(type.bits), `${where}: an integer needs bits of 8, 16, 32, or 64.`);
  check(typeof type.signed === 'boolean', `${where}: an integer needs explicit signedness.`);
  check(Array.isArray(type.range) && type.range.length === 2, `${where}: an integer needs an explicit inclusive range.`);
  const [min, max] = type.range.map(bound => bigInteger(bound, where));
  const [low, high] = integerLimits(type);
  check(min >= low && max <= high, `${where}: the range [${type.range}] exceeds a ${type.signed ? 'signed' : 'unsigned'} ${type.bits}-bit integer.`);
  check(min <= max, `${where}: inverted range [${type.range}].`);
  return [min, max];
}

/** Validate a value type. Structures are parameters only, so `allowStructure` is false for fields and returns. */
function validateType(ctx, type, where, { allowStructure = false } = {}) {
  check(isObject(type), `${where}: a type must be an object.`);
  check(KINDS.has(type.kind), `${where}: unknown kind "${type.kind}".`);
  switch (type.kind) {
    case 'integer': validateInteger(type, where); break;
    case 'enumeration':
      onlyKeys(type, ['kind', 'enumeration'], where);
      check(ctx.enumerations.has(type.enumeration), `${where}: unknown enumeration "${type.enumeration}".`); break;
    case 'handle':
      onlyKeys(type, ['kind', 'handle'], where);
      check(ctx.handles.has(type.handle), `${where}: unknown handle "${type.handle}".`); break;
    case 'identifier':
      onlyKeys(type, ['kind', 'family'], where);
      check(ctx.identifiers.has(type.family), `${where}: unknown identifier family "${type.family}".`); break;
    case 'bytes': case 'text': case 'web_string': onlyKeys(type, ['kind'], where); break;
    case 'structure':
      onlyKeys(type, ['kind', 'structure'], where);
      check(allowStructure, `${where}: a structure is valid only as a parameter.`);
      check(ctx.structures.has(type.structure), `${where}: unknown structure "${type.structure}".`); break;
    case 'optional': {
      onlyKeys(type, ['kind', 'absent', 'value'], where);
      check(type.absent === 'zero', `${where}: an optional value needs the absence encoding "zero".`);
      validateType(ctx, type.value, `${where}.value`);
      const value = type.value;
      check(['integer', 'enumeration', 'identifier'].includes(value.kind), `${where}: an optional value must be an integer, an enumeration, or an identifier.`);
      let excludesZero = value.kind === 'identifier';
      if (value.kind === 'integer') { const [min, max] = validateInteger(value, `${where}.value`); excludesZero = min > 0n || max < 0n; }
      if (value.kind === 'enumeration') excludesZero = ctx.enumerations.get(value.enumeration).members.every(m => m.value !== 0);
      check(excludesZero, `${where}: an optional value whose absence is zero needs a value that is never zero.`);
      break;
    }
  }
}

/** Validate the pointer facts of a parameter, a field, or a received value. */
function validatePointer(ctx, holder, where, { kind }) {
  check(NULLABILITIES.includes(holder.nullability), `${where}: a pointer needs a nullability of ${NULLABILITIES.join(', ')}.`);
  check(holder.nullability !== 'null_when_empty' || RANGE_KINDS.has(kind), `${where}: only a byte, text, or web string range can be null when empty.`);
  check(OWNERSHIPS.includes(holder.ownership), `${where}: a pointer needs an ownership of ${OWNERSHIPS.join(', ')}.`);
  check(ctx.lifetimes.has(holder.lifetime), `${where}: a pointer needs a lifetime that the schema defines, not "${holder.lifetime}".`);
}

function validateEnumeration(enumeration, where) {
  text(enumeration.description, where);
  check(isObject(enumeration.underlying) && enumeration.underlying.kind === 'integer', `${where}: an enumeration needs an underlying integer kind.`);
  const [min, max] = validateInteger(enumeration.underlying, `${where}.underlying`);
  const members = uniqueNames(enumeration.members, `${where}.members`);
  check(members.size > 0, `${where}: an enumeration needs members.`);
  const values = new Set();
  for (const member of enumeration.members) {
    onlyKeys(member, ['name', 'value', 'description'], `${where}.${member.name}`);
    const value = bigInteger(member.value, `${where}.${member.name}`);
    check(value >= min && value <= max, `${where}.${member.name}: the value is outside the underlying range.`);
    check(!values.has(value), `${where}.${member.name}: duplicate value ${member.value}.`);
    values.add(value);
    text(member.description, `${where}.${member.name}`);
  }
}

/** Validate the ABI schema. Throws an AbiError that names the first problem. */
export function validateSchema(schema) {
  check(isObject(schema), 'The schema must be an object.');
  onlyKeys(schema, ['schema', 'schema_version', 'abi_revision', 'stability', 'prefix', 'implemented_browser_capabilities', 'description',
    'threads', 'lifetimes', 'statuses', 'enumerations', 'constants', 'handles', 'identifiers', 'structures', 'functions', 'events'], 'schema');
  check(schema.schema === 'fairpane-c-abi' && schema.schema_version === 1, 'The schema must be fairpane-c-abi version 1.');
  check(Number.isSafeInteger(schema.abi_revision) && schema.abi_revision >= 0 && schema.abi_revision <= 0xFFFFFFFF, 'The ABI revision must be a 32-bit unsigned integer.');
  check(schema.stability === 'experimental' || schema.stability === 'stable', 'The stability must be experimental or stable.');
  name(schema.prefix, 'prefix');
  check(Array.isArray(schema.implemented_browser_capabilities) && schema.implemented_browser_capabilities.every(c => typeof c === 'string'),
    'implemented_browser_capabilities must be a list of capability names.');
  text(schema.description, 'schema');

  for (const key of ['threads', 'lifetimes', 'enumerations', 'constants', 'handles', 'identifiers', 'structures', 'functions']) uniqueNames(schema[key], key);
  const ctx = index(schema);
  const prefix = schema.prefix, upper = prefix.toUpperCase();
  // Every generated C and Zig name must be unique, so that two schema names cannot collide after mapping.
  const cNames = new Set([`${upper}_API`, `${upper}_ABI_REVISION`, `${upper}_OPTIONAL`, 'FAIRPANE_H', 'FAIRPANE_SHARED', 'FAIRPANE_BUILD']);
  const zigNames = new Set(['std', 'abi_revision', 'Optional', 'layout', 'functions']);
  const claim = (set, generated) => { check(!set.has(generated), `duplicate name "${generated}".`); set.add(generated); };

  for (const t of schema.threads) { onlyKeys(t, ['name', 'description'], `threads.${t.name}`); text(t.description, `threads.${t.name}`); }
  for (const l of schema.lifetimes) {
    onlyKeys(l, ['name', 'description', 'ended_by'], `lifetimes.${l.name}`);
    text(l.description, `lifetimes.${l.name}`);
    check(Array.isArray(l.ended_by) && l.ended_by.every(f => ctx.functions.has(f)), `lifetimes.${l.name}: ended_by must name schema functions.`);
  }

  check(isObject(schema.statuses), 'statuses must be an object.');
  onlyKeys(schema.statuses, ['description', 'underlying', 'members'], 'statuses');
  validateEnumeration(schema.statuses, 'statuses');
  check(schema.statuses.members.some(m => m.name === 'ok'), 'statuses: the ok status is required.');
  for (const m of schema.statuses.members) claim(cNames, `${upper}_STATUS_${m.name.toUpperCase()}`);
  claim(zigNames, 'Status');

  for (const e of schema.enumerations) {
    const where = `enumerations.${e.name}`;
    onlyKeys(e, ['name', 'member_prefix', 'description', 'underlying', 'members'], where);
    name(e.member_prefix, `${where}.member_prefix`);
    validateEnumeration(e, where);
    for (const m of e.members) claim(cNames, `${upper}_${e.member_prefix.toUpperCase()}_${m.name.toUpperCase()}`);
    claim(zigNames, pascal(e.name));
  }
  for (const c of schema.constants) {
    const where = `constants.${c.name}`;
    onlyKeys(c, ['name', 'description', 'type', 'value'], where);
    text(c.description, where);
    check(isObject(c.type) && c.type.kind === 'integer', `${where}: a constant must be an integer.`);
    const [min, max] = validateInteger(c.type, where);
    const value = bigInteger(c.value, where);
    check(value >= min && value <= max, `${where}: the value is outside its range.`);
    claim(cNames, `${upper}_${c.name.toUpperCase()}`);
    claim(zigNames, c.name);
  }
  for (const h of schema.handles) {
    const where = `handles.${h.name}`;
    onlyKeys(h, ['name', 'description', 'thread'], where);
    text(h.description, where);
    check(ctx.threads.has(h.thread), `${where}: unknown thread rule "${h.thread}".`);
    claim(cNames, `${prefix}_${h.name}`);
    claim(zigNames, pascal(h.name));
  }
  for (const i of schema.identifiers) {
    const where = `identifiers.${i.name}`;
    onlyKeys(i, ['name', 'description'], where);
    text(i.description, where);
    claim(cNames, `${prefix}_${i.name}_id`);
    claim(zigNames, `${pascal(i.name)}Id`);
  }

  for (const s of schema.structures) {
    const where = s.name;
    onlyKeys(s, ['name', 'description', 'fields'], `structures.${where}`);
    text(s.description, where);
    uniqueNames(s.fields, `${where}.fields`);
    const first = s.fields[0];
    check(first?.name === 'struct_size' && first.type?.kind === 'integer' && first.type.bits === 32 && first.type.signed === false,
      `${where}: the first field must be struct_size, a 32-bit unsigned integer.`);
    const members = new Set();
    for (const f of s.fields) {
      const at = `${where}.${f.name}`;
      onlyKeys(f, ['name', 'description', 'type', 'direction', 'nullability', 'ownership', 'lifetime'], at);
      if (f.description !== undefined) text(f.description, at);
      validateType(ctx, f.type, at);
      if (POINTER_KINDS.has(f.type.kind)) {
        check(DIRECTIONS.includes(f.direction), `${at}: a pointer needs a direction of in or out.`);
        validatePointer(ctx, f, at, f.type);
      } else {
        for (const key of ['direction', 'nullability', 'ownership', 'lifetime']) check(f[key] === undefined, `${at}: only a pointer states ${key}.`);
      }
      for (const member of RANGE_KINDS.has(f.type.kind) ? [f.name, `${f.name}_len`] : [f.name]) {
        check(!members.has(member), `${at}: duplicate name "${member}".`);
        members.add(member);
      }
    }
    claim(cNames, `${prefix}_${s.name}`);
    claim(zigNames, pascal(s.name));
  }

  for (const fn of schema.functions) {
    const where = fn.name;
    onlyKeys(fn, ['name', 'description', 'thread', 'returns', 'statuses', 'parameters'], `functions.${where}`);
    text(fn.description, where);
    check(ctx.threads.has(fn.thread), `${where}: unknown thread rule "${fn.thread}".`);
    check(Array.isArray(fn.statuses), `${where}: a function must list every status it can return.`);
    if (fn.returns === 'status') {
      check(fn.statuses.includes('ok'), `${where}: a status function must list ok.`);
      check(new Set(fn.statuses).size === fn.statuses.length, `${where}: duplicate status.`);
      for (const status of fn.statuses) check(schema.statuses.members.some(m => m.name === status), `${where}: unknown status "${status}".`);
    } else {
      validateType(ctx, fn.returns, `${where}.returns`);
      check(fn.returns.kind === 'integer', `${where}: a function returns a status or an integer.`);
      check(fn.statuses.length === 0, `${where}: a function that returns no status lists no statuses.`);
    }
    uniqueNames(fn.parameters, `${where}.parameters`);
    const members = new Set();
    for (const p of fn.parameters) {
      const at = `${where}.${p.name}`;
      onlyKeys(p, ['name', 'description', 'type', 'direction', 'nullability', 'ownership', 'lifetime', 'receives'], at);
      if (p.description !== undefined) text(p.description, at);
      validateType(ctx, p.type, at, { allowStructure: true });
      check(DIRECTIONS.includes(p.direction), `${at}: a parameter needs a direction of in or out.`);
      const kind = p.type.kind;
      check(!(RANGE_KINDS.has(kind) && p.direction === 'out'), `${at}: an output byte, text, or web string range is not supported.`);
      if (p.direction === 'out' || POINTER_KINDS.has(kind) || kind === 'structure') validatePointer(ctx, p, at, p.direction === 'out' ? {} : p.type);
      else for (const key of ['nullability', 'ownership', 'lifetime']) check(p[key] === undefined, `${at}: only a pointer states ${key}.`);
      if (p.direction === 'out' && POINTER_KINDS.has(kind)) {
        check(isObject(p.receives), `${at}: an output pointer value needs the facts of the value it receives.`);
        onlyKeys(p.receives, ['nullability', 'ownership', 'lifetime'], `${at}.receives`);
        validatePointer(ctx, p.receives, `${at}.receives`, p.type);
      } else check(p.receives === undefined, `${at}: only an output pointer value states receives.`);
      if (kind === 'structure') {
        for (const field of ctx.structures.get(p.type.structure).fields) {
          check(field.direction === undefined || field.direction === p.direction, `${at}: field ${p.type.structure}.${field.name} has direction ${field.direction}.`);
        }
      }
      const length = RANGE_KINDS.has(kind) ? `${p.name}_len` : kind === 'structure' && p.direction === 'out' ? `${p.name}_size` : null;
      for (const member of length ? [p.name, length] : [p.name]) {
        check(!members.has(member), `${at}: duplicate name "${member}".`);
        members.add(member);
      }
    }
    claim(cNames, `${prefix}_${fn.name}`);
  }

  check(Array.isArray(schema.events), 'events must be a list.');
  const kinds = new Set(), eventEnumerations = new Set();
  for (const event of schema.events) {
    check(isObject(event), 'events holds a non-object entry.');
    const where = `events.${event.kind}`;
    onlyKeys(event, ['kind', 'structure', 'description', 'fields'], where);
    text(event.description, where);
    const structure = ctx.structures.get(event.structure);
    check(structure, `${where}: unknown structure "${event.structure}".`);
    const kindField = structure.fields.find(f => f.name === 'kind');
    check(kindField?.type.kind === 'enumeration', `${where}: an event structure needs an enumeration field named kind.`);
    const enumeration = ctx.enumerations.get(kindField.type.enumeration);
    const member = enumeration.members.find(m => m.name === event.kind);
    check(member && member.value !== 0, `${where}: the kind must be a nonzero ${enumeration.name} member.`);
    check(!kinds.has(event.kind), `${where}: duplicate event.`);
    kinds.add(event.kind);
    eventEnumerations.add(enumeration);
    check(Array.isArray(event.fields), `${where}: an event lists its fields.`);
    const seen = new Set();
    for (const field of event.fields) {
      check(isObject(field), `${where}: an event field must be an object.`);
      onlyKeys(field, ['name', 'presence'], `${where}.${field.name}`);
      check(structure.fields.some(f => f.name === field.name && f.name !== 'struct_size' && f.name !== 'kind'), `${where}: unknown field "${field.name}".`);
      check(PRESENCES.includes(field.presence), `${where}.${field.name}: presence must be always or optional.`);
      check(!seen.has(field.name), `${where}: duplicate field "${field.name}".`);
      seen.add(field.name);
    }
  }
  // Every nonzero kind of an event enumeration needs a description of the fields it carries.
  for (const enumeration of eventEnumerations) {
    for (const member of enumeration.members) check(member.value === 0 || kinds.has(member.name), `events: no event describes ${enumeration.name} member "${member.name}".`);
  }
  return true;
}

/** The size and alignment of one C member of a field type. */
function scalarLayout(ctx, type, pointerBytes) {
  switch (type.kind) {
    case 'integer': return type.bits / 8;
    case 'enumeration': return ctx.enumerations.get(type.enumeration).underlying.bits / 8;
    case 'identifier': return 8;
    case 'optional': return scalarLayout(ctx, type.value, pointerBytes);
    default: return pointerBytes;
  }
}
function layoutOf(ctx, structure, pointerBytes) {
  let offset = 0, align = 1;
  const offsets = [];
  for (const field of structure.fields) {
    const members = RANGE_KINDS.has(field.type.kind) ? [[field.name, pointerBytes], [`${field.name}_len`, pointerBytes]] : [[field.name, scalarLayout(ctx, field.type, pointerBytes)]];
    for (const [member, size] of members) {
      offset = Math.ceil(offset / size) * size;
      offsets.push({ name: member, offset });
      offset += size;
      align = Math.max(align, size);
    }
  }
  return { size: Math.ceil(offset / align) * align, align, offsets };
}
/**
 * The C layout that the schema implies for a structure on a target with `pointerBytes`-byte pointers.
 * Every member has its natural alignment, and a range field holds a pointer followed by a target-sized length.
 */
export function structureLayout(schema, structureName, pointerBytes) {
  validateSchema(schema);
  const ctx = index(schema);
  const structure = ctx.structures.get(structureName);
  check(structure, `Unknown structure "${structureName}".`);
  check(pointerBytes === 4 || pointerBytes === 8, 'The schema implies layouts for 4-byte and 8-byte pointers only.');
  return layoutOf(ctx, structure, pointerBytes);
}

function literal(value, type) {
  const big = BigInt(value);
  return big >= 1n << 32n ? `0x${big.toString(16).toUpperCase()}` : big.toString();
}
const cInteger = type => `${type.signed ? 'int' : 'uint'}${type.bits}_t`;
const cLiteral = (value, type) => `${type.signed ? 'INT' : 'UINT'}${type.bits}_C(${literal(value, type)})`;
const zigInteger = type => `${type.signed ? 'i' : 'u'}${type.bits}`;

function cType(ctx, type) {
  const p = ctx.prefix;
  switch (type.kind) {
    case 'integer': return cInteger(type);
    case 'enumeration': return cInteger(ctx.enumerations.get(type.enumeration).underlying);
    case 'identifier': return `${p}_${type.family}_id`;
    case 'optional': return `${p.toUpperCase()}_OPTIONAL(${cType(ctx, type.value)})`;
    case 'handle': return `${p}_${type.handle} *`;
    case 'bytes': return 'const uint8_t *';
    case 'text': return 'const char *';
    case 'web_string': return 'const uint16_t *';
    default: throw new AbiError(`No C mapping exists for kind ${type.kind}.`);
  }
}
function zigType(ctx, type) {
  switch (type.kind) {
    case 'integer': return zigInteger(type);
    case 'enumeration': return zigInteger(ctx.enumerations.get(type.enumeration).underlying);
    case 'identifier': return `${pascal(type.family)}Id`;
    // The optional wrapper accepts every raw value, so it can carry the enumeration type itself.
    case 'optional': return `Optional(${type.value.kind === 'enumeration' ? pascal(type.value.enumeration) : zigType(ctx, type.value)})`;
    case 'handle': return `?*${pascal(type.handle)}`;
    case 'bytes': return '?[*]const u8';
    case 'text': return '?[*]const c_char';
    case 'web_string': return '?[*]const u16';
    default: throw new AbiError(`No Zig mapping exists for kind ${type.kind}.`);
  }
}
const cDeclaration = (type, member) => type.endsWith('*') ? `${type}${member}` : `${type} ${member}`;

/** The C parameter declarations of one schema parameter. */
function cParameters(ctx, p) {
  const p0 = ctx.prefix;
  if (p.type.kind === 'structure') {
    return p.direction === 'in' ? [`const ${p0}_${p.type.structure} *${p.name}`] : [`${p0}_${p.type.structure} *${p.name}`, `size_t ${p.name}_size`];
  }
  const value = cType(ctx, p.type);
  if (p.direction === 'out') return [cDeclaration(value.endsWith('*') ? `${value}*` : `${value} *`, p.name)];
  return RANGE_KINDS.has(p.type.kind) ? [cDeclaration(value, p.name), `size_t ${p.name}_len`] : [cDeclaration(value, p.name)];
}
function zigParameters(ctx, p) {
  if (p.type.kind === 'structure') {
    const structure = pascal(p.type.structure);
    return p.direction === 'in' ? [`${p.name}: ?*const ${structure}`] : [`${p.name}: ?*${structure}`, `${p.name}_size: usize`];
  }
  const value = zigType(ctx, p.type);
  if (p.direction === 'out') return [`${p.name}: ?*${value}`];
  return RANGE_KINDS.has(p.type.kind) ? [`${p.name}: ${value}`, `${p.name}_len: usize`] : [`${p.name}: ${value}`];
}
const cReturn = (ctx, fn) => fn.returns === 'status' ? cInteger(ctx.schema.statuses.underlying) : cType(ctx, fn.returns);
const zigReturn = (ctx, fn) => fn.returns === 'status' ? zigInteger(ctx.schema.statuses.underlying) : zigType(ctx, fn.returns);

function generateHeader(ctx) {
  const s = ctx.schema, p = ctx.prefix, upper = p.toUpperCase();
  const out = [
    `/* Generated by tools/abi.mjs from ${SCHEMA_PATH}. Do not edit.`,
    ' * Run node tools/fairpane.mjs abi-generate after a schema change.',
    ' */',
    '#ifndef FAIRPANE_H',
    '#define FAIRPANE_H',
    '',
    '#include <stddef.h>',
    '#include <stdint.h>',
    '',
    '#if defined(_WIN32) && defined(FAIRPANE_SHARED)',
    '#  if defined(FAIRPANE_BUILD)',
    `#    define ${upper}_API __declspec(dllexport)`,
    '#  else',
    `#    define ${upper}_API __declspec(dllimport)`,
    '#  endif',
    '#else',
    `#  define ${upper}_API`,
    '#endif',
    '',
    '#ifdef __cplusplus',
    'extern "C" {',
    '#endif',
    '',
    `/* ${s.description} */`,
    `#define ${upper}_ABI_REVISION UINT32_C(${s.abi_revision})`,
    '',
    '/* A value that may be absent. Zero encodes absence, and the value itself is never zero. */',
    `#define ${upper}_OPTIONAL(type) type`,
    '',
  ];
  const enumeration = (description, members, macroPrefix, underlying) => {
    out.push(`/* ${description} */`);
    for (const m of members) out.push(`/* ${m.description} */`, `#define ${macroPrefix}_${m.name.toUpperCase()} ${cLiteral(m.value, underlying)}`);
    out.push('');
  };
  enumeration(s.statuses.description, s.statuses.members, `${upper}_STATUS`, s.statuses.underlying);
  for (const e of s.enumerations) enumeration(e.description, e.members, `${upper}_${e.member_prefix.toUpperCase()}`, e.underlying);
  for (const c of s.constants) out.push(`/* ${c.description} */`, `#define ${upper}_${c.name.toUpperCase()} ${cLiteral(c.value, c.type)}`, '');
  for (const h of s.handles) out.push(`/* ${h.description} */`, `typedef struct ${p}_${h.name} ${p}_${h.name};`, '');
  for (const i of s.identifiers) out.push(`/* ${i.description} */`, `typedef uint64_t ${p}_${i.name}_id;`, '');
  for (const st of s.structures) {
    out.push(`/* ${st.description} */`, `typedef struct ${p}_${st.name} {`);
    for (const f of st.fields) {
      if (f.description) out.push(`    /* ${f.description} */`);
      out.push(`    ${cDeclaration(cType(ctx, f.type), f.name)};`);
      if (RANGE_KINDS.has(f.type.kind)) out.push(`    size_t ${f.name}_len;`);
    }
    out.push(`} ${p}_${st.name};`, '');
  }
  for (const fn of s.functions) {
    const parameters = fn.parameters.flatMap(param => cParameters(ctx, param));
    out.push(`/* ${fn.description} */`, `${upper}_API ${cReturn(ctx, fn)} ${p}_${fn.name}(${parameters.length ? parameters.join(', ') : 'void'});`, '');
  }
  out.push('#ifdef __cplusplus', '}', '#endif', '#endif', '');
  return out.join('\n');
}

function generateZig(ctx) {
  const s = ctx.schema, p = ctx.prefix;
  const out = [
    `//! Generated by tools/abi.mjs from ${SCHEMA_PATH}. Do not edit.`,
    '//! Run `node tools/fairpane.mjs abi-generate` after a schema change.',
    `//! ${s.description}`,
    '',
    'const std = @import("std");',
    '',
    `pub const abi_revision: u32 = ${s.abi_revision};`,
    '',
  ];
  const enumeration = (description, typeName, members, underlying) => {
    out.push(`/// ${description}`, `pub const ${typeName} = enum(${zigInteger(underlying)}) {`);
    for (const m of members) out.push(`    /// ${m.description}`, `    ${m.name} = ${literal(m.value, underlying)},`);
    out.push('};', '');
  };
  enumeration(s.statuses.description, 'Status', s.statuses.members, s.statuses.underlying);
  for (const e of s.enumerations) enumeration(e.description, pascal(e.name), e.members, e.underlying);
  for (const c of s.constants) out.push(`/// ${c.description}`, `pub const ${c.name}: ${zigInteger(c.type)} = ${literal(c.value, c.type)};`, '');
  for (const h of s.handles) out.push(`/// ${h.description}`, `pub const ${pascal(h.name)} = opaque {};`, '');
  for (const i of s.identifiers) out.push(`/// ${i.description}`, `pub const ${pascal(i.name)}Id = enum(u64) { _ };`, '');
  out.push(
    '/// A value that may be absent. Zero encodes absence, and the value itself is never zero.',
    'pub fn Optional(comptime T: type) type {',
    '    const Raw = switch (@typeInfo(T)) {',
    '        .int => T,',
    '        .@"enum" => |info| info.tag_type,',
    '        else => @compileError("An optional value needs an integer, enumeration, or identifier type."),',
    '    };',
    '    return enum(Raw) {',
    '        absent = 0,',
    '        _,',
    '',
    '        /// Wraps a present value, which is never zero.',
    '        pub fn of(value: T) @This() {',
    '            const raw: Raw = if (@typeInfo(T) == .int) value else @backingInt(value);',
    '            std.debug.assert(raw != 0);',
    '            return @fromBackingInt(raw);',
    '        }',
    '',
    '        /// Returns the value, or null when it is absent or outside its enumeration.',
    '        pub fn get(optional: @This()) ?T {',
    '            if (optional == .absent) return null;',
    '            const raw = @backingInt(optional);',
    '            return if (@typeInfo(T) == .int) raw else std.enums.fromInt(T, raw);',
    '        }',
    '    };',
    '}',
    '',
  );
  for (const st of s.structures) {
    out.push(`/// ${st.description}`, `pub const ${pascal(st.name)} = extern struct {`);
    for (const f of st.fields) {
      if (f.description) out.push(`    /// ${f.description}`);
      out.push(`    ${f.name}: ${zigType(ctx, f.type)},`);
      if (RANGE_KINDS.has(f.type.kind)) out.push(`    ${f.name}_len: usize,`);
    }
    out.push('};', '');
  }
  out.push('/// The C function types, by symbol name.', 'pub const functions = struct {');
  for (const fn of s.functions) {
    const parameters = fn.parameters.flatMap(param => zigParameters(ctx, param));
    out.push(`    /// ${fn.description}`, `    pub const ${p}_${fn.name} = fn (${parameters.join(', ')}) callconv(.c) ${zigReturn(ctx, fn)};`);
  }
  out.push('};', '');
  out.push(
    '/// Selects the layout value that the schema implies for the target pointer width.',
    'fn layout(comptime wide: comptime_int, comptime narrow: comptime_int) comptime_int {',
    '    return if (@sizeOf(usize) == 8) wide else narrow;',
    '}',
    '',
    '// The size and every field offset that the schema implies for each structure.',
    'comptime {',
    '    if (@sizeOf(usize) != 8 and @sizeOf(usize) != 4) @compileError("The schema implies layouts for 32-bit and 64-bit pointers only.");',
  );
  const expression = (wide, narrow) => wide === narrow ? `${wide}` : `layout(${wide}, ${narrow})`;
  for (const st of s.structures) {
    const zig = pascal(st.name), wide = layoutOf(ctx, st, 8), narrow = layoutOf(ctx, st, 4);
    out.push(`    if (@sizeOf(${zig}) != ${expression(wide.size, narrow.size)}) @compileError("${zig} differs from the size that the schema implies.");`);
    for (const [i, member] of wide.offsets.entries()) {
      out.push(`    if (@offsetOf(${zig}, "${member.name}") != ${expression(member.offset, narrow.offsets[i].offset)}) @compileError("${zig}.${member.name} differs from the offset that the schema implies.");`);
    }
  }
  out.push('}', '');
  return out.join('\n');
}

/** Validate the schema and generate every output file. The result maps each path in GENERATED_FILES to its text. */
export function generate(schema) {
  validateSchema(schema);
  const ctx = index(schema);
  return { [GENERATED_FILES[0]]: generateHeader(ctx), [GENERATED_FILES[1]]: generateZig(ctx) };
}

/** Validate the failure scenarios against the schema. Throws an AbiError that names the first problem. */
export function validateScenarios(scenarios, schema) {
  check(isObject(scenarios) && scenarios.schema_version === 1, 'The scenario file needs schema_version 1.');
  onlyKeys(scenarios, ['schema_version', 'abi_schema', 'description', 'scenarios'], 'scenario file');
  check(scenarios.abi_schema === SCHEMA_PATH, `The scenario file must name ${SCHEMA_PATH}.`);
  text(scenarios.description, 'scenario file');
  check(Array.isArray(scenarios.scenarios) && scenarios.scenarios.length > 0, 'The scenario file needs a nonempty scenarios list.');
  const functions = new Map(schema.functions.map(fn => [`${schema.prefix}_${fn.name}`, fn]));
  const ids = new Set(), situations = new Set();
  for (const [i, item] of scenarios.scenarios.entries()) {
    check(isObject(item), `scenario ${i + 1} must be an object.`);
    const where = typeof item.id === 'string' ? `scenario ${item.id}` : `scenario ${i + 1}`;
    onlyKeys(item, ['id', 'situation', 'description', 'expressible_in_c', 'reason', 'calls', 'effects'], where);
    check(typeof item.id === 'string' && SCENARIO_ID.test(item.id), `${where} needs an identifier in lowercase kebab case.`);
    check(!ids.has(item.id), `duplicate scenario "${item.id}".`);
    ids.add(item.id);
    check(SCENARIO_SITUATIONS.includes(item.situation), `${where} names an unknown situation "${item.situation}".`);
    situations.add(item.situation);
    text(item.description, where);
    check(typeof item.expressible_in_c === 'boolean', `${where} must state whether C can express it.`);
    if (item.expressible_in_c) check(item.reason === undefined, `${where}: only a scenario that C cannot express states a reason.`);
    else text(item.reason, `${where} reason`);
    check(Array.isArray(item.calls) && item.calls.length > 0, `${where} needs its calls.`);
    for (const [j, call] of item.calls.entries()) {
      const at = `${where}: call ${j + 1}`;
      check(isObject(call), `${at} must be an object.`);
      onlyKeys(call, ['function', 'arguments', 'status'], at);
      check(functions.has(call.function), `${where} names unknown function "${call.function}".`);
      text(call.arguments, `${at} arguments`);
      check(typeof call.status === 'string', `${at} needs an expected status.`);
      check(functions.get(call.function).statuses.includes(call.status), `${where}: ${call.function} cannot return status "${call.status}".`);
    }
    check(Array.isArray(item.effects) && item.effects.length > 0, `${where} needs its expected effects.`);
    for (const [j, effect] of item.effects.entries()) text(effect, `${where}: effect ${j + 1}`);
  }
  for (const situation of SCENARIO_SITUATIONS) check(situations.has(situation), `No scenario covers the ${situation} situation.`);
  return true;
}

/** The scenario identifiers that a test source names with `Scenario <id>:` markers. */
export function scenarioMarkers(source) {
  return new Set([...source.matchAll(/\bScenario ([a-z0-9]+(?:-[a-z0-9]+)*):/g)].map(m => m[1]));
}

/** Read and validate the schema and the failure scenarios of the repository at `root`. */
export function loadAbi(root) {
  const schema = readJson(safePath(root, SCHEMA_PATH));
  validateSchema(schema);
  validateScenarios(readJson(safePath(root, SCENARIOS_PATH)), schema);
  return schema;
}

/** Write every generated file from the schema. */
export function abiGenerate(root) {
  const generated = generate(loadAbi(root));
  for (const file of GENERATED_FILES) fs.writeFileSync(safePath(root, file, { mustExist: false }), generated[file]);
  return { result: 'written', schema: SCHEMA_PATH, files: [...GENERATED_FILES] };
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

/** Regenerate in memory and compare each committed file byte for byte. */
export function abiCheck(root) {
  const generated = generate(loadAbi(root));
  const differences = [];
  for (const file of GENERATED_FILES) {
    const expected = Buffer.from(generated[file], 'utf8'), absolute = path.join(root, file);
    if (!fs.existsSync(absolute)) { differences.push({ file, line: null, problem: 'missing' }); continue; }
    const actual = fs.readFileSync(safePath(root, file));
    if (!actual.equals(expected)) differences.push({ file, line: firstDifferentLine(expected, actual), problem: 'differs from the generator output' });
  }
  return differences.length
    ? { result: 'stale', schema: SCHEMA_PATH, differences, instruction: 'Run node tools/fairpane.mjs abi-generate and review the change.' }
    : { result: 'pass', schema: SCHEMA_PATH, files: [...GENERATED_FILES] };
}
