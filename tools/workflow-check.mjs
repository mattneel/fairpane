/**
 * Policy checks for GitHub Actions workflows.
 * The parser reads only the YAML subset that these checks need and rejects any other syntax with a line number,
 * so the controller needs no YAML package and no unreadable construct passes unchecked.
 *
 * Accepted: printable ASCII text with LF or CRLF line ends, block mappings with plain keys, block sequences,
 * plain and quoted single-line scalars, single-line flow sequences of scalars, `|` and `>` block scalars, and comments.
 * Rejected: every other character, including tabs and the NEL, LS, and PS line breaks that YAML parsers honor,
 * anchors, aliases, tags, flow mappings, complex keys, quoted keys, document markers, directives,
 * multi-line plain or quoted scalars, block scalars as sequence items, duplicate keys,
 * and a block scalar whose leading blank line has more spaces than its first content line, which libyaml also rejects.
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
  const normalized = text.replace(/^\uFEFF/, '').replaceAll('\r\n', '\n');
  // A YAML parser also breaks lines at NEL, LS, and PS, so any character beyond printable ASCII could hide a key from this parser.
  const outside = /[^\n\x20-\x7E]/.exec(normalized);
  if (outside) {
    const line = normalized.slice(0, outside.index).split('\n').length;
    const code = outside[0].codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
    throw new WorkflowParseError(line, `Character U+${code} is not accepted. A workflow must be printable ASCII with LF or CRLF line ends.`);
  }
  const lines = normalized.split('\n');
  const tokens = [];
  for (let i = 0; i < lines.length; i++) {
    const line = i + 1, raw = lines[i];
    const indent = /^ */.exec(raw)[0].length;
    let rest = raw.slice(indent), column = indent, dashed = false;
    if (rest === '' || rest.startsWith('#')) continue;
    while (rest === '-' || rest.startsWith('- ')) {
      tokens.push({ type: 'dash', indent: column, line });
      const pad = /^ */.exec(rest.slice(1))[0].length;
      column += 1 + pad; rest = rest.slice(1 + pad); dashed = true;
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
    // Like libyaml, it rejects a leading blank line with more spaces than its first content line.
    let end = i + 1, contentIndent = null, blankIndent = 0, blankLine = 0;
    const body = [];
    while (end < lines.length) {
      const l = lines[end], lead = /^ */.exec(l)[0].length;
      if (l.trim() !== '') {
        if (lead <= column) break;
        if (contentIndent === null) {
          if (blankIndent > lead) throw new WorkflowParseError(blankLine, 'A leading blank line of a block scalar has more spaces than its first content line.');
          contentIndent = lead;
        } else if (lead < contentIndent) throw new WorkflowParseError(end + 1, 'A block scalar line is indented less than its first line.');
      } else if (contentIndent === null && lead > blankIndent) { blankIndent = lead; blankLine = end + 1; }
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
/**
 * The reviewed commit of each accepted action, with its release tag.
 * GitHub also fetches a commit from any fork of the action's repository, so a full SHA alone does not identify reviewed code.
 * Each SHA was resolved through the release tag's git ref in the action's own repository, as
 * engineering/evidence/FP-0033/raw/action-tag-refs.log and engineering/evidence/docs-site/raw/action-pins.log record.
 */
const REVIEWED_ACTIONS = new Map([
  ['actions/checkout', { sha: '3d3c42e5aac5ba805825da76410c181273ba90b1', version: 'v7.0.1' }],
  ['actions/setup-node', { sha: '949feb2413d6458794dcd2491c4babbbce0c15c1', version: 'v7.1.0' }],
  ['actions/upload-artifact', { sha: 'cf430e030ddbb5b0abf93d22962f4752f3646cd9', version: 'v7.0.2' }],
  ['actions/upload-pages-artifact', { sha: 'fc324d3547104276b827a68afc52ff2a11cc49c9', version: 'v5.0.0' }],
  ['actions/deploy-pages', { sha: '368f82528645a54fb793d4d04e342629a3f51346', version: 'v5.0.1' }],
]);
/** The names that an expression may read: the event fields that the reviewed workflows use, and step outputs. */
const EXPRESSION_READS = new Set(['github.event_name', 'github.run_id', 'github.event.pull_request.number']);
const STEP_OUTPUT = /^steps\.[A-Za-z_][A-Za-z0-9_-]*\.outputs\.[A-Za-z_][A-Za-z0-9_-]*$/;
const EXPRESSION_CALLS = new Set(['always', 'format']);
const EXPRESSION_LITERALS = new Set(['true', 'false', 'null']);

/**
 * The bodies of the `${{ }}` expressions in a value, with null for an expression that never closes.
 * A `}}` inside a single-quoted string literal does not close an expression; a doubled quote toggles the state twice.
 */
function expressionBodies(value) {
  const bodies = [];
  for (let start = value.indexOf('${{'); start !== -1;) {
    let end = start + 3, quoted = false;
    while (end < value.length && (quoted || !value.startsWith('}}', end))) {
      if (value[end] === "'") quoted = !quoted;
      end++;
    }
    if (end >= value.length) { bodies.push(null); break; }
    bodies.push(value.slice(start + 3, end));
    start = value.indexOf('${{', end + 2);
  }
  return bodies;
}

/** Problems in one expression body. Its string literals are removed before its names are checked against the allowlists. */
function expressionProblems(body) {
  if (body === null) return ['An expression has no closing }}.'];
  const parts = body.split("'");
  if (parts.length % 2 === 0) return ['An expression has an unterminated string literal.'];
  const code = parts.filter((_, i) => i % 2 === 0).join(' 0 ');
  const problems = [];
  const syntax = /[^A-Za-z0-9_.\s()=!<>&|,-]/.exec(code);
  if (syntax) problems.push(`An expression uses ${syntax[0]}, which the checker does not accept.`);
  for (const m of code.matchAll(/[A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*/g)) {
    const name = m[0], call = /^\s*\(/.test(code.slice(m.index + name.length));
    const allowed = call ? EXPRESSION_CALLS.has(name) : EXPRESSION_LITERALS.has(name) || EXPRESSION_READS.has(name) || STEP_OUTPUT.test(name);
    if (!allowed) problems.push(`An expression ${call ? 'calls' : 'reads'} ${name}, which is not on the allowlist.`);
  }
  return problems;
}

function visit(n, fn) {
  fn(n);
  if (n.kind === 'map') for (const e of n.entries.values()) visit(e.value, fn);
  else if (n.kind === 'seq') for (const item of n.items) visit(item, fn);
}
const isReadOnly = entry => entry.value.kind === 'map' && entry.value.entries.size === 1 &&
  entry.value.entries.get('contents')?.value.kind === 'scalar' && entry.value.entries.get('contents').value.value === 'read';
/** A scalar as written when it is a single word, and quoted otherwise, so no scalar reads like a list of grants. */
const word = n => n.kind !== 'scalar' ? `(${n.kind === 'null' ? 'nothing' : n.kind === 'seq' ? 'a sequence' : 'a mapping'})` :
  /^[A-Za-z0-9_-]+$/.test(n.value) ? n.value : JSON.stringify(n.value);
/** The exact grants of a permissions value in source order, so a reviewed problem list binds the grants themselves. */
const grants = n => n.kind === 'map' ? [...n.entries.values()].map(e => `${e.key}: ${word(e.value)}`).join(', ') : word(n);
const ACCEPTED_TRIGGERS = new Set(['push', 'pull_request', 'workflow_dispatch']);

/** Policy problems in a parsed workflow. An empty list means every check passed. */
export function workflowProblems(root) {
  const problems = [];
  const add = (line, message) => problems.push(`Line ${line}: ${message}`);
  const on = root.entries.get('on');
  if (!on) add(root.line, 'The workflow declares no trigger.');
  else {
    const v = on.value;
    const triggers = v.kind === 'scalar' ? [[v.value, v.line]] : v.kind === 'seq' ? v.items.map(i => [i.kind === 'scalar' ? i.value : null, i.line]) :
      v.kind === 'map' ? [...v.entries.values()].map(e => [e.key, e.line]) : [];
    if (triggers.length === 0) add(on.line, 'The workflow declares no trigger.');
    for (const [name, line] of triggers) {
      if (name === null) add(line, 'A trigger is not a scalar.');
      else if (!ACCEPTED_TRIGGERS.has(name)) add(line, `The workflow uses ${name}, which is not an accepted trigger.`);
    }
  }
  const permissions = root.entries.get('permissions');
  if (!permissions) add(root.line, 'The workflow does not declare permissions: contents: read.');
  else if (!isReadOnly(permissions)) add(permissions.line, `The workflow grants a permission other than contents: read (${grants(permissions.value)}).`);
  const jobs = root.entries.get('jobs');
  if (!jobs || jobs.value.kind !== 'map' || jobs.value.entries.size === 0) add(jobs?.line ?? root.line, 'The workflow has no jobs mapping.');
  else for (const [id, job] of jobs.value.entries) {
    if (job.value.kind !== 'map') { add(job.line, `Job ${id} is not a mapping.`); continue; }
    const p = job.value.entries.get('permissions');
    if (p && !isReadOnly(p)) add(p.line, `Job ${id} grants a permission other than contents: read (${grants(p.value)}).`);
  }
  visit(root, n => {
    if (n.kind === 'scalar') for (const body of expressionBodies(n.value)) for (const p of expressionProblems(body)) add(n.line, p);
    if (n.kind !== 'map') return;
    for (const e of n.entries.values()) {
      if (e.key === 'continue-on-error') add(e.line, 'continue-on-error is not accepted.');
      if (e.key === 'secrets') add(e.line, 'A secrets mapping is not accepted.');
    }
    // A run: value reaches a shell, so no expression may expand inside it. Values pass through env: instead.
    const run = n.entries.get('run');
    if (run?.value.kind === 'scalar' && run.value.value.includes('${{')) add(run.line, 'A run: value contains a ${{ }} expression. Pass the value through env: instead.');
    // An if: value is an expression even without ${{ }}.
    const condition = n.entries.get('if');
    if (condition?.value.kind === 'scalar' && !condition.value.value.includes('${{')) {
      for (const p of expressionProblems(condition.value.value)) add(condition.line, p);
    }
    const uses = n.entries.get('uses');
    if (!uses) return;
    const ref = uses.value.kind === 'scalar' ? uses.value.value : null;
    if (ref === null || !PINNED_USES.test(ref)) add(uses.line, `uses ${ref ?? '(not a scalar)'} is not pinned to a full 40-hex commit SHA.`);
    else if (!VERSION_COMMENT.test(uses.value.comment ?? '')) add(uses.line, `uses ${ref} has no version comment such as # v1.2.3.`);
    else {
      const [action, sha] = ref.split('@'), reviewed = REVIEWED_ACTIONS.get(action.toLowerCase());
      if (!reviewed || sha !== reviewed.sha || uses.value.comment !== reviewed.version) {
        add(uses.line, `uses ${ref} # ${uses.value.comment} is not a reviewed action commit.`);
      }
    }
    if (ref !== null && ref.split('@')[0].toLowerCase() === 'actions/checkout') {
      const w = n.entries.get('with'), persist = w?.value.kind === 'map' ? w.value.entries.get('persist-credentials') : undefined;
      if (!(persist?.value.kind === 'scalar' && persist.value.value === 'false')) add(uses.line, 'Checkout must set persist-credentials: false.');
    }
  });
  return problems;
}

const GATE_WORKFLOW_KEYS = ['name', 'on', 'permissions', 'concurrency', 'jobs'];
const GATE_JOB_KEYS = ['name', 'runs-on', 'timeout-minutes', 'steps'];
const GATE_RUN_KEYS = ['name', 'run'];
const GATE_COMMAND = /^node tools\/fairpane\.mjs (?:install-zig|run [a-z0-9][a-z0-9_-]*)$/;
/** The only actions that the Gates workflow may use, with the only inputs that each may receive. */
const GATE_ACTIONS = new Map([
  ['actions/checkout', ['persist-credentials']],
  ['actions/setup-node', ['node-version']],
  ['actions/upload-artifact', ['name', 'path', 'if-no-files-found']],
]);
const UPLOAD_CONDITION = '${{ always() }}';
const CONDITION_PROBLEM = `Only an upload-artifact step may set if:, and only to ${UPLOAD_CONDITION}.`;
/** The exact values of the upload-artifact inputs that decide what a Gates run uploads and whether a missing upload fails it. */
const UPLOAD_INPUTS = new Map([['path', 'out/evidence/'], ['if-no-files-found', 'error']]);
/** The filtered triggers of the Gates workflow. Each may set only branches, and only to exactly these branches. */
const GATE_FILTERED_TRIGGERS = ['push', 'pull_request'];
const GATE_BRANCHES = ['master'];
/** The exact gate list of each job that this function fixes, in order. */
const JOB_GATES = new Map([
  ['linux', ['repo-check', 'controller-test', 'zig-fmt', 'zig-test', 'cross-windows-x86_64', 'cross-linux-aarch64', 'cross-macos-aarch64']],
]);
const GATE_RUN = /^node tools\/fairpane\.mjs run ([a-z0-9][a-z0-9_-]*)$/;
const series = items => items.length < 3 ? items.join(' and ') : `${items.slice(0, -1).join(', ')}, and ${items.at(-1)}`;
const flow = n => n.kind === 'seq' ? `[${n.items.map(word).join(', ')}]` : word(n);

/**
 * Problems in the Gates workflow outside its allowlists.
 * The workflow may set only name, on, permissions, concurrency, and jobs, and a job only name, runs-on, timeout-minutes, and steps.
 * The push and pull_request triggers must each set exactly branches: [master] and nothing else, and workflow_dispatch must have no value.
 * So no filter can narrow the pushes and pull requests that run the gates.
 * A run step may set only name and run, and it runs `node tools/fairpane.mjs install-zig` or `node tools/fairpane.mjs run <gate>`.
 * An action step may set only name, uses, and with, and it uses an accepted action with only that action's accepted inputs.
 * workflowProblems binds each action to its reviewed commit, so a commit from a fork of the action's repository fails.
 * An actions/upload-artifact step must also set if: to exactly ${{ always() }}, path: out/evidence/, and if-no-files-found: error.
 * No other step may set if:.
 * So no default, environment, working directory, container, condition, or unreviewed action code can change what a gate step runs.
 * The linux job must run exactly the gates that JOB_GATES lists, in that order.
 * The other step order, the runner labels, and the Windows gate list are fixed by the gates.yml test, not by this function.
 */
export function gateWorkflowProblems(root) {
  const problems = [];
  const add = (line, message) => problems.push(`Line ${line}: ${message}`);
  for (const e of root.entries.values()) {
    if (!GATE_WORKFLOW_KEYS.includes(e.key)) add(e.line, `The Gates workflow sets ${e.key}:. It may set only ${series(GATE_WORKFLOW_KEYS)}.`);
  }
  const on = root.entries.get('on');
  const triggers = on?.value.kind === 'map' ? on.value.entries : new Map();
  const required = `branches: [${GATE_BRANCHES.join(', ')}]`;
  for (const name of GATE_FILTERED_TRIGGERS) {
    const trigger = triggers.get(name), filters = trigger?.value.kind === 'map' ? trigger.value.entries : new Map();
    for (const e of filters.values()) {
      if (e.key !== 'branches') add(e.line, `Trigger ${name} sets ${e.key}:. A Gates trigger may set only ${required}.`);
    }
    const branches = filters.get('branches');
    if (!branches) add(trigger?.line ?? on?.line ?? root.line, `Trigger ${name} does not set ${required}.`);
    else if (branches.value.kind !== 'seq' || branches.value.items.length !== GATE_BRANCHES.length ||
      branches.value.items.some((item, i) => item.kind !== 'scalar' || item.value !== GATE_BRANCHES[i])) {
      add(branches.line, `Trigger ${name} sets branches: to ${flow(branches.value)}. It must set ${required}.`);
    }
  }
  const dispatch = triggers.get('workflow_dispatch');
  if (dispatch?.value.kind === 'map') for (const e of dispatch.value.entries.values()) add(e.line, `Trigger workflow_dispatch sets ${e.key}:. It may set nothing.`);
  else if (dispatch && dispatch.value.kind !== 'null') add(dispatch.line, `Trigger workflow_dispatch is set to ${flow(dispatch.value)}. It may set nothing.`);
  const jobs = root.entries.get('jobs');
  if (jobs?.value.kind !== 'map') { add(jobs?.line ?? root.line, 'The Gates workflow has no jobs mapping.'); return problems; }
  for (const [id, job] of jobs.value.entries) {
    if (job.value.kind !== 'map') { add(job.line, `Job ${id} is not a mapping.`); continue; }
    for (const e of job.value.entries.values()) {
      if (!GATE_JOB_KEYS.includes(e.key)) add(e.line, `Job ${id} sets ${e.key}:. A Gates job may set only ${series(GATE_JOB_KEYS)}.`);
    }
    const steps = job.value.entries.get('steps');
    if (steps?.value.kind !== 'seq') { add(job.line, `Job ${id} has no steps sequence.`); continue; }
    for (const step of steps.value.items) {
      if (step.kind !== 'map') { add(step.line, `A step of job ${id} is not a mapping.`); continue; }
      const uses = step.entries.get('uses'), run = step.entries.get('run');
      if (uses) {
        if (uses.value.kind !== 'scalar') { add(uses.line, `A step of job ${id} sets uses: to something other than a scalar.`); continue; }
        const action = uses.value.value.split('@')[0].toLowerCase(), inputs = GATE_ACTIONS.get(action);
        const upload = action === 'actions/upload-artifact';
        if (!inputs) add(uses.line, `Job ${id} uses ${action}, which is not an accepted action.`);
        const keys = upload ? ['name', 'if', 'uses', 'with'] : ['name', 'uses', 'with'];
        for (const e of step.entries.values()) {
          if (e.key === 'if' && !upload) add(e.line, CONDITION_PROBLEM);
          else if (!keys.includes(e.key)) add(e.line, `The ${action} step of job ${id} sets ${e.key}:. An action step may set only ${series(keys)}.`);
        }
        const w = step.entries.get('with');
        if (w && w.value.kind !== 'map') add(w.line, `The ${action} step of job ${id} sets with: to something other than a mapping.`);
        else if (w && inputs) for (const e of w.value.entries.values()) {
          if (!inputs.includes(e.key)) add(e.line, `The ${action} step of job ${id} sets the input ${e.key}. That action accepts only ${series(inputs)}.`);
        }
        if (!upload) continue;
        const condition = step.entries.get('if');
        if (!condition) add(uses.line, `An upload-artifact step of job ${id} must set if: ${UPLOAD_CONDITION}.`);
        else if (condition.value.kind !== 'scalar' || condition.value.value !== UPLOAD_CONDITION) add(condition.line, CONDITION_PROBLEM);
        const given = w?.value.kind === 'map' ? w.value.entries : new Map();
        for (const [input, value] of UPLOAD_INPUTS) {
          const e = given.get(input);
          if (!e) add(uses.line, `The ${action} step of job ${id} does not set ${input}. It must set ${input}: ${value}.`);
          else if (e.value.kind !== 'scalar' || e.value.value !== value) add(e.line, `The ${action} step of job ${id} sets ${input} to ${flow(e.value)}. It must set ${input}: ${value}.`);
        }
      } else if (run) {
        for (const e of step.entries.values()) {
          if (e.key === 'if') add(e.line, CONDITION_PROBLEM);
          else if (!GATE_RUN_KEYS.includes(e.key)) add(e.line, `A run step of job ${id} sets ${e.key}:. A run step may set only ${series(GATE_RUN_KEYS)}.`);
        }
        const command = run.value.kind === 'scalar' ? run.value.value : null;
        if (command === null || !GATE_COMMAND.test(command)) {
          add(run.line, `Job ${id} runs ${command === null ? '(not a scalar)' : JSON.stringify(command)}, which is not node tools/fairpane.mjs install-zig or node tools/fairpane.mjs run <gate>.`);
        }
      } else add(step.line, `A step of job ${id} sets neither run nor uses.`);
    }
    const gates = JOB_GATES.get(id);
    if (!gates) continue;
    const ran = steps.value.items.flatMap(step => {
      const run = step.kind === 'map' ? step.entries.get('run')?.value : undefined;
      const match = run?.kind === 'scalar' ? GATE_RUN.exec(run.value) : null;
      return match ? [match[1]] : [];
    });
    if (ran.join('\n') !== gates.join('\n')) {
      add(steps.line, `Job ${id} runs the gates ${ran.length ? series(ran) : '(none)'}. It must run ${series(gates)}, in that order.`);
    }
  }
  return problems;
}

/** Parse and check workflow text. Throws WorkflowParseError for syntax outside the accepted subset. */
export function checkWorkflow(text) { return workflowProblems(parseWorkflow(text)); }
