# The Fairpane assignment

## Assignment to the coding agent

Build Fairpane according to this repository's founding contract.
Treat this as an implementation program, not a request for another proposal.
Preserve the full engine and browser vision through every intermediate milestone.

Start with `AGENTS.md`, `docs/CHARTER.md`, and `docs/PRODUCT.md`.
Inspect `engineering/HANDOFF.md`, `engineering/plan.json`, and `engineering/state.json`.
Check the actual local tools before any claim about their availability.

Execute `FP-0001` first.
Check the bootstrap and compile its candidate Zig source with the pinned master compiler.
Fix actual incompatibilities against that compiler without silently switching to a stable release.
Record each command and its result.

Establish Git history when the local identity permits a truthful commit.
Keep work sequential when isolation cannot yet operate.
Do not invent an identity or overwrite an existing repository.

Use `.omp/agents` for bounded specialist tasks.
Use isolated workspaces for concurrent writes after the baseline exists.
Keep one integrator responsible for shared contracts.
Do not automatically apply worker patches before review.

Treat the supplied task graph as an initial frontier, not the complete definition of the project.
Decompose unimplemented workstreams into testable tasks as prerequisites become available.
Expand the graph without deleting the full-scope obligations in `engineering/qualification.json`.

Keep the JavaScript runtime first-party and Zig-native.
Exploit comptime, SIMD, layout control, and native specialization where evidence supports them.
Do not use another engine or host WebView as a delivery shortcut.
Do not leave JavaScript as an optional long-term substitute for complete browser support.

Implement a real native browser shell during the early vertical-slice work.
Write the shell in Rust, the first-party wrapper language, against the public embedding contract only.
Render the browser chrome with Fairpane itself, as a trusted document under its own engine owner.
Treat any capability that the shell needs and the contract lacks as a contract defect, not a private shortcut.
Use qualified, pinned crates only in the browser application, as `engineering/dependencies.json` allows.
Keep the wrapper crates first-party.
Build extensions after the first usable browser, as `docs/EXTENSIONS.md` sequences them.
Preserve address-bar identity, accessibility, permissions, and application workflows.
Do not end with only a headless library or static HTML demonstration.

Keep progress and evidence on disk after each meaningful checkpoint.
Continue authorized work instead of ending after architecture notes or skeleton files.
At an actual session boundary, write the exact next command and unresolved failures into `engineering/HANDOFF.md`.
Never describe that handoff as project completion.

## First response from the agent

Report the loaded contract files and detected tool versions.
Report the first selected task and its acceptance criteria.
Then execute the task in the same session.

## Completion rule

A stage is complete only when its frozen qualification contract has valid evidence.
The browser is not complete because its build succeeds or its window opens.
The initial archive intentionally fails the release gate.
