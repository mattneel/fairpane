// FP-0082: builds a copy of src with the stack probe appended to src/js/parser.zig.
// Usage: node make-stack-overlay.mjs <output-directory> [recursive]
// With "recursive", the copy takes src/js/parser.zig and src/js/ast.zig from the recursive-descent
// implementation that this directory keeps as recursive-parser.zig.txt and recursive-ast.zig.txt.
import { cpSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [output, variant] = process.argv.slice(2);
if (!output || (variant !== undefined && variant !== 'recursive')) throw new Error('Usage: node make-stack-overlay.mjs <output-directory> [recursive]');
rmSync(output, { recursive: true, force: true });
cpSync('src', join(output, 'src'), { recursive: true });
const parser = join(output, 'src', 'js', 'parser.zig');
if (variant === 'recursive') {
  writeFileSync(parser, readFileSync(join(here, 'recursive-parser.zig.txt')));
  writeFileSync(join(output, 'src', 'js', 'ast.zig'), readFileSync(join(here, 'recursive-ast.zig.txt')));
}
writeFileSync(parser, readFileSync(parser, 'utf8') + readFileSync(join(here, 'stack-probe.zig.txt'), 'utf8'));
