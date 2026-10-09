// Throwaway FP-0027 helper. "write <log> <copy>" copies the statement that a recorded provenance run printed;
// "check <log> <copy>" exits 0 and prints "equal" only when the copy parses to the same statement.
import fs from 'node:fs';
import { isDeepStrictEqual } from 'node:util';
const [mode, logPath, copyPath] = process.argv.slice(2);
const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/);
const start = lines.findIndex(l => l.startsWith('COMMAND') && l.includes('"provenance"'));
const end = lines.findIndex((l, i) => i > start && l.startsWith('RESULT'));
if (start < 0 || end < 0) throw new Error('No provenance record in the log.');
const statement = JSON.parse(lines.slice(start + 1, end).join('\n'));
if (mode === 'write') fs.writeFileSync(copyPath, `${JSON.stringify(statement, null, 2)}\n`);
else if (mode === 'check') {
  const copy = JSON.parse(fs.readFileSync(copyPath, 'utf8'));
  if (!isDeepStrictEqual(copy, statement)) { console.log('different'); process.exit(1); }
  console.log('equal');
} else throw new Error('Usage: write|check <log> <copy>');
