// Appends probe-allocations-r2.zig.txt to <dir>/src/js/parser.zig, a copy of the base sources.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [dir] = process.argv.slice(2);
if (!dir) throw new Error('Usage: node probe-allocations-r2.mjs <copy-dir>');
const probe = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'probe-allocations-r2.zig.txt'));
const target = path.join(dir, 'src', 'js', 'parser.zig');
fs.appendFileSync(target, probe);
console.log(`Appended ${probe.length} bytes to ${target}.`);
