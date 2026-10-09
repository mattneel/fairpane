/**
 * Policy checks for GitHub Actions workflows.
 * The parser reads only the YAML subset that these checks need and rejects any other syntax with a line number,
 * so the controller needs no YAML package and no unreadable construct passes unchecked.
 *
 * Accepted: block mappings with plain keys, block sequences, plain and quoted single-line scalars,
 * single-line flow sequences of scalars, `|` and `>` block scalars, and comments.
 * Rejected: anchors, aliases, tags, flow mappings, complex keys, quoted keys, document markers, directives,
 * multi-line plain or quoted scalars, block scalars as sequence items, duplicate keys, and tab indentation.
 */

export class WorkflowParseError extends Error {
  constructor(line, message) {
    super(`Line ${line}: ${message}`);
    this.name = 'WorkflowParseError';
    this.line = line;
  }
}

const KEY = /^([A-Za-z_][A-Za-z0-9_.-]*):(?=[ ]|$)/;
const DOUBLE_ESCAPES = { '\\': '\\', '"': '"', '/': '/', n: '\n', t: '\t', r: '\r', '0': '\0' };
const nullNode = line => ({ kind: 'null', line });
const scalarNode = (value, line, comment = null, style = 'plain') => ({ kind: 'scalar', value, line, comment, style });

/** The text after a complete value: nothing, or a comment that follows whitespace. Returns the comment text. */
function trailing(rest, line) {
  const m = /^(?:[ ]+#(.*))?[ ]*$/.exec(rest);
  if (!m) throw new WorkflowParseError(line, `Unexpected text after a value: ${rest.trim()}`);
  return m[1] === undefined ? null : m[1].trim();
}

/** A quoted scalar that starts at text[0] and ends on the same line. */
function quoted(text, line) {
  const quote = text[0];
  let value = '';
  for (let i = 1; i < text.length; i++) {
    const c = text[i];
    if (quote === "'" && c === "'") {
      if (text[i + 1] === "'") { value += "'"; i++; continue; }
      return { value, end: i + 1 };
    }
    if (quote === '"' && c === '"') return { value, end: i + 1 };
    if (quote === '"' && c === '\\') {
      const escaped = DOUBLE_ESCAPES[text[i + 1]];
      if (escaped === undefined) throw new WorkflowParseError(line, `Unsupported escape \\${text[i + 1] ?? ''} in a double-quoted scalar.`);
      value += escaped; i++; continue;
    }
    value += c;
  }
  throw new WorkflowParseError(line, 'A quoted scalar must end on its own line.');
}

/** A single-line flow sequence of scalars that starts at text[0]. */
function flowSequence(text, line) {
  const items = [];
  let i = 1;
  const skip = () => { while (text[i] === ' ') i++; };
  skip();
  if (text[i] === ']') return { node: { kind: 'seq', items, line }, end: i + 1 };
  for (;;) {
    skip();
    if (i >= text.length) throw new WorkflowParseError(line, 'A flow sequence must close on its own line.');
    if (text[i] === '"' || text[i] === "'") {
      const q = quoted(text.slice(i), line);
      items.push(scalarNode(q.value, line, null, 'quoted'));
      i += q.end;
    } else {
      const start = i;
      while (i < text.length && text[i] !== ',' && text[i] !== ']') i++;
      const plain = text.slice(start, i).trim();
      if (!plain || /[[\]{}#&*!|>%@`]|: |:$/.test(plain) || /^[-?:](?: |$)/.test(plain)) {
        throw new WorkflowParseError(line, `Unsupported flow sequence item: ${plain || '(empty)'}`);
      }
      items.push(scalarNode(plain, line));
    }
    skip();
    if (text[i] === ']') return { node: { kind: 'seq', items, line }, end: i + 1 };
    if (text[i] !== ',') throw new WorkflowParseError(line, 'A flow sequence must close on its own line.');
    i++;
  }
}

/** The value that follows a key or a sequence dash. `block` is true for a block scalar header. */
function inlineValue(text, line) {
  const t = text.replace(/^ +/, '');
  if (t === '' || t.startsWith('#')) return { node: nullNode(line), block: false };
  if (t[0] === '"' || t[0] === "'") {
    const q = quoted(t, line);
    return { node: scalarNode(q.value, line, trailing(t.slice(q.end), line), 'quoted'), block: false };
  }
  if (t[0] === '[') {
    const f = flowSequence(t, line);
    trailing(t.slice(f.end), line);
    return { node: f.node, block: false };
  }
  if (t[0] === '|' || t[0] === '>') {
    const m = /^[|>][-+]?(?= |$)/.exec(t);
    if (!m) throw new WorkflowParseError(line, `Unsupported block scalar header: ${t}`);
    trailing(t.slice(m[0].length), line);
    return { node: scalarNode('', line, null, 'block'), block: true };
  }
  if (/^[&*!{}\],%@`?:]/.test(t) || /^-(?: |$)/.test(t)) throw new WorkflowParseError(line, `Unsupported YAML syntax: ${t}`);
  const hash = t.search(/ #/);
  const body = (hash === -1 ? t : t.slice(0, hash)).trimEnd();
  if (/: |:$/.test(body)) throw new WorkflowParseError(line, `A plain scalar cannot contain ": ". Quote it: ${body}`);
  return { node: scalarNode(body, line, hash === -1 ? null : t.slice(hash + 2).trim()), block: false };
}

/** Flatten the text into dash, entry, and scalar tokens with their columns. Block scalars consume their lines here. */
function tokenize(text) {
  const lines = text.replace(/^\uFEFF/, '').split('\n').map(l => (l.endsWith('\r') ? l.slice(0, -1) : l));
  const tokens = [];
  for (let i = 0; i < lines.length; i++) {
    const line = i + 1, raw = lines[i];
    if (raw.includes('\r')) throw new WorkflowParseError(line, 'A lone carriage return is not accepted.');
    const indent = /^ */.exec(raw)[0].length;
    let rest = raw.slice(indent), column = indent, dashed = false;
    if (rest === '' || rest.startsWith('#')) continue;
    if (rest[0] === '\t') throw new WorkflowParseError(line, 'Tabs are not accepted in indentation.');
    while (rest === '-' || rest.startsWith('- ')) {
      tokens.push({ type: 'dash', indent: column, line });
      const pad = /^ */.exec(rest.slice(1))[0].length;
      column += 1 + pad; rest = rest.slice(1 + pad); dashed = true;
      if (rest[0] === '\t') throw new WorkflowParseError(line, 'Tabs are not accepted in indentation.');
    }
    if (rest === '' || rest.startsWith('#')) continue;
    const key = KEY.exec(rest);
    let token;
    if (key) token = { type: 'entry', indent: column, line, key: key[1], ...inlineValue(rest.slice(key[0].length), line) };
    else if (dashed) {
      token = { type: 'scalar', indent: column, line, ...inlineValue(rest, line) };
      if (token.block) throw new WorkflowParseError(line, 'A block scalar is not accepted as a sequence item.');
    } else throw new WorkflowParseError(line, `Expected a mapping key or a sequence item: ${rest}`);
    tokens.push(token);
    if (!token.block) continue;
    // A block scalar owns the following blank lines and every line indented beyond its key.
    let end = i + 1, contentIndent = null;
    const body = [];
    while (end < lines.length) {
      const l = lines[end], lead = /^ */.exec(l)[0].length;
      if (l.trim() !== '') {
        if (lead <= column) break;
        if (contentIndent === null) contentIndent = lead;
        else if (lead < contentIndent) throw new WorkflowParseError(end + 1, 'A block scalar line is indented less than its first line.');
      }
      body.push(l); end++;
    }
    while (body.length && body.at(-1).trim() === '') { body.pop(); end--; }
    if (contentIndent === null) throw new WorkflowParseError(line, 'A block scalar has no content.');
    token.node.value = body.map(l => l.slice(contentIndent)).join('\n');
    i = end - 1;
  }
  return tokens;
}

/** Parse workflow text into nodes: `map` with `entries`, `seq` with `items`, `scalar` with `value` and `comment`, or `null`. */
export function parseWorkflow(text) {
  if (typeof text !== 'string') throw new TypeError('Workflow text must be a string.');
  const tokens = tokenize(text);
  if (tokens.length === 0) throw new WorkflowParseError(1, 'The workflow is empty.');
  let pos = 0;
  const fail = (token, message) => { throw new WorkflowParseError(token.line, message); };
  function deeper(indent) {
    const next = tokens[pos];
    if (next && next.indent > indent) fail(next, 'Unexpected indentation. Multi-line plain scalars are not accepted.');
  }
  function node() {
    const t = tokens[pos];
    if (t.type === 'dash') return sequence(t.indent);
    if (t.type === 'entry') return mapping(t.indent);
    pos++;
    return t.node;
  }
  function sequence(indent) {
    const result = { kind: 'seq', items: [], line: tokens[pos].line };
    while (pos < tokens.length && tokens[pos].type === 'dash' && tokens[pos].indent === indent) {
      const dash = tokens[pos++];
      if (pos === tokens.length || tokens[pos].indent <= indent) fail(dash, 'An empty sequence item is not accepted.');
      result.items.push(node());
    }
    deeper(indent);
    return result;
  }
  function mapping(indent) {
    const result = { kind: 'map', entries: new Map(), line: tokens[pos].line };
    while (pos < tokens.length && tokens[pos].type === 'entry' && tokens[pos].indent === indent) {
      const t = tokens[pos++];
      if (result.entries.has(t.key)) fail(t, `Duplicate key: ${t.key}`);
      let value = t.node;
      const next = tokens[pos];
      if (value.kind === 'null' && next && next.indent > indent) value = node();
      else if (value.kind === 'null' && next && next.indent === indent && next.type === 'dash') value = sequence(indent);
      else deeper(indent);
      result.entries.set(t.key, { key: t.key, line: t.line, value });
    }
    deeper(indent);
    return result;
  }
  if (tokens[0].type !== 'entry' || tokens[0].indent !== 0) fail(tokens[0], 'The workflow must be a mapping at column 1.');
  const root = mapping(0);
  if (pos !== tokens.length) fail(tokens[pos], 'Unexpected content after the workflow mapping.');
  return root;
}

const PINNED_USES = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_./-]+)?@[0-9a-f]{40}$/;
const VERSION_COMMENT = /^v\d+(?:\.\d+)*$/;
const SECRET_EXPRESSION = /\$\{\{(?:(?!\}\}).)*?\b(?:secrets|github\.token)\b/s;

function visit(n, fn) {
  fn(n);
  if (n.kind === 'map') for (const e of n.entries.values()) visit(e.value, fn);
  else if (n.kind === 'seq') for (const item of n.items) visit(item, fn);
}
const isReadOnly = entry => entry.value.kind === 'map' && entry.value.entries.size === 1 &&
  entry.value.entries.get('contents')?.value.kind === 'scalar' && entry.value.entries.get('contents').value.value === 'read';

/** Policy problems in a parsed workflow. An empty list means every check passed. */
export function workflowProblems(root) {
  const problems = [];
  const add = (line, message) => problems.push(`Line ${line}: ${message}`);
  const on = root.entries.get('on');
  if (!on) add(root.line, 'The workflow declares no trigger.');
  else {
    const v = on.value;
    const triggers = v.kind === 'scalar' ? [[v.value, v.line]] : v.kind === 'seq' ? v.items.map(i => [i.value, i.line]) :
      v.kind === 'map' ? [...v.entries.values()].map(e => [e.key, e.line]) : [];
    if (triggers.length === 0) add(on.line, 'The workflow declares no trigger.');
    for (const [name, line] of triggers) if (name === 'pull_request_target') add(line, 'The workflow uses pull_request_target.');
  }
  const permissions = root.entries.get('permissions');
  if (!permissions) add(root.line, 'The workflow does not declare permissions: contents: read.');
  else if (!isReadOnly(permissions)) add(permissions.line, 'The workflow grants a permission other than contents: read.');
  const jobs = root.entries.get('jobs');
  if (!jobs || jobs.value.kind !== 'map' || jobs.value.entries.size === 0) add(jobs?.line ?? root.line, 'The workflow has no jobs mapping.');
  else for (const [id, job] of jobs.value.entries) {
    if (job.value.kind !== 'map') { add(job.line, `Job ${id} is not a mapping.`); continue; }
    const p = job.value.entries.get('permissions');
    if (p && !isReadOnly(p)) add(p.line, `Job ${id} grants a permission other than contents: read.`);
  }
  visit(root, n => {
    if (n.kind === 'scalar' && n.value !== null && SECRET_EXPRESSION.test(n.value)) add(n.line, 'An expression reads a secret or the workflow token.');
    if (n.kind !== 'map') return;
    for (const e of n.entries.values()) {
      if (e.key === 'continue-on-error') add(e.line, 'continue-on-error is not accepted.');
      if (e.key === 'secrets') add(e.line, 'A secrets mapping is not accepted.');
    }
    const uses = n.entries.get('uses');
    if (!uses) return;
    const ref = uses.value.kind === 'scalar' ? uses.value.value : null;
    if (ref === null || !PINNED_USES.test(ref)) add(uses.line, `uses ${ref ?? '(not a scalar)'} is not pinned to a full 40-hex commit SHA.`);
    else if (!VERSION_COMMENT.test(uses.value.comment ?? '')) add(uses.line, `uses ${ref} has no version comment such as # v1.2.3.`);
    if (ref !== null && ref.split('@')[0].toLowerCase() === 'actions/checkout') {
      const w = n.entries.get('with'), persist = w?.value.kind === 'map' ? w.value.entries.get('persist-credentials') : undefined;
      if (!(persist?.value.kind === 'scalar' && persist.value.value === 'false')) add(uses.line, 'Checkout must set persist-credentials: false.');
    }
  });
  return problems;
}

/** Parse and check workflow text. Throws WorkflowParseError for syntax outside the accepted subset. */
export function checkWorkflow(text) { return workflowProblems(parseWorkflow(text)); }
