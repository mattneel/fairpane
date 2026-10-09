/**
 * Capability records under `specs/capabilities/`. A record states what the engine does now for each obligation of a family,
 * and names the plan task that owns each remaining obligation.
 */
import { invariant } from './lib.mjs';

/** The frozen obligation set of the `text-fonts` family, from the FP-0013 contract as FP-0108 amends it. */
export const TEXT_FONT_OBLIGATIONS = Object.freeze([
  ['unicode-properties', 'implemented', 'FP-0013'], ['opentype-core-tables', 'implemented', 'FP-0013'],
  ['unicode-remaining-data', 'remaining', 'FP-0055'], ['bidi-algorithm', 'remaining', 'FP-0015'],
  ['grapheme-segmentation', 'implemented', 'FP-0108'], ['line-breaking', 'remaining', 'FP-0015'], ['shaping', 'remaining', 'FP-0015'],
  ['font-fallback', 'remaining', 'FP-0015'], ['glyph-rasterization', 'remaining', 'FP-0056'], ['truetype-hinting', 'remaining', 'FP-0057'],
  ['woff', 'remaining', 'FP-0058'], ['woff2-brotli', 'remaining', 'FP-0058'], ['font-collections', 'remaining', 'FP-0059'],
  ['cff2-and-variations', 'remaining', 'FP-0059'], ['color-fonts', 'remaining', 'FP-0060'], ['vertical-metrics', 'remaining', 'FP-0061'],
  ['cmap-variation-and-legacy-formats', 'remaining', 'FP-0061'], ['layout-auxiliary-tables', 'remaining', 'FP-0062'],
  ['platform-font-discovery', 'remaining', 'FP-0063'],
].map(([id, status, owner_task]) => Object.freeze({ id, status, owner_task })));

const STATUSES = new Set(['implemented', 'remaining']);
const OBLIGATION_FIELDS = ['id', 'status', 'owner_task', 'summary', 'engine_behavior'];

/** Validate `specs/capabilities/text-fonts.json` against the frozen obligation set and the task IDs of `plan`. */
export function validateCapabilityRecord(record, plan) {
  invariant(record && typeof record === 'object' && !Array.isArray(record), 'The capability record must be an object.');
  for (const key of Object.keys(record)) invariant(['schema_version', 'family', 'unicode_version', 'obligations'].includes(key), `The capability record has an unexpected field "${key}".`);
  invariant(record.schema_version === 1, 'The capability record needs schema_version 1.');
  invariant(record.family === 'text-fonts', 'The capability record family must be "text-fonts".');
  invariant(record.unicode_version === '18.0.0', 'The capability record must state Unicode version 18.0.0.');
  invariant(Array.isArray(record.obligations), 'The capability record needs an obligations list.');
  const tasks = new Set(plan.tasks.map(t => t.id)), seen = new Set();
  for (const o of record.obligations) {
    invariant(o && typeof o === 'object', 'Each obligation must be an object.');
    const where = `Obligation ${o.id}`;
    for (const key of Object.keys(o)) invariant(OBLIGATION_FIELDS.includes(key), `${where} has an unexpected field "${key}".`);
    invariant(typeof o.id === 'string' && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(o.id) && !seen.has(o.id), `Obligation IDs must be unique kebab-case names: ${o.id}`);
    seen.add(o.id);
    invariant(STATUSES.has(o.status), `${where} status must be implemented or remaining.`);
    invariant(typeof o.owner_task === 'string' && o.owner_task.length > 0, `${where} needs an owner task.`);
    invariant(tasks.has(o.owner_task), `${where} names owner task ${o.owner_task}, which is not in engineering/plan.json.`);
    for (const field of ['summary', 'engine_behavior']) invariant(typeof o[field] === 'string' && o[field].trim().length > 0, `${where} needs a ${field}.`);
  }
  for (const frozen of TEXT_FONT_OBLIGATIONS) {
    const o = record.obligations.find(x => x.id === frozen.id);
    invariant(o, `The capability record is missing obligation ${frozen.id}.`);
    invariant(o.status === frozen.status && o.owner_task === frozen.owner_task,
      `Obligation ${frozen.id} must be ${frozen.status} with owner ${frozen.owner_task}, not ${o.status} with owner ${o.owner_task}.`);
  }
  invariant(record.obligations.length === TEXT_FONT_OBLIGATIONS.length, 'The capability record has obligations outside the frozen set.');
  return true;
}
