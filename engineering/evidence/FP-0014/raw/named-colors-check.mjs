// FP-0014 integrator check: compare src/css/named_colors.zig with the named-color table of CSS Color 4 at
// w3c/csswg-drafts 58354dac99cc8783a9b7b28957ece56bb48579eb, as the contract's evidence section requires.
// Usage, from the repository root: node engineering/evidence/FP-0014/raw/named-colors-check.mjs <Overview.bs> <named_colors.zig>
// Exit status 0 means every row matches; status 1 means a difference, which the output names.
import fs from 'node:fs';

const [bsPath, zigPath] = process.argv.slice(2);
if (!bsPath || !zigPath) { console.error('usage: named-colors-check.mjs <Overview.bs> <named_colors.zig>'); process.exit(2); }

// Section 6.1 lists each named color as a table row: swatches, then the name, the hex form, and the decimal form.
const spec = [...fs.readFileSync(bsPath, 'utf8').matchAll(/<th scope=row><dfn[^>]*>([a-z]+)<\/dfn><td>#([0-9a-f]{6})<td>(\d+) (\d+) (\d+)/g)]
  .map(m => ({ name: m[1], hex: m[2], rgb: [Number(m[3]), Number(m[4]), Number(m[5])] }));
const zig = [...fs.readFileSync(zigPath, 'utf8').matchAll(/\.\{ \.name = "([a-z]+)", \.red = (\d+), \.green = (\d+), \.blue = (\d+) \}/g)]
  .map(m => ({ name: m[1], rgb: [Number(m[2]), Number(m[3]), Number(m[4])] }));

const problems = [];
for (const row of spec) {
  const fromHex = [0, 2, 4].map(i => parseInt(row.hex.slice(i, i + 2), 16));
  if (fromHex.join() !== row.rgb.join()) problems.push(`specification row ${row.name}: #${row.hex} disagrees with ${row.rgb.join(' ')}`);
}
const ascending = rows => rows.every((r, i) => i === 0 || Buffer.compare(Buffer.from(rows[i - 1].name), Buffer.from(r.name)) < 0);
if (!ascending(spec)) problems.push('the specification table is not in ascending name order');
if (!ascending(zig)) problems.push('named_colors.zig is not in ascending name order');
if (spec.length !== zig.length) problems.push(`the specification has ${spec.length} rows and named_colors.zig has ${zig.length}`);
for (let i = 0; i < Math.max(spec.length, zig.length); i++) {
  const s = spec[i], z = zig[i];
  if (!s || !z || s.name !== z.name || s.rgb.join() !== z.rgb.join()) {
    problems.push(`row ${i + 1}: specification ${s ? `${s.name} ${s.rgb.join(' ')}` : 'none'}, named_colors.zig ${z ? `${z.name} ${z.rgb.join(' ')}` : 'none'}`);
  }
}
console.log(`specification rows: ${spec.length}`);
console.log(`named_colors.zig rows: ${zig.length}`);
for (const p of problems) console.log(`problem: ${p}`);
console.log(`result: ${problems.length ? 'fail' : 'pass'}`);
process.exitCode = problems.length ? 1 : 0;
