// FP-0119 case 14 observations for the README. The script asserts nothing.
// It reads each TrueType fixture directly, without the Zig decoder or fontTools, and prints:
// the counts of simple, composite, and empty glyphs; how many component records set each flag bit;
// and the largest observed value of each maxp maximum next to the maxp value.
import { readFileSync } from 'node:fs';

const fonts = [
  'tests/text/fonts/noto-sans/NotoSans-Regular.ttf',
  'tests/text/fonts/noto-sans-arabic/NotoSansArabic-Regular.ttf',
  'tests/text/fonts/noto-sans-devanagari/NotoSansDevanagari-Regular.ttf',
];

const flagNames = new Map([
  [0x0001, 'ARG_1_AND_2_ARE_WORDS'], [0x0002, 'ARGS_ARE_XY_VALUES'], [0x0004, 'ROUND_XY_TO_GRID'],
  [0x0008, 'WE_HAVE_A_SCALE'], [0x0010, 'reserved 0x0010'], [0x0020, 'MORE_COMPONENTS'],
  [0x0040, 'WE_HAVE_AN_X_AND_Y_SCALE'], [0x0080, 'WE_HAVE_A_TWO_BY_TWO'], [0x0100, 'WE_HAVE_INSTRUCTIONS'],
  [0x0200, 'USE_MY_METRICS'], [0x0400, 'OVERLAP_COMPOUND'], [0x0800, 'SCALED_COMPONENT_OFFSET'],
  [0x1000, 'UNSCALED_COMPONENT_OFFSET'], [0x2000, 'reserved 0x2000'], [0x4000, 'reserved 0x4000'], [0x8000, 'reserved 0x8000'],
]);

for (const path of fonts) {
  const b = readFileSync(path);
  const tables = new Map();
  for (let i = 0; i < b.readUInt16BE(4); i++) {
    const at = 12 + 16 * i;
    tables.set(b.toString('latin1', at, at + 4), { offset: b.readUInt32BE(at + 8), length: b.readUInt32BE(at + 12) });
  }
  const head = tables.get('head').offset;
  const longLoca = b.readInt16BE(head + 50) === 1;
  const maxpAt = tables.get('maxp').offset;
  const numGlyphs = b.readUInt16BE(maxpAt + 4);
  const maxp = {
    maxPoints: b.readUInt16BE(maxpAt + 6), maxContours: b.readUInt16BE(maxpAt + 8),
    maxCompositePoints: b.readUInt16BE(maxpAt + 10), maxCompositeContours: b.readUInt16BE(maxpAt + 12),
    maxComponentElements: b.readUInt16BE(maxpAt + 28), maxComponentDepth: b.readUInt16BE(maxpAt + 30),
  };
  const loca = tables.get('loca').offset;
  const glyf = tables.get('glyf').offset;
  const range = (g) => longLoca
    ? [b.readUInt32BE(loca + 4 * g), b.readUInt32BE(loca + 4 * g + 4)]
    : [2 * b.readUInt16BE(loca + 2 * g), 2 * b.readUInt16BE(loca + 2 * g + 2)];

  // Each glyph's points, contours, depth, and top-level records, memoized; components are visited with an explicit stack.
  const info = new Map();
  const flagCounts = new Map();
  const counts = { simple: 0, composite: 0, empty: 0 };
  const observed = { maxPoints: 0, maxContours: 0, maxCompositePoints: 0, maxCompositeContours: 0, maxComponentElements: 0, maxComponentDepth: 0 };
  const children = (g) => {
    const [start] = range(g);
    const list = [];
    let at = glyf + start + 10;
    for (;;) {
      const flags = b.readUInt16BE(at);
      list.push({ flags, glyph: b.readUInt16BE(at + 2) });
      at += 4 + (flags & 1 ? 4 : 2) + (flags & 0x8 ? 2 : flags & 0x40 ? 4 : flags & 0x80 ? 8 : 0);
      if (!(flags & 0x20)) return list;
    }
  };
  const resolve = (root) => {
    const stack = [root];
    while (stack.length) {
      const g = stack[stack.length - 1];
      if (info.has(g)) { stack.pop(); continue; }
      const [start, end] = range(g);
      if (start === end) { info.set(g, { points: 0, contours: 0, depth: 0, records: 0 }); stack.pop(); continue; }
      const contours = b.readInt16BE(glyf + start);
      if (contours >= 0) {
        const points = contours === 0 ? 0 : b.readUInt16BE(glyf + start + 10 + 2 * (contours - 1)) + 1;
        info.set(g, { points, contours, depth: 0, records: 0 });
        stack.pop();
        continue;
      }
      const list = children(g);
      const missing = list.filter((c) => !info.has(c.glyph));
      if (missing.length) { for (const c of missing) stack.push(c.glyph); continue; }
      const sum = { points: 0, contours: 0, depth: 1, records: list.length };
      for (const c of list) {
        const child = info.get(c.glyph);
        sum.points += child.points;
        sum.contours += child.contours;
        sum.depth = Math.max(sum.depth, child.depth + 1);
      }
      info.set(g, sum);
      stack.pop();
    }
    return info.get(root);
  };

  for (let g = 0; g < numGlyphs; g++) {
    const [start, end] = range(g);
    if (start === end) { counts.empty++; continue; }
    const glyph = resolve(g);
    if (b.readInt16BE(glyf + start) >= 0) {
      counts.simple++;
      observed.maxPoints = Math.max(observed.maxPoints, glyph.points);
      observed.maxContours = Math.max(observed.maxContours, glyph.contours);
    } else {
      counts.composite++;
      for (const c of children(g)) {
        for (const [mask] of flagNames) if (c.flags & mask) flagCounts.set(mask, (flagCounts.get(mask) ?? 0) + 1);
      }
      observed.maxCompositePoints = Math.max(observed.maxCompositePoints, glyph.points);
      observed.maxCompositeContours = Math.max(observed.maxCompositeContours, glyph.contours);
      observed.maxComponentElements = Math.max(observed.maxComponentElements, glyph.records);
      observed.maxComponentDepth = Math.max(observed.maxComponentDepth, glyph.depth);
    }
  }

  console.log(`${path}: ${numGlyphs} glyphs, ${counts.simple} simple, ${counts.composite} composite, ${counts.empty} empty`);
  for (const [mask, name] of flagNames) {
    console.log(`  component flag 0x${mask.toString(16).padStart(4, '0')} ${name}: ${flagCounts.get(mask) ?? 0} records`);
  }
  for (const key of Object.keys(maxp)) {
    const reached = observed[key] === maxp[key] ? 'reached' : 'not reached';
    console.log(`  ${key}: maxp ${maxp[key]}, observed ${observed[key]}, ${reached}`);
  }
}
