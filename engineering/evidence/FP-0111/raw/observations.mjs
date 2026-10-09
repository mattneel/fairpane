// FP-0111 README observations, recorded without assertions: lookup, flag, coverage, and caret counts from the version 2
// expectation files, AttachList and lookupOrderOffset values read from the font bytes, and the size and SHA-256 of each
// version 1 (at the base commit) and version 2 expectation file. Run from the repository root.
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';

const BASE = 'ca026e8';
const FIXTURES = [
  'tests/text/fonts/noto-sans/NotoSans-Regular',
  'tests/text/fonts/noto-sans-arabic/NotoSansArabic-Regular',
  'tests/text/fonts/noto-sans-devanagari/NotoSansDevanagari-Regular',
  'tests/text/fonts/noto-sans-cjk-jp-subset/cjk-subset',
];
const FONT_EXT = { 'cjk-subset': '.otf' };
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const count = (map, key) => map.set(key, (map.get(key) ?? 0) + 1);
const show = map => [...map.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([k, v]) => `${k}=${v}`).join(' ') || 'none';

/** The table directory of an sfnt font, by tag. */
function directory(font) {
  const tables = new Map();
  for (let i = 0; i < font.readUInt16BE(4); i++) {
    const at = 12 + 16 * i;
    tables.set(font.toString('latin1', at, at + 4), { offset: font.readUInt32BE(at + 8), length: font.readUInt32BE(at + 12) });
  }
  return tables;
}

/** Every LangSys lookupOrderOffset of a GSUB or GPOS table, default and listed, in table order. */
function lookupOrderOffsets(font, table) {
  const out = [];
  const scriptList = table.offset + font.readUInt16BE(table.offset + 4);
  for (let i = 0; i < font.readUInt16BE(scriptList); i++) {
    const script = scriptList + font.readUInt16BE(scriptList + 2 + 6 * i + 4);
    const defaultOffset = font.readUInt16BE(script);
    if (defaultOffset !== 0) out.push(font.readUInt16BE(script + defaultOffset));
    for (let j = 0; j < font.readUInt16BE(script + 2); j++) out.push(font.readUInt16BE(script + font.readUInt16BE(script + 4 + 6 * j + 4)));
  }
  return out;
}

for (const stem of FIXTURES) {
  const name = stem.split('/').pop();
  const fontPath = `${stem}${FONT_EXT[name] ?? '.ttf'}`;
  const expectPath = `${stem}.expect.json`;
  const font = fs.readFileSync(fontPath);
  const v2 = fs.readFileSync(expectPath);
  const v1 = execFileSync('git', ['show', `${BASE}:${expectPath}`], { maxBuffer: 1 << 26 });
  const e = JSON.parse(v2.toString('utf8'));
  console.log(`# ${fontPath}`);
  console.log(`expectation version 1 at ${BASE}: ${v1.length} bytes, SHA-256 ${sha256(v1)}`);
  console.log(`expectation version 2: ${v2.length} bytes, SHA-256 ${sha256(v2)}`);
  const tables = directory(font);
  for (const tag of ['gsub', 'gpos']) {
    const layout = e[tag];
    if (layout === null) { console.log(`${tag}: absent`); continue; }
    const byTypeFormat = new Map(), flagBits = new Map(), coverageFormats = new Map();
    let extensions = 0, markFilteringSets = 0, subtables = 0;
    for (const lookup of layout.lookups) {
      if (lookup.subtables.some(s => s.extension)) extensions++;
      if (lookup.mark_filtering_set !== null) markFilteringSets++;
      for (let bit = 0; bit < 16; bit++) if (lookup.flag & (1 << bit)) count(flagBits, `0x${(1 << bit).toString(16).padStart(4, '0')}`);
      for (const s of lookup.subtables) {
        subtables++;
        count(byTypeFormat, `type${s.type}/format${s.format}`);
        count(coverageFormats, `format${s.coverage.format}`);
      }
    }
    const orders = lookupOrderOffsets(font, tables.get(tag.toUpperCase()));
    console.log(`${tag}: version 0x${layout.version.toString(16).padStart(8, '0')}, feature_variations ${layout.feature_variations}, ` +
      `${layout.scripts.length} scripts, ${layout.features.length} features, ${layout.lookups.length} lookups, ${subtables} subtables`);
    console.log(`${tag} subtables by effective type and format: ${show(byTypeFormat)}`);
    console.log(`${tag} extension lookups: ${extensions}; lookups with a mark filtering set: ${markFilteringSets}`);
    console.log(`${tag} lookups with each flag bit: ${show(flagBits)}`);
    console.log(`${tag} primary coverages by format: ${show(coverageFormats)}`);
    console.log(`${tag} LangSys tables: ${orders.length}; nonzero lookupOrderOffset: ${orders.filter(o => o !== 0).length}`);
  }
  const gdef = e.gdef;
  if (gdef === null) { console.log('gdef: absent'); continue; }
  const gdefTable = tables.get('GDEF');
  const attachList = font.readUInt16BE(gdefTable.offset + 6);
  const caretFormats = new Map();
  for (const entry of gdef.lig_caret_list ?? []) for (const caret of entry.carets) count(caretFormats, `format${caret.format}`);
  console.log(`gdef: version 0x${gdef.version.toString(16).padStart(8, '0')}, AttachList offset ${attachList}, item_var_store ${gdef.item_var_store}`);
  console.log(`gdef glyph_class_def: ${gdef.glyph_class_def === null ? 'absent' : `format ${gdef.glyph_class_def.format}, ${gdef.glyph_class_def.classes.length} classed glyphs`}`);
  console.log(`gdef mark_attach_class_def: ${gdef.mark_attach_class_def === null ? 'absent' : `format ${gdef.mark_attach_class_def.format}, ${gdef.mark_attach_class_def.classes.length} classed glyphs`}`);
  console.log(`gdef mark_glyph_sets: ${gdef.mark_glyph_sets === null ? 'absent' : `${gdef.mark_glyph_sets.sets.length} sets`}`);
  console.log(`gdef lig_caret_list: ${gdef.lig_caret_list === null ? 'absent' : `${gdef.lig_caret_list.length} ligatures, carets ${show(caretFormats)}`}`);
}
