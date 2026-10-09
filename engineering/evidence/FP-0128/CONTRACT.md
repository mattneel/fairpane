# FP-0128 task contract

## Identity

Task ID: `FP-0128`, "Compile and run the FP-0082 subset on a generic bytecode interpreter".
Workstream: `javascript`.
Base: the commit that freezes this contract, after `FP-0082` is accepted at its Revision 2 head. That head is implementation `84ffa53` with amendments `c28afb0` and `f397d8d`, and amendment 3's comment change `1ecd24a`.
Prerequisite: `FP-0082`, accepted.
If a later FP-0082 revision changes its syntax tree, its diagnostics, its `Options`, or `parseScript`, the integrator re-checks this contract before freezing it, as the re-check decision below does for Revision 2.
A `fairpane-js` contract worker drafted this contract as the first slice of the `FP-0083` split. The root integrator decided its open questions, and this is revision 2 of the draft after the pre-freeze check `out/drafts/FP-0128-check.json`.
Assigned role: `fairpane-js`.
Authority: `routine-local-engineering`.
Required gates: `repo-check`, `controller-test`, `zig-fmt`, and `zig-test`.
Required reviewers: `fairpane-review` and `fairpane-spec`.

### Integrator decisions

- **Split.** `FP-0083` is split into `FP-0128` and `FP-0129`. `FP-0083` keeps its nine criteria word for word as the closing task and depends on both slices.
  - `FP-0128` carries FP-0083 criteria 1, 2, 3, 8, and 9 word for word. Through criterion 1 it also carries FP-0012 criterion 1.
  - `FP-0129` carries FP-0083 criteria 4 to 7.
- **ADR number.** Plan commit `4e65397` ("plan: name ADR 0012 for the bytecode tasks and route FP-0111 notes") renamed the record in FP-0128 criterion 4, FP-0083 criterion 8, and FP-0129 criterion 5 to architecture decision record 0012. ADR 0011 is `engineering/decisions/0011-concurrent-controller-tests.md`.
  - FP-0128 criterion 4 now reads "Record the bytecode format and the dispatch reference in architecture decision record 0012." (`engineering/plan.json:4273`). This contract carries it word for word.
  - The state notes of FP-0128 and FP-0083 record the rename.
- **Re-check against the FP-0082 Revision 2 parser.** The drafter re-read Revision 1, Revision 2, and Revision 2 amendments 1 to 3, together with the parser source at `9f1096d`, in these four areas. `9f1096d` is `2c85bd3` plus one plan-only commit, "plan: record plan review 14 and carry its note". Evidence step 1 records `git diff --stat 2c85bd3 HEAD -- src build.zig`. The re-check changed no expected line of this contract.
  - **E96 rows.** Revision 1 changed rows E96, E96a, E96b, and E96c (`src/js/parser.zig:2628-2631`). No FP-0128 row uses `()` or `(a,)` as a script. Case 15 compiles only sources that parse to a script. The census file's SHA-256 is still `0e5277cd3bad6676e588dd11e196231c95069088f45aa5e993eb947a962148c7` after Revisions 1 and 2 (`engineering/evidence/FP-0082/README.md:279, 416`), so the smoke files' `agree_valid` records stand.
  - **Parse writer.** `writeOutcome` now allocates its write stack and returns `WriteError = std.Io.Writer.Error || Allocator.Error` (`parser.zig:198-215`). `writeDiagnostic` writes the three diagnostic forms without allocating (`parser.zig:217-223`). `Engine.writeOutcome` never writes a syntax tree. It writes parse diagnostics through `parser.writeDiagnostic`, so its error set stays `std.Io.Writer.Error`, and rows B8 and case 17's parse lines are unchanged.
  - **Limiter.** The parser's `Limiter` refuses every resize and remap (`parser.zig:274-311`; vtable at `285`). So the parser's own allocations are deterministic under a failing allocator. This contract therefore names the backing allocator of every allocation-failure case (L6 and case 15).
    - FP-0082 spec review 3's note is folded in under "Default limits": a growing parser buffer briefly holds its old and new blocks, and `max_memory_bytes` counts both.
  - **Per-body name sets.** The parser keeps one VarDeclaredNames set per body nesting level (`seen`, `parser.zig:556-561`), a per-body `function_names` set (`565`), and `params_seen` (`568`). `declareVar` is at `1218-1221`. Revision 2 case 1 bounds each set by its body's own names. The 70,000-name rows of case 15 rely on this linear parse [INFERENCE: Revision 2 case 1 measured 10,000 names per set, not 70,000].
- **Size.** `FP-0128` stays one task. If its worker hits stop rule 8, the integrator splits it in two:
  - one slice holds code without functions, the realm, completions, and ToObject;
  - the other holds functions, cases 5 to 8, case 13 D3 and D4, and the FP-0082 obligations.
- **No native re-entry.** No native frame calls an ECMAScript function.
  - A call or construct from bytecode pushes a VM frame and continues the same dispatch loop.
  - Some operations must call user code: OrdinaryToPrimitive, an accessor's getter or setter, `InstanceofOperator`'s `%Symbol.hasInstance%` method, and every conversion inside a built-in. Such an operation records its state in a continuation frame and pushes the callee's frame. The loop resumes the continuation when the callee returns.
  - The FP-0011 `call` kernel keeps calling only built-in behaviors (`src/js/kernels.zig:191-194`; `src/js/runtime.zig:463-466`). It asserts that it never receives an ECMAScript function.
  - `FP-0087`'s callback methods and `FP-0089`'s getters and setters must follow this rule, and ADR 0012 says so.
- **Operand widths.** No compile limit exists beyond the parser's own limits. The width rule under "Bytecode format" holds every count and offset that a tree accepted by the parser can need.
- **Unimplemented standard globals.** Each name in the frozen list below gives the outcome `unsupported <name>` on lookup, distinct from a thrown ReferenceError.
- **Realm content.**
  - The realm includes `Object.prototype.toString` and `valueOf`, `Error.prototype.toString`, `Error.isError`, and `Function.prototype[%Symbol.hasInstance%]`.
  - Engine-created errors are realm-relative. Today `src/js/heap.zig:455` always uses the heap-wide `type_error_prototype`. The heap-wide FP-0011 intrinsic record stays for FP-0011's own tests.
- **Test262 smoke runs.** The 31 runs below are FP-0128 evidence. FP-0084's contract will record that they are not a selection. The harness files run as separate non-strict scripts in the realm, before the test. The runs change nothing in `specs/applicability/test262.json`.
- **Limit semantics.** A limit, an interrupt, or an `unsupported <name>` outcome skips every catch and finally block and leaves the realm usable.
- **Default limits.**
  - `max_frames` is 2^20, and `max_stack_bytes` is 256 MiB. The limit codes are `frames`, `stack`, and `cells`.
  - `max_stack_bytes` counts the logical bytes of live VM frames and registers, as ADR 0012 defines them, not the allocator blocks behind them.
  - Every case and evidence step uses the FP-0082 parser defaults (`parser.zig:34-38`).
  - A caller that tunes `Options.parse.max_memory_bytes` must allow for the Limiter counting a growing buffer's old and new blocks together (FP-0082 Revision 2 amendment 2; FP-0082 spec review 3 in the FP-0128 state notes).
- **Test-time budget.** There are two bounds.
  - FP-0128 adds at most 30 seconds to `zig build test` on the development host. Anything heavier runs in the recorded step `zig build js-vm-heavy`, outside the zig-test gate.
  - The first `Gates` run that contains the FP-0128 change must keep each zig-test step within FP-0098's bound of 400 seconds, two thirds of the 600,000 ms timeout (`engineering/gates.json:31-38`), on both Windows and Linux. The README reports both steps' durations.
  - FP-0098's accepted runs had their slowest zig-test steps at 221 s on Windows and 261 s on Linux (state.json FP-0098 notes).
  - Linux zig-test once reached its 600 s timeout at `0df569a`, in run 37991104261 attempt 1, with no known cause. The receipt is `engineering/evidence/ci/run-37991104261-attempt-1/linux-gate-receipts-unsigned-local-integrity-records-not-attestations/2026-10-09T21-05-34-879Z-zig-test-e061b527.log:24`, with `timed_out` true and `duration_ms` 600486.
  - That run passed on rerun (`engineering/evidence/ci/run-37991104261-rerun.log`), and a local WSL reproduction passed (`engineering/evidence/ci/run-37991104261-repro-linux.log:214`).
- **Out of scope here.** FP-0026's frontier decomposition owns proper tail calls and the legacy `caller` and `arguments` own properties. FP-0128 follows the specification text. FP-0084's runner classifies tail-call tests by feature.
- **Error messages.** Engine-thrown error messages stay unfrozen, and cases assert error constructors only.
- **Heap catalog lines.** Before `tests-before.log`, ADR 0012 lists every new heap kind and its layout. The worker records the resulting FP-0011 case 7 literal in `tests-before.log`. The README states the literal and diffs the implemented one against the ADR, and reviewers check both.
- **Frozen text.** The value text and the outcome text below are frozen now, and FP-0084 builds on them.
- **Compile census.** It is a required evidence step, and the integrator's independent count stays.
- **Symbol and BigInt wrappers.** Host-API tests of these wrappers suffice.

## Sources

**ECMA-262.** The ECMA-262 draft is the multipage edition at <https://tc39.es/ecma262/multipage/>, retrieved 2026-10-09, with Annex B. At freeze, the integrator records its SHA-256 and headings (freeze step 2). Section numbers follow that edition:
- 6.2.4 Completion Records, UpdateEmpty; 6.2.5 Reference Records (GetValue 6.2.5.5, PutValue 6.2.5.6, GetThisValue).
- 7.1.1 ToPrimitive, 7.1.1.1 OrdinaryToPrimitive, 7.1.18 ToObject, 7.2.3 IsCallable, 7.2.4 IsConstructor, 7.3.21 OrdinaryHasInstance, IsLooselyEqual, IsStrictlyEqual, IsLessThan.
- 8.4.1 HasName, 8.4.2 IsFunctionDefinition, 8.4.3 IsAnonymousFunctionDefinition, 8.4.4 IsIdentifierRef, 8.4.5 NamedEvaluation (including the ParenthesizedExpression rule), 8.6.4 AssignmentTargetType.
- 9.1.1.1 Declarative Environment Records; 9.1.1.3 Function Environment Records; 9.1.1.4 Global Environment Records with 9.1.1.4.13 to 9.1.1.4.17; 9.1.2.1 to 9.1.2.5.
- 9.3.1 InitializeHostDefinedRealm, 9.3.2 CreateIntrinsics, 9.3.3 SetDefaultGlobalBindings; 9.4.2 to 9.4.6.
- 10.1 ordinary internal methods, including 10.1.9.2 OrdinarySetWithOwnDescriptor; 10.2.1 [[Call]] with 10.2.1.1, 10.2.1.2, and 10.2.1.4; 10.2.2 [[Construct]]; 10.2.3 OrdinaryFunctionCreate; 10.2.4 AddRestrictedFunctionProperties and 10.2.4.1 %ThrowTypeError%; 10.2.5 MakeConstructor; 10.2.9 SetFunctionName; 10.2.10 SetFunctionLength; 10.2.11 FunctionDeclarationInstantiation.
- 10.3 built-in function objects; 10.4.3 String exotic objects with 10.4.3.1 to 10.4.3.5.
- 13.1.3, 13.2.1 to 13.2.9, 13.3.2 to 13.3.6 (EvaluateNew, EvaluateCall), 13.4.2 to 13.4.5, 13.5 (`delete`, `void`, `typeof`, and the unary operators), 13.6 to 13.14, 13.10.2 InstanceofOperator, 13.15.2, 13.15.3 ApplyStringOrNumericBinaryOperator, 13.16.
- 14.1 to 14.10 and 14.12 to 14.16, with LoopContinues, ForBodyEvaluation, CaseBlockEvaluation, LabelledEvaluation, CatchClauseEvaluation, and the TryStatement evaluation.
- 15.2.4 InstantiateOrdinaryFunctionObject, 15.2.5 InstantiateOrdinaryFunctionExpression, 15.2.6.
- 16.1.4 to 16.1.7 (Script Records, ScriptEvaluation, GlobalDeclarationInstantiation).
- 19 The Global Object: 19.1 to 19.4, which give the global property names. Also 20.1.3.6 and 20.1.3.7; 20.2.3, 20.2.3.5, 20.2.3.6, and 20.2.4; 20.5.1 to 20.5.6.
- Annex B.2.1 (`escape`, `unescape`), B.3.4, and B.3.9 Runtime Errors for Function Call Assignment Targets.

**Test262.** Test262 is pinned at `2e0a56762801e275a9fdf96dc49d90ba0cddcf63`.
- From `INTERPRETING.md`: "Test262-Defined Bindings", "Strict Mode", "Test Results", and `negative`.
- The harness files `assert.js` and `sta.js`, with the blob IDs that the FP-0082 contract lists.

**FP-0082 contract and README.** Cite `engineering/evidence/FP-0082/CONTRACT.md` with its amendments 1 and 2, Revision 1 with its amendments 1 and 2, and Revision 2 with its amendments 1 to 3. Cite `engineering/evidence/FP-0082/README.md` as well.

**Other sources.** `engineering/evidence/FP-0011/CONTRACT.md`, ADR 0008, and `docs/JAVASCRIPT_RUNTIME.md`.

### Observed facts that shaped the decisions

The drafter read the working tree at `9f1096d`, which is `2c85bd3` plus one plan-only commit, and evidence step 1 records `git diff --stat 2c85bd3 HEAD -- src build.zig`. Evidence step 1 records each cited window at the base with `git show`. None of these facts is a test input.

- **Syntax tree.**
  - The tree keeps `paren` nodes (`src/js/ast.zig:162`) and function source ranges (`ast.zig:35-37`). It does not keep the source text, so the runtime must copy the source for `[[SourceText]]`.
  - `checkTarget` unwraps parentheses and accepts a call target only in non-strict code (`src/js/parser.zig:1923-1932`). So `(f()) = 1` reaches the runtime in non-strict code.
  - The parser deduplicates var names with one hash set per body nesting level (`parser.zig:556-561`, `declareVar` at `1218-1221`), as FP-0082 Revision 2 reworked them.
  - The parser's `Options` bound nesting depth, memory, and source length (`parser.zig:34-38`). They bound neither the number of arguments nor the number of parameters. FP-0082 Revision 1 case 4 parses 10,000 parameters, and Revision 2 case 1 parses 10,000 var declarations.
- **Heap.**
  - Property lookup is a linear scan (`src/js/heap.zig:412-415`). Tests therefore keep global property counts small; only function-local names scale to 70,000.
  - FP-0011 creates `%Function.prototype%` as an ordinary, non-callable object (`heap.zig:209`). It makes TypeErrors with the heap-wide prototype (`heap.zig:455`).
  - At the cell limit and at the end of the representation's cell index space (`max_cell_index`), `allocateCell` returns `error.OutOfMemory` (`heap.zig:266-273`). FP-0011 case 15 freezes that (`heap.zig:1102`).
  - FP-0011 case 14 runs `checkAllAllocationFailures` over a `testing.FailingAllocator` with `.resize_fail_index = 0` and asserts `allocated_bytes == freed_bytes` (`heap.zig:1093-1100`). With that setting, the pinned `FailingAllocator` fails every resize and remap (`.tools/zig/0.18.0-dev.120+9fe22a29b/x86_64-windows/lib/std/testing/FailingAllocator.zig:81-110`).
  - FP-0011 case 7 freezes the heap catalog literal (`src/js/heap_catalog.zig:393-407`, test at `409-416`), whose eight kinds are the `Kind` enum at `heap_catalog.zig:15-24`.
- **Built-in calls.** The `call` kernel runs only built-in behaviors, and it reads `payload.builtin_function` (`kernels.zig:191-194`, `runtime.zig:466`).
- **Native stack.** The FP-0082 stack-painting helper and `runOnSmallStack` are at `parser.zig:2978-3053`. FP-0082 measured a 21 KB native stack baseline for parsing (FP-0082 README, "Stop rules").
- **Test262.** Evidence step 1 records each of these facts.
  - The seven files whose `esid` is `sec-runtime-errors-for-function-call-assignment-targets` are all under `test/annexB/language/expressions/assignmenttargettype/`. All seven are `unsupported` in the FP-0082 census:
    - six at `method_definition`, because each uses `valueOf() {}` (for example `callexpression.js:22`);
    - `cover-callexpression-and-asyncarrowhead.js` at `for_in @992`.
    So FP-0128 covers B.3.9 with hand-written rows. Row B9 repeats that file's `async() = 1`, which the census shows the parser accepts before offset 992.
  - `fn-name-lhs-cover.js:18`, `fn-name-cover.js:22`, and `fn-name-lhs-member.js:18` under `test/language/expressions/assignment/` include `propertyHelper.js`. The FP-0082 README reports `unsupported array_literal @2981` for that file (README line 67).
  - `test/built-ins/Function/prototype/toString/function-declaration.js:7` includes `nativeFunctionMatcher.js`, which uses arrow functions (`harness/nativeFunctionMatcher.js:26`). So FP-0128 covers name inference and `toString` with hand-written rows.
  - The 16 smoke files below are recorded as `agree_valid` in every run mode in `out/fp0082-census.jsonl`, whose SHA-256 the FP-0082 README gives as `0e5277cd3bad6676e588dd11e196231c95069088f45aa5e993eb947a962148c7` (lines 73 and 416).
  - In `harness/assert.js`, the listed names `JSON`, `String`, `Object`, and `Array` appear only at lines 27, 29, 36, 44, 47, 155, 157, 163, and 179. These lines are inside `formatIdentityFreeValue`, `formatSimpleValue`, `assert.compareArray`, and `compareArray.format`. Of those, `assert`, `assert.sameValue`, and `assert.throws` reach only `formatSimpleValue`, and only on their failure branches.
  - `harness/sta.js` uses no listed name.
  - The 15 smoke files that are expected to pass reference no listed name, and `native-call.js` references `Function` on its first statement. [INFERENCE: read by the drafter; evidence step 1 records the search.]

## Behavior

### Files

The names give the intended shape. The worker may refine them without changing behavior.

| File | Content |
| --- | --- |
| `src/js/bytecode.zig` | Opcode catalog, operand kinds, code records, `verify`, `writeCode`. |
| `src/js/compiler.zig` | Syntax tree to bytecode, with an explicit stack and a function worklist. |
| `src/js/interpreter.zig` | The generic dispatch loop, VM frames, calls, continuations, and unwinding. |
| `src/js/environment.zig` | Global, function, and declarative environment records. |
| `src/js/realm.zig` | Realm records, intrinsics, the global object, the built-ins, and `unimplemented_globals`. |
| `src/js/engine.zig` | `Engine(r)`, outcomes, the value writer, and host calls. |
| `src/js/vm_tests.zig` | Cases 1 to 20, compiled as a separate test binary. |
| `src/js/vm_heavy_tests.zig` | The `js-vm-heavy` cases. |
| `src/js/run_main.zig` | The `fairpane-js-run` executable root. |
| `src/js/heap_catalog.zig`, `heap.zig`, `runtime.zig`, `kernels.zig` | New kinds, VM roots, property removal, the recorded cause of a cell-limit failure, and realm-relative engine errors. |
| `src/js/value.zig` | FP-0011 case 20 (`value.zig:143-166`) lists the new files. |
| `build.zig` | `js-tools` also installs `fairpane-js-run`. It adds the case 17 run steps, the separate test binary, and the `js-vm-heavy` step. |
| `tests/js/run/*` | Command-line fixtures. |
| `engineering/decisions/0012-javascript-bytecode-and-dispatch.md` | ADR 0012. |

The heap keeps returning `error.OutOfMemory` at the cell limit, as FP-0011 case 15 freezes. It also records that the cell limit or the representation's cell index space (`max_cell_index`) caused that failure, as the parser's `Limiter.exceeded` does (`parser.zig:279, 294`). The engine maps that record to `limit cells`, and it maps every other `error.OutOfMemory` to the `gpa` failure.
No new file under `src/js` contains `export `, `callconv(`, `extern struct`, or `extern union`.
The task changes nothing under `include` or `api`, and it changes neither `src/c_api.zig` nor `src/abi_generated.zig`.

### Interface

```zig
pub fn Engine(comptime r: Representation) type {
    return struct {
        pub const Options = struct {
            heap: Rt.Heap.Options = .{},
            parse: parser.Options = .{},
            /// Frames on the VM stack: one per script evaluation, per ECMAScript [[Call]] or
            /// [[Construct]], and per continuation frame.
            max_frames: u32 = 1 << 20,
            /// Logical bytes of live VM frames and registers, as ADR 0012 defines them.
            max_stack_bytes: usize = 256 * 1024 * 1024,
        };
        pub const Realm = enum(u32) { _ };
        pub const LimitCode = enum { frames, stack, cells };
        pub const Outcome = union(enum) {
            normal: Root,            // a persistent root until `release`
            throw: Root,
            parse: parser.Diagnostic,
            limit: LimitCode,
            unsupported: []const u8, // a name from `realm.unimplemented_globals`
        };
        pub fn init(gpa: Allocator, options: Options) error{OutOfMemory}!Self;
        pub fn deinit(engine: *Self) void;
        pub fn createRealm(engine: *Self) error{OutOfMemory}!Realm;
        pub fn evaluateScript(engine: *Self, realm: Realm, source: []const u16) error{OutOfMemory}!Outcome;
        pub fn call(engine: *Self, function: Value, this: Value, args: []const Value) error{OutOfMemory}!Outcome;
        pub fn defineGlobal(engine: *Self, realm: Realm, name: []const u16, value: Value) error{OutOfMemory}!void;
        pub fn globalObject(engine: *const Self, realm: Realm) Value;
        pub fn release(engine: *Self, outcome: *Outcome) void;
        pub fn writeOutcome(engine: *Self, outcome: Outcome, writer: *std.Io.Writer) std.Io.Writer.Error!void;
    };
}
```

- `error.OutOfMemory` means that `gpa` failed. The engine stays valid for `deinit`.
- `limit cells` means that an allocation found the live cell count at `Options.heap.max_cells` after a collection, or found the representation's cell index space (`max_cell_index`) full.
- `defineGlobal` defines a data property with Writable true, Enumerable false, and Configurable true.
- The interpreter reaches the heap only through `Runtime(r)` contexts or as the runtime's owner, as ADR 0008 §1 allows.
- Every new heap primitive declares its effects. Every FP-0011 compile-fail fixture still passes.

### Outcome and value text

This text is frozen, and FP-0084 builds on it.
`writeOutcome` writes one line without a terminator, in one of these forms:

- `normal <value>` or `throw <value>`;
- `limit frames`, `limit stack`, or `limit cells`;
- `unsupported <name>`, for an unimplemented standard global;
- for a parse diagnostic, the text of `parser.writeDiagnostic` (`parser.zig:217-223`): `syntax-error <code> @<offset>`, `unsupported <code> @<offset>`, or `limit <code> @<offset>`.

`<value>` is one of the following:

- `undefined`, `null`, `true`, or `false`;
- `number <Number::toString(x)>`, except that negative zero is written `number -0`;
- `string "<units>"`, escaped as in FP-0082's `writeString`;
- `symbol`, or `bigint <decimal>`;
- `function`, for a callable object;
- `error <Name>`, for an object with [[ErrorData]] whose [[Prototype]] is `%Name.prototype%` of one of the engine's realms, with Name in Error, TypeError, or ReferenceError;
- `error`, for any other object with [[ErrorData]];
- `object`, for any other object.

The writer runs no user code.

### Bytecode format

These rules are normative. ADR 0012 records the full opcode list.

- **Machine model.** The machine is register-based. A frame owns `register_count` Value slots, each initialized to undefined. Non-Value state lives in typed frame fields.
- **Opcode catalog.** The catalog is a Zig declaration in `bytecode.zig`, in the operation-catalog style of ADR 0008 §1. Each entry gives:
  - its name;
  - its operand kinds;
  - an upper bound of its `operations.Effects`, checked by the ADR 0008 rules;
  - the flags `jump`, `terminator`, and `calls_user_code`.
- **Encoding.** An instruction is a `u8` opcode followed by its operands, little-endian and unaligned. The operand kinds and their widths are:
  - `reg`: u32;
  - `count`: u32;
  - `const`, `name`, and `function`: u32;
  - `jump`: i64, relative to the start of the next instruction;
  - `imm`: u8, which holds only enumerations such as an operator or a completion type, never a count or an index.
- **Width rule.** No operand that holds a count, an index, or a code offset is narrower than 32 bits. Every such count and index fits in u32, for this reason:
  - Every count and index of a code record is at most the length in code units of that record's source range, which is a u32 (`ast.zig:35-37`). The compiler allocates at most one register, constant, name, nested function, handler entry, or argument slot per code unit of the range, and it frees each temporary register before it allocates for a later sibling. A record may also use a fixed number K of slots that ADR 0012 states, so each count is at most max(range length, K), which still fits in u32 because both terms do.
  - ADR 0012 shows that per-code-unit bound for every syntax form of the FP-0082 subset.
  - Jump offsets are i64, so no code record is too long to encode.
  - A code record stores its bytecode length and every handler range as `usize`.
- **Code record.** A code record holds:
  - the bytecode;
  - a constant pool of Numbers and Strings, which are traced;
  - a name pool;
  - nested function templates;
  - a handler table of try ranges, each with its catch or finally entry;
  - the source range;
  - the parameter count;
  - the register count;
  - strictness;
  - the kind: script or function.
- **Verifier.** `verify(code)` checks the following:
  - every operand is in range;
  - every jump lands on an instruction start inside the code;
  - handler ranges are well formed and properly nested;
  - the last instruction is a terminator.
- **Disassembler.** `writeCode` writes one line per instruction, `<pc> <name> <operands>`, with operands written as `r<n>`, `k<n>`, `n<n>`, `f<n>`, `@<target pc>`, and `#<n>`. Its output is deterministic.
- **Limits.** No syntax tree that FP-0082 accepts yields a compile limit or a compile error. Case 15 holds functions with 70,000 parameters, 70,000 arguments, and 70,000 var names, each beyond 65,535.

### Compiler

- The compiler walks the tree with an explicit heap stack of at most `max_depth` frames, as `ast.writeScript` does. It compiles nested functions from a worklist. It never recurses once per tree level or once per function level.
- Some names may resolve at compile time, because FP-0128 has no `with` statement and no direct `eval`: parameters, `var` names, function declarations, a catch parameter, and a named function expression's own name.
- Global names resolve at run time through the Global Environment Record.
- Compile time and memory are linear in the size of the tree.

### Interpreter loop and native stack

- **Dispatch reference.** `interpreter.run` is the generic reference, and ADR 0012 records it as the reference that FP-0085 compares against. It is one loop that fetches an opcode and runs an exhaustive `switch` over the catalog. It uses no computed goto, no threaded dispatch, no superinstructions, and no inline caches.
- **Calls.**
  - A call or construct of an ECMAScript function pushes a frame and continues the loop.
  - A built-in behavior is called natively, and it never calls an ECMAScript function.
  - An operation that calls user code uses a continuation frame.
- **Native stack.** The native stack does not grow with syntax nesting, with ECMAScript call depth, or with the depth of nested conversions or built-in calls.
- **Unwinding** is iterative and uses the handler tables.
- **Tracing.** The heap tracer visits the VM stack, the realms, and the code records without recursion.
- **ADR 0012** records the native stack bytes that case 13 measures: D1 to D5 and the compile-only probe.

### Completion records

- Each statement follows its ECMA-262 Evaluation steps, including UpdateEmpty, LoopContinues, the conversion of `break` in LabelledEvaluation, CaseBlockEvaluation, and the three TryStatement forms.
- A `break` or `continue` that leaves a `try` or `finally` region passes through each enclosing `finally` with a recorded completion {type, value, target}. So does every `return` and `throw`.
- When a `finally` block completes normally, the recorded completion resumes.
- ScriptEvaluation turns an empty normal completion into undefined (16.1.6 step 13).

### Environment records and declaration instantiation

- **Global Environment Record.** Implement it as 9.1.1.4 specifies:
  - [[ObjectRecord]] over the global object;
  - [[GlobalThisValue]];
  - an empty [[DeclarativeRecord]];
  - the operations HasLexicalDeclaration, HasRestrictedGlobalProperty, CanDeclareGlobalVar, CanDeclareGlobalFunction, CreateGlobalVarBinding, and CreateGlobalFunctionBinding.
- **GlobalDeclarationInstantiation** (16.1.7) uses FP-0082's `functions_to_initialize` and `var_declared_names`. A failed check throws before any binding exists.
- **Function Environment Records** (9.1.1.3, 9.1.2.4) hold [[ThisValue]], [[ThisBindingStatus]], [[FunctionObject]], and [[NewTarget]].
- **FunctionDeclarationInstantiation** (10.2.11) creates the parameters (including duplicates in non-strict code), the var bindings, and the function declarations.
  - No arguments object is ever needed, because FP-0082 reports `arguments_object` unless a parameter or a function declaration is named `arguments`.
- **Declarative records** serve each catch clause (14.15.2) and each named function expression's own binding (15.2.5).
- **Block environments** cannot be observed without lexical declarations, so they may be omitted. ADR 0012 says so, and FP-0086 must add them.

### Functions

- **Creation.** OrdinaryFunctionCreate, MakeConstructor, SetFunctionName, and SetFunctionLength apply, with ExpectedArgumentCount equal to the parameter count. Every FunctionDeclaration and FunctionExpression is a constructor with a `prototype` property.
- **[[Call]]** follows 10.2.1, including OrdinaryCallBindThis with ToObject for a non-strict callee.
- **[[Construct]]** follows 10.2.2. OrdinaryCreateFromConstructor runs before the frame is pushed, and the result rules of steps 12 to 14 apply.
- **EvaluateCall and EvaluateNew** evaluate the arguments before the callable and constructor checks.
- **Not implemented.** Following the specification text, FP-0128 has no proper tail calls and adds no own `caller` or `arguments` property to functions. FP-0026's frontier decomposition owns both.

### Realm and intrinsics

Every built-in function has the following:
- [[Prototype]] equal to the realm's `%Function.prototype%`;
- `length` and `name` with Writable false, Enumerable false, and Configurable true;
- [[InitialName]] equal to its name.

Methods have Writable true, Enumerable false, and Configurable true.

| Intrinsic | Content |
| --- | --- |
| `%Object.prototype%` | [[Prototype]] null; methods `toString` (20.1.3.6) and `valueOf` (20.1.3.7). |
| `%Function.prototype%` | A built-in function that returns undefined (20.2.3), with [[Prototype]] `%Object.prototype%`; not a constructor. Properties: `length` 0; `name` ""; the method `toString` (20.2.3.5); the method `[%Symbol.hasInstance%]`, with all attributes false and name "[Symbol.hasInstance]"; and the `caller` and `arguments` accessors, whose getter and setter are `%ThrowTypeError%` (10.2.4, 9.3.2 step 3). |
| `%ThrowTypeError%` | Anonymous; [[Extensible]] false; `length` and `name` with all attributes false. |
| `%Error%` | A constructor with [[Prototype]] `%Function.prototype%`, `length` 1, `name` "Error", `prototype` with all attributes false, and the method `isError` (20.5.2.1). |
| `%Error.prototype%` | `constructor`, `message` "", `name` "Error", and the method `toString` (20.5.3.4). |
| `%TypeError%`, `%ReferenceError%` | As 20.5.6 gives them: [[Prototype]] `%Error%`, `length` 1, `name`, and `prototype`. Their prototypes have [[Prototype]] `%Error.prototype%`, `constructor`, `message` "", and `name`. |
| `%Boolean.prototype%`, `%Number.prototype%` | Ordinary objects with [[BooleanData]] false and [[NumberData]] +0. |
| `%String.prototype%` | A String exotic object with [[StringData]] "" and `length` 0. |
| `%Symbol.prototype%`, `%BigInt.prototype%` | Ordinary objects. |
| Global object | Ordinary, extensible, with [[Prototype]] `%Object.prototype%`. Its own properties, in this order: `globalThis` (Writable true, Enumerable false, Configurable true); `Infinity`, `NaN`, and `undefined` (all attributes false); and `Error`, `ReferenceError`, and `TypeError` (Writable true, Enumerable false, Configurable true). |

- The wrapper prototypes have no `constructor` and no methods, because their constructors are not implemented yet.
- `Function.prototype.toString` of a built-in returns exactly `function <InitialName>() { [native code] }`.
- `%Error%` and `%NativeError%` run 20.5.1.1 and 20.5.6.1.1, including InstallErrorCause. Their ToString(message) uses continuation frames.
- `Error.prototype.toString` uses continuation frames for its ToString of `name` and `message`.

### Unimplemented standard globals

`realm.zig` declares `unimplemented_globals`, which is this frozen list of 57 names, in this order. The list is the 64 global property names of clauses 19.1 to 19.4 (4 + 9 + 45 + 4) and Annex B.2.1 (2) of the retrieved draft, minus the seven that the realm implements. Freeze step 2 records those headings.

- 19.2: `eval`, `isFinite`, `isNaN`, `parseFloat`, `parseInt`, `decodeURI`, `decodeURIComponent`, `encodeURI`, `encodeURIComponent`.
- 19.3: `AggregateError`, `Array`, `ArrayBuffer`, `AsyncDisposableStack`, `BigInt`, `BigInt64Array`, `BigUint64Array`, `Boolean`, `DataView`, `Date`, `DisposableStack`, `EvalError`, `FinalizationRegistry`, `Float16Array`, `Float32Array`, `Float64Array`, `Function`, `Int8Array`, `Int16Array`, `Int32Array`, `Iterator`, `Map`, `Number`, `Object`, `Promise`, `Proxy`, `RangeError`, `RegExp`, `Set`, `SharedArrayBuffer`, `String`, `SuppressedError`, `Symbol`, `SyntaxError`, `Uint8Array`, `Uint8ClampedArray`, `Uint16Array`, `Uint32Array`, `URIError`, `WeakMap`, `WeakRef`, `WeakSet`.
- 19.4: `Atomics`, `JSON`, `Math`, `Reflect`.
- B.2.1: `escape`, `unescape`.

These rules apply:
- **Trigger.** Evaluating an IdentifierReference (13.1.3) may give an unresolvable Reference Record from ResolveBinding. If its StringValue is on the list, evaluation stops with the outcome `unsupported <name>`. This happens before any GetValue, PutValue, `typeof`, `delete`, or call uses the reference.
- **Unwinding.** The outcome unwinds as a limit does: no catch or finally block runs, and the realm stays usable.
- **Resolvable bindings.** A resolvable binding of a listed name follows ordinary semantics. Examples are a `var`, a function declaration, and a global property that a script created.
- **Property access.** A property access such as `globalThis.Array` is not an identifier reference, and it is not intercepted.
- **Maintenance.** Each later task that implements a listed global removes its name from the list in the same change.

### ToObject and primitive wrappers

- ToObject follows 7.1.18.
  - It throws TypeError for undefined and null.
  - It wraps Booleans, Numbers, Symbols, and BigInts with the realm's prototypes.
  - It makes String exotic objects with 10.4.3.1 to 10.4.3.5 and StringCreate. A String object's `length` is an own data property with all attributes false.
- GetValue and PutValue (6.2.5.5, 6.2.5.6) call ToObject before ToPropertyKey.
- A Set through a primitive receiver returns false, which throws TypeError only in strict code.
- Symbols and BigInts cannot reach scripts yet, so their wrappers are tested through the host API.

### FP-0082 obligations

- **Name inference.** NamedEvaluation applies in these places:
  - a VariableDeclaration initializer;
  - an `=` assignment whose left side is an IdentifierRef, never a parenthesized one;
  - a `PropertyName : AssignmentExpression` that is not the `__proto__` setter form;
  - through ParenthesizedExpression (8.4.5).
  It never applies through a comma expression.
- **B.3.9.** In non-strict code, an `=` assignment, a compound assignment, and every update form throw ReferenceError right after the call target is evaluated. These are 13.15.2 step 1.b, step 2 of 13.4.2 to 13.4.5, and step 2 of the compound form.
- **Function.prototype.toString.** [[SourceText]] is the recorded range, from `function` through `}`, taken from a runtime copy of the script source.

### Limits and abrupt outcomes

- **Frame limit.** Pushing a frame when `max_frames` frames already exist gives `limit frames`.
- **Stack limit.** When the logical bytes of live VM frames and registers would exceed `max_stack_bytes`, the outcome is `limit stack`.
- **Cell limit.** The cell limit and the full cell index space of the representation (`max_cell_index`) give `limit cells`. Any other `error.OutOfMemory` is the `gpa` failure.
- **Unwinding.** A limit or an `unsupported <name>` outcome unwinds without running any catch or finally block.
- **Uncaught exceptions.** An uncaught exception gives `throw`.
- **Engine-thrown errors.** Their messages are implementation-defined and not frozen. Cases assert only their constructors.

### Command line

`zig build js-tools` also installs `fairpane-js-run`.

- **`fairpane-js-run file <path>...`** creates one realm, evaluates each UTF-8 file as its own Script in order, and writes one `writeOutcome` line per script. It stops at the first outcome that is not normal.
  - Exit status 0 means that every outcome was normal.
  - 1 means a syntax error.
  - 2 means unsupported, from the parser or from an unimplemented global.
  - 3 means an input or usage error.
  - 4 means a limit, from the parser or from the runtime.
  - 5 means a throw.
- **`fairpane-js-run compile-census <extract-root>`** parses every discovered non-module file in each mode by the FP-0082 census rules, without running anything. It compiles and verifies every script.
  - Its summary line has the keys `discovered`, `module`, `runs`, `scripts`, `compiled`, `compile_failures`, and `limits`.
  - It exits with status 0 only when `scripts` equals `compiled` and both other counts are 0.
- **`fairpane-js-run test262-smoke <extract-root>`** checks the commit in `EXTRACT.json` and runs each run of the list below in a fresh realm.
  - It evaluates `harness/assert.js` and then `harness/sta.js`, each as a separate non-strict script.
  - It then evaluates the test, prefixed with `"use strict";` and U+000A for a strict run.
  - A run passes when the test completes normally.
  - A run with `negative: {phase: runtime, type: T}` passes when the test throws an object whose `constructor.name` is the String T.
  - A run is `unsupported` when its outcome is an `unsupported` outcome. Any other run fails.
  - It writes one line per run, `<path> <mode> <pass|fail|unsupported> <outcome line>`, and then a summary line.
  - It exits with status 0 only when no run differs from its frozen expectation.

### Test262 smoke subset

Every file and run mode below is `agree_valid` in `out/fp0082-census.jsonl`, which evidence step 1 records.
"Both" means a non-strict run and a strict run.
The expected summary line is `{"runs":31,"pass":29,"unsupported":2,"fail":0,"mismatch":0}`.

| # | File | Modes | Expected | Derivation |
| --- | --- | --- | --- | --- |
| 1 | `test/language/statements/try/S12.14_A1.js` | both | pass | Try blocks complete normally (14.15.3), and the finally blocks run. |
| 2 | `test/language/statements/try/S12.14_A10_T1.js` | both | pass | `throw i` at i=5 is caught, and `e !== 5` is false. |
| 3 | `test/language/statements/try/S12.14_A13_T2.js` | both | pass | A finally completion overrides only when it is abrupt: return 1 (#1), throw (#4 to #6), and return 2 (#7, #8). `someValue` is not a listed name, so it throws ReferenceError (6.2.5.5). |
| 4 | `test/language/statements/switch/S12.11_A1_T1.js` | both | pass | CaseBlockEvaluation gives 6, 4, 56, 48, 64, and 32 for each value that matches nothing. |
| 5 | `test/language/statements/continue/S12.7_A9_T1.js` | both | pass | `continue FOR` runs from the catch block, and `return` runs at x === 10. |
| 6 | `test/language/statements/continue/12.7-1.js` | both | pass | `continue⏎;` is one statement, so `sum` stays 0, and `assert.sameValue(0, 0)` returns. |
| 7 | `test/language/identifier-resolution/S10.2.2_A1_T1.js` | both | pass | `f2` closes over `f1`'s `x`, which is 1. |
| 8 | `test/language/identifier-resolution/assign-to-global-undefined.js` | strict | pass | The left reference resolves before the right side runs (13.15.2 step 1.a). PutValue on the unresolvable strict reference then throws ReferenceError (6.2.5.6 step 2.a). |
| 9 | `test/language/expressions/addition/S11.6.1_A2.2_T1.js` | both | pass | OrdinaryToPrimitive tries valueOf, then toString, for the default hint. #8 throws a TypeError, and `e instanceof TypeError` is true. |
| 10 | `test/language/expressions/addition/S11.6.1_A2.3_T1.js` | both | pass | The left ToPrimitive runs first and throws "x" (13.15.3). |
| 11 | `test/language/expressions/new/S11.2.2_A3_T1.js` | both | pass | IsConstructor(true) is false, so the result is TypeError (13.3.5.1.1 step 5). |
| 12 | `test/language/expressions/typeof/get-value-ref-err.js` | both | pass | GetValue(x) throws ReferenceError, and `thrown.constructor === ReferenceError`. |
| 13 | `test/language/expressions/typeof/unresolvable-reference.js` | both | pass | `typeof` of an unresolvable reference is "undefined" (13.5.3.1). `x` is not a listed name. |
| 14 | `test/language/expressions/delete/member-identifier-reference-null.js` | both | pass | ToObject(null) throws TypeError. |
| 15 | `test/language/statements/function/S13.2.2_A9.js` | both | pass | `this.func` is undefined, so the call throws TypeError, which is not a Test262Error. |
| 16 | `test/language/expressions/typeof/native-call.js` | both | unsupported: `unsupported Function` | `Function` is a listed name, and its binding is unresolvable. |

## Exact test cases

- Every case runs in a fresh engine and realm unless it says otherwise.
- Sources are shown as raw JavaScript.
- `⏎` is U+000A, and `<CR>` is U+000D.
- `⟫` separates scripts evaluated in order in one realm. The expected lines follow in the same order.
- Each row expects exactly the `writeOutcome` line shown.

Every case fails before the change:
- The new test files fail to compile, because `src/js/engine.zig` and its siblings do not exist.
- The case 18 update fails, because `heap_catalog.zig:393-407` renders only the eight kinds of `heap_catalog.zig:15-24`.
- FP-0011 case 20's new `@embedFile` entries (`value.zig:143-166`) fail to compile.

Every source here parses to a script under the FP-0082 Revision 2 parser unless the row says otherwise [INFERENCE: checked against the FP-0082 subset table, not by running the parser]. See stop rule 3.
Unless a row says otherwise, no identifier in these sources is in `unimplemented_globals`. `nope` is used as an undeclared name that is not on the list.

Cases 1 to 20 run in `zig build test`. The `js-vm-heavy` step runs two extensions:
- the stress pass of case 14 for the four configurations other than `reference`;
- the full 50,000 random sources of case 15. The first 5,000 of them also run in `zig build test`.

Every `std.testing.checkAllAllocationFailures` call in these cases uses a `testing.FailingAllocator` with `.resize_fail_index = 0` as its backing allocator, and asserts afterward that its `allocated_bytes` equals its `freed_bytes`, as FP-0011 case 14 does (`heap.zig:1093-1100`).

**1. Catalog and verifier.** The opcode catalog passes its comptime validation. Every code record compiled in cases 3 to 15 passes `verify`.

**2. Value writer.** The host-built values undefined, null, true, -0, NaN, 1e21, the string `a"\b⏎`, a symbol, the BigInt 12, a plain object, a function, and `new TypeError()` give these lines, in order:

```text
undefined
null
true
number -0
number NaN
number 1e+21
string "a\"\\b\u000A"
symbol
bigint 12
object
function
error TypeError
```

**3. Expressions.**

```text
X1  1 + 2 ⇒ normal number 3
X2  "a" + 1.5 ⇒ normal string "a1.5"
X3  1 + 2 + "3" ⇒ normal string "33"
X4  "3" * "4" ⇒ normal number 12
X5  -7 % 3 ⇒ normal number -1
X6  2 ** -1 ⇒ normal number 0.5
X7  0 * -1 ⇒ normal number -0
X8  1 / -0 ⇒ normal number -Infinity
X9  -1 >>> 0 ⇒ normal number 4294967295
X10 1 << 31 ⇒ normal number -2147483648
X11 -5 >> 1 ⇒ normal number -3
X12 (5 & 3) + "," + (5 | 3) + "," + (5 ^ 3) + "," + ~5 ⇒ normal string "1,7,6,-6"
X13 +"  12  " ⇒ normal number 12
X14 +"0x10" ⇒ normal number 16
X15 +"abc" ⇒ normal number NaN
X16 +"" + "," + +null + "," + +true + "," + +undefined ⇒ normal string "0,0,1,NaN"
X17 typeof null + "," + typeof undefined + "," + typeof nope + "," + typeof function () {} + "," + typeof {} + "," + typeof "s" + "," + typeof 1 + "," + typeof true ⇒ normal string "object,undefined,undefined,function,object,string,number,boolean"
X18 void 0 ⇒ normal undefined
X19 !"" + "," + !"0" + "," + !!NaN ⇒ normal string "true,false,false"
X20 (null == undefined) + "," + ("1" == 1) + "," + (true == 1) + "," + ("" == 0) + "," + (NaN == NaN) + "," + (null == 0) ⇒ normal string "true,true,true,true,false,false"
X21 (0 === -0) + "," + ("a" !== "a") + "," + (null === undefined) ⇒ normal string "true,false,false"
X22 ("B" < "a") + "," + ("10" < "9") + "," + ("10" < 9) + "," + (undefined < 1) + "," + (undefined >= 1) + "," + (null >= 0) ⇒ normal string "true,true,false,false,false,true"
X23 0 || "x" ⇒ normal string "x"
X24 1 && 0 ⇒ normal number 0
X25 null && nope() ⇒ normal null
X26 0 ? nope : "n" ⇒ normal string "n"
X27 (1, 2, 3) ⇒ normal number 3
X28 var a = 5; a -= 2; a *= 3 ⇒ normal number 9
X29 var a = 1; a++ + a ⇒ normal number 3
X30 var b = 1; ++b + b ⇒ normal number 4
X31 var o = {}; o.x = 1; o["y"] = 2; o.x + o.y ⇒ normal number 3
X32 var o = {a: 1}; delete o.a ⇒ normal true
X33 var o = {a: 1}; delete o.a; "a" in o ⇒ normal false
X34 delete 1 ⇒ normal true
X35 delete nope ⇒ normal true
X36 var v = 1; delete v ⇒ normal false
X37 w = 1; delete w ⇒ normal true
X38 w = 1; delete w; typeof w ⇒ normal string "undefined"
X39 function f() { var x; return delete x; } f() ⇒ normal false
X40 var n = 0; function f() { n++; } delete f(); n ⇒ normal number 1
X41 function F() {} new F() instanceof F ⇒ normal true
X42 function F() {} var o = new F(); F.prototype = {}; o instanceof F ⇒ normal false
X43 function F() {} 1 instanceof F ⇒ normal false
X44 ({}) instanceof {} ⇒ throw error TypeError
X45 function F() {} F.prototype = 1; new F() instanceof F ⇒ throw error TypeError
X46 "a" in {a: 1} ⇒ normal true
X47 "length" in "abc" ⇒ throw error TypeError
X48 PA a + b ⇒ normal number 3
X49 PA a + b; log ⇒ normal string "ab"
X50 PA a > b; log ⇒ normal string "ab"
X51 "" + { valueOf: function () { return {}; }, toString: function () { return "t"; } } ⇒ normal string "t"
X52 "" + { valueOf: function () { return {}; }, toString: function () { return {}; } } ⇒ throw error TypeError
X53 var o = {}; o[{ toString: function () { return "k"; }, valueOf: function () { return "v"; } }] = 1; o.k ⇒ normal number 1
X54 ({ valueOf: function () { return 1; } }) == 1 ⇒ normal true
X55 "" + {} ⇒ normal string "[object Object]"
X56 "" + 1e21 + "," + -0 ⇒ normal string "1e+21,0"
X57 var n = 0; try { null[n = 1]; } catch (e) {} n ⇒ normal number 1
X58 var k = 0; try { null[{ toString: function () { k = 1; return "x"; } }]; } catch (e) {} k ⇒ normal number 0
X59 var log = ""; var o = {}; o[{ toString: function () { log += "k"; return "p"; } }] = (log += "v", 1); log ⇒ normal string "vk"
X60 var n = 0; var x = 1; try { x(n = 5); } catch (e) {} n ⇒ normal number 5
X61 var n = 0; try { new 1(n = 5); } catch (e) {} n ⇒ normal number 5
X62 nope ⇒ throw error ReferenceError
X63 "use strict"; nope = 1 ⇒ throw error ReferenceError
X64 nope = 1; nope ⇒ normal number 1
X65 "use strict"; undefined = 1 ⇒ throw error TypeError
X66 undefined = 1; undefined ⇒ normal undefined
X67 "use strict"; function F() {} delete F.prototype ⇒ throw error TypeError
X68 function F() {} delete F.prototype ⇒ normal false
X69 var o = {}; o.f = function () { return this === o; }; o.f() + "," + (o.f)() + "," + (0, o.f)() ⇒ normal string "true,true,false"
X70 var log = ""; var o = { [(log += "1", "a")]: (log += "2", 1), b: (log += "3", 2) }; log ⇒ normal string "123"
X71 var o = {a: 1, a: 2}; o.a ⇒ normal number 2
X72 var o = {1.5: "x", 0x10: "y"}; o["1.5"] + o[16] ⇒ normal string "xy"
X73 var p = {a: 1}; var o = {__proto__: p}; o.a ⇒ normal number 1
X74 ("toString" in {__proto__: null}) + "," + ("toString" in {}) ⇒ normal string "false,true"
```

`PA` stands for `var log = ""; var a = { valueOf: function () { log += "a"; return 1; } }; var b = { valueOf: function () { log += "b"; return 2; } };`.

Derivations for the nontrivial rows:
- **X22.** IsLessThan(undefined, 1) is undefined, so `>=` returns false. For `null >= 0`, 0 < 0 is false, so `>=` returns true.
- **X45.** OrdinaryCreateFromConstructor falls back to `%Object.prototype%`. OrdinaryHasInstance step 4 then throws, because `F.prototype` is not an Object.
- **X50.** `a > b` is IsLessThan(b, a, LeftFirst false). Step 2 converts y = a first, then x = b, so the log is "ab".
- **X53.** ToPropertyKey runs ToPrimitive with hint string, so toString runs first.
- **X57, X58.** GetValue calls ToObject before ToPropertyKey (6.2.5.5 steps 3.a and 3.c).
- **X59.** ToPropertyKey runs after the right side, at PutValue step 3.c (6.2.5.6), as the note at 13.3.3 step 3 says.
- **X60, X61.** EvaluateCall step 3 and EvaluateNew step 4 evaluate the arguments before the callable and constructor checks.
- **X69.** In non-strict code, `(0, o.f)()` gets this = undefined, which OrdinaryCallBindThis turns into the global object.

**4. Statements and completion values.**

```text
S1  1; var x = 2; ⇒ normal number 1
S2  1; if (false) 2; ⇒ normal undefined
S3  1; if (true) {} ⇒ normal undefined
S4  1; {} ⇒ normal number 1
S5  1; ; debugger; ⇒ normal number 1
S6  2; do { 3; break; } while (false) ⇒ normal number 3
S7  1; while (true) { break; } ⇒ normal undefined
S8  var i = 0; while (i < 3) { i++; } ⇒ normal number 2
S9  var i = 0; do i++; while (i < 3) ⇒ normal number 2
S10 for (var i = 0; i < 3; i++) i; ⇒ normal number 2
S11 1; do { 2; continue; } while (false) ⇒ normal number 2
S12 1; do { if (true) continue; } while (false) ⇒ normal undefined
S13 a: { 1; break a; 2; } ⇒ normal number 1
S14 1; a: { break a; } ⇒ normal number 1
S15 switch (1) { case 1: 5; case 2: 6; break; } ⇒ normal number 6
S16 switch (3) { case 1: 5; default: 7; case 2: 8; } ⇒ normal number 8
S17 1; switch (0) { case 1: 2; } ⇒ normal undefined
S18 var log = ""; function c(v) { log += v; return v; } switch (2) { case c(1): case c(2): log += "!"; case c(3): } log ⇒ normal string "12!"
S19 1; try { 2; } finally { 3; } ⇒ normal number 2
S20 1; try { throw 0; } catch (e) {} ⇒ normal undefined
S21 1; try {} finally { 3; } ⇒ normal undefined
S22 try { throw 5; } catch (e) { e; } ⇒ normal number 5
S23 try { 1; } catch (e) { 2; } ⇒ normal number 1
S24 try { throw 1; } catch { 2; } ⇒ normal number 2
S25 var e = "outer"; try { throw "inner"; } catch (e) { e; } ⇒ normal string "inner"
S26 var e = "outer"; try { throw "inner"; } catch (e) {} e ⇒ normal string "outer"
S27 try { throw 1; } catch (e) { var e = 2; } e ⇒ normal undefined
S28 try { throw 1; } catch (e) { var e = 2; e; } ⇒ normal number 2
S29 var n = 0; while (true) { try { break; } finally { n++; } } n ⇒ normal number 1
S30 var n = 0; for (var i = 0; i < 3; i++) { try { continue; } finally { n++; } } n ⇒ normal number 3
S31 var log = ""; a: { try { try { break a; } finally { log += "1"; } } finally { log += "2"; } } log ⇒ normal string "12"
S32 try { try { throw 1; } finally { throw 2; } } catch (e) { e; } ⇒ normal number 2
S33 var c = 0; function f() { try { return 1; } finally { c = 1; } } f(); c ⇒ normal number 1
S34 function g() { try { return 1; } finally { 2; } } g() ⇒ normal number 1
S35 function f() { try { return 1; } finally { return 2; } } f() ⇒ normal number 2
S36 function f() { try { throw 1; } finally { return 2; } } f() ⇒ normal number 2
S37 function f() { l: try { return 1; } finally { break l; } return 3; } f() ⇒ normal number 3
S38 throw 1 ⇒ throw number 1
S39 throw {} ⇒ throw object
S40 throw new TypeError("x") ⇒ throw error TypeError
S41 var x = 1; try { throw 0; x = 2; } catch (e) {} x ⇒ normal number 1
S42 var s = ""; outer: for (var i = 0; i < 3; i++) { for (var j = 0; j < 3; j++) { if (j === 1) continue outer; s += i + "" + j; } } s ⇒ normal string "001020"
S43 var n = 0; outer: while (true) { while (true) { n++; break outer; } } n ⇒ normal number 1
```

Derivations:
- **S2, S3.** An IfStatement returns undefined, or UpdateEmpty(stmtCompletion, undefined) (14.6.2), so the earlier value 1 is replaced.
- **S5.** The DebuggerStatement returns empty when no debugging facility is enabled (14.16.1).
- **S6.** The block gives break(3). DoWhileLoopEvaluation returns UpdateEmpty(break(3), undefined), and LabelledEvaluation turns it into normal(3).
- **S11.** The block gives continue(2), so iterationResult becomes 2, and then the test is false.
- **S12.** The `if` gives UpdateEmpty(continue(empty), undefined) = continue(undefined), so iterationResult becomes undefined.
- **S14.** LabelledStatement step 4 gives NormalCompletion(empty), and the StatementList keeps 1.
- **S16.** No clause matches in A or in B. The default gives 7, and step 15 then runs the B clause, which gives 8.
- **S18.** CaseClauseIsSelected runs only while `found` is false, so `c(3)` never runs.
- **S21.** The finally completion is normal, so the result is the empty blockResult, and UpdateEmpty turns it into undefined.
- **S27.** CatchClauseEvaluation binds `e` in the catch environment, so `var e = 2` assigns that binding (B.3.4), and the global `e` stays undefined.
- **S37.** The finally block gives break(l), which overrides the return. Label l turns it into normal, so the function continues to `return 3`.

**5. Functions, environments, `this`, and construction.**

```text
F1  function f(a, b) { return a + b; } f(1, 2) ⇒ normal number 3
F2  function f(a, b) { return b; } f(1) ⇒ normal undefined
F3  function f(a, a) { return a; } f(1, 2) ⇒ normal number 2
F4  function f(a, a) { return a; } f(1) ⇒ normal undefined
F5  function f() { return typeof g; var g = 1; function g() {} } f() ⇒ normal string "function"
F6  function f() { var g = 1; function g() {} return g; } f() ⇒ normal number 1
F7  function f(a) { var a; return a; } f(7) ⇒ normal number 7
F8  function f(a) { function a() {} return typeof a; } f(7) ⇒ normal string "function"
F9  function mk() { var c = 0; return function () { c++; return c; }; } var g = mk(); g(); g() ⇒ normal number 2
F10 function mk() { var c = 0; return { inc: function () { c++; }, get: function () { return c; } }; } var o = mk(); o.inc(); o.inc(); o.get() ⇒ normal number 2
F11 function mk(v) { return function () { return v; }; } var a = mk(1); var b = mk(2); a() + b() ⇒ normal number 3
F12 var f = function g() { return typeof g; }; f() ⇒ normal string "function"
F13 var f = function g() {}; typeof g ⇒ normal string "undefined"
F14 var f = function g() { g = 1; return typeof g; }; f() ⇒ normal string "function"
F15 "use strict"; var f = function g() { g = 1; }; f() ⇒ throw error TypeError
F16 function fact(n) { return n <= 1 ? 1 : n * fact(n - 1); } fact(10) ⇒ normal number 3628800
F17 function f() { return this; } f() === this ⇒ normal true
F18 "use strict"; function f() { return this; } f() ⇒ normal undefined
F19 function f() { "use strict"; return this; } f() ⇒ normal undefined
F20 function F(a) { this.a = a; } new F(5).a ⇒ normal number 5
F21 function G() { this.x = 1; return { b: 2 }; } new G().b ⇒ normal number 2
F22 function H() { this.x = 1; return 1; } new H().x ⇒ normal number 1
F23 function P() {} P.prototype.m = function () { return 3; }; new P().m() ⇒ normal number 3
F24 new 1 ⇒ throw error TypeError
F25 var o = {}; new o() ⇒ throw error TypeError
F26 function F() {} F.prototype = 1; var o = new F(); "toString" in o ⇒ normal true
F27 var x = {}; x() ⇒ throw error TypeError
F28 function f(a, b) {} f.length + "," + (function () {}).length ⇒ normal string "2,0"
F29 function f() {} f.name ⇒ normal string "f"
F30 function F() {} var t = typeof F.prototype; (F.prototype.constructor === F) + "," + t ⇒ normal string "true,object"
F31 function f() {} f.name = "z"; f.name ⇒ normal string "f"
F32 "use strict"; function f() {} f.name = "z" ⇒ throw error TypeError
F33 function f() {} delete f.name; f.name ⇒ normal string ""
F34 function f(a) {} delete f.length; f.length ⇒ normal number 0
F35 function f() {} f.caller ⇒ throw error TypeError
F36 function o() { return i(); function i() { return 4; } } o() ⇒ normal number 4
F37 function f(arguments) { return arguments; } f(7) ⇒ normal number 7
F38 function g() { function arguments() {} return typeof arguments; } g() ⇒ normal string "function"
F39 arguments ⇒ throw error ReferenceError
F40 function f() { var z = 1; } f(); typeof z ⇒ normal string "undefined"
F41 function f() { z = 1; } f(); z ⇒ normal number 1
F42 var r = g(); function g() { return 9; } r ⇒ normal number 9
F43 function g() { return 1; } function g() { return 2; } g() ⇒ normal number 2
```

Derivations:
- **F3, F4.** With duplicates, both bindings start as undefined (10.2.11 step 21). IteratorBindingInitialization with usedEnv undefined then assigns them in order, so the last value wins.
- **F8.** Step 36 assigns the function object over the parameter binding.
- **F14, F15.** The function-expression name is an immutable, non-strict binding. SetMutableBinding throws only when the code is strict (9.1.1.1.5 step 5).
- **F22.** A primitive return value is ignored for a base constructor (10.2.2 step 13).
- **F33, F34.** The values come from `%Function.prototype%`'s `name` "" and `length` 0.
- **F35.** The inherited `caller` accessor's getter is `%ThrowTypeError%`. FP-0128 adds no own `caller` property; FP-0026's frontier decomposition owns that legacy extension.

**6. Name inference.**

```text
N1  var f = function () {}; f.name ⇒ normal string "f"
N2  var g = function h() {}; g.name ⇒ normal string "h"
N3  x = function () {}; x.name ⇒ normal string "x"
N4  var x; (x) = function () {}; x.name ⇒ normal string ""
N5  var f = (function () {}); f.name ⇒ normal string "f"
N6  var f = (0, function () {}); f.name ⇒ normal string ""
N7  var o = { a: function () {} }; o.a.name ⇒ normal string "a"
N8  var o = { "b c": function () {} }; o["b c"].name ⇒ normal string "b c"
N9  var o = { 1: function () {} }; o[1].name ⇒ normal string "1"
N10 var o = { ["k" + 1]: function () {} }; o.k1.name ⇒ normal string "k1"
N11 var o = { __proto__: function () {} }; o.name ⇒ normal string ""
N12 var o = { ["__proto__"]: function () {} }; o.__proto__.name ⇒ normal string "__proto__"
N13 var o = {}; o.a = function () {}; o.a.name ⇒ normal string ""
N14 var f; f = function () {}; f.name ⇒ normal string "f"
N15 var a = b = function () {}; a.name ⇒ normal string "b"
N16 var f = function () {}; var g = f; g.name ⇒ normal string "f"
N17 var fn = function () {}; var o = { fn }; o.fn.name ⇒ normal string "fn"
N18 var o = { f: function g() {} }; o.f.name ⇒ normal string "g"
N19 "use strict"; var f = function () {}; f.name ⇒ normal string "f"
N20 var f = ((function () {})); f.name ⇒ normal string "f"
```

Derivations:
- **N4.** IsIdentifierRef of a parenthesized expression is false (8.4.4).
- **N5, N20.** IsFunctionDefinition and NamedEvaluation pass through ParenthesizedExpression (8.4.2, 8.4.5).
- **N11.** isProtoSetter is true, so NamedEvaluation does not run. The function keeps the name "" from 15.2.5, and `o` inherits it.
- **N12.** A computed key is never the proto setter.
- **N15.** The initializer is an AssignmentExpression, so IsAnonymousFunctionDefinition is false for `a`.

**7. Function.prototype.toString.**

```text
T1  /* before */function /* a */ f /* b */ ( /* c */ x /* d */ , /* e */ y /* f */ ) /* g */ { /* h */ ; /* i */ ; /* j */ }/* after */⏎f.toString() ⇒ normal string "function /* a */ f /* b */ ( /* c */ x /* d */ , /* e */ y /* f */ ) /* g */ { /* h */ ; /* i */ ; /* j */ }"
T2  var e = function () { return 1; }; e.toString() ⇒ normal string "function () { return 1; }"
T3  var p = (function  q ( ) {}); p.toString() ⇒ normal string "function  q ( ) {}"
T4  var t = function () {<CR>⏎return "\u0041";<U+2028>}; t.toString() ⇒ normal string "function () {\u000D\u000Areturn \"\\u0041\";\u2028}"
T5  "" + function () {} ⇒ normal string "function () {}"
T6  function outer() { function inner(a) { return a; } return inner; } outer().toString() ⇒ normal string "function inner(a) { return a; }"
T7  "use strict"; function s() { "use strict"; } s.toString() ⇒ normal string "function s() { \"use strict\"; }"
T8  function f() {} f.toString.toString() ⇒ normal string "function toString() { [native code] }"
T9  TypeError.toString() ⇒ normal string "function TypeError() { [native code] }"
T10 var o = { t: (function () {}).toString }; o.t() ⇒ throw error TypeError
```

T10 follows 20.2.3.5 step 5: the receiver has no [[SourceText]], is not a built-in function, and is not callable.

**8. B.3.9.**

`PB` stands for `var log = ""; function f() { log += "f"; return { valueOf: function () { log += "v"; return 1; } }; } function g() { log += "g"; return 1; }`.

```text
B1 PB try { f() = g(); } catch (e) { log += e instanceof ReferenceError; } log ⇒ normal string "ftrue"
B2 PB try { f() += g(); } catch (e) { log += e instanceof ReferenceError; } log ⇒ normal string "ftrue"
B3 PB try { f()++; } catch (e) { log += e instanceof ReferenceError; } log ⇒ normal string "ftrue"
B4 PB try { --f(); } catch (e) { log += e instanceof ReferenceError; } log ⇒ normal string "ftrue"
B5 PB try { (f()) = g(); } catch (e) { log += e instanceof ReferenceError; } log ⇒ normal string "ftrue"
B6 function h() { throw 7; } try { h() = 1; } catch (e) { e; } ⇒ normal number 7
B7 var x = 1; try { x() = 2; } catch (e) { e instanceof TypeError; } ⇒ normal true
B8 "use strict"; f() = 1; ⇒ syntax-error invalid_assignment_target @14
B9 function async() {} try { async() = 1; } catch (e) { e instanceof ReferenceError; } ⇒ normal true
```

- **B1 to B5.** The ReferenceError is thrown right after the target is evaluated, so `g` and `valueOf` never run.
- **B6, B7.** The call's own throw comes first.
- **B8** is FP-0082 row E54.
- **B9** is the CoverCallExpressionAndAsyncArrowHead form from `cover-callexpression-and-asyncarrowhead.js:17-21`.

**9. ToObject, String exotic objects, and `this` binding.**

```text
W1 "abc".length + "," + "abc"[1] + "," + "abc"[3] + "," + "abc"[-0] + "," + "abc"["01"] ⇒ normal string "3,b,undefined,a,undefined"
W2 "abc".x + "," + (5).x + "," + true.x ⇒ normal string "undefined,undefined,undefined"
W3 null.x ⇒ throw error TypeError
W4 undefined[0] ⇒ throw error TypeError
W5 var s = "abc"; s.length = 5; s.x = 1; s.length + "," + s.x ⇒ normal string "3,undefined"
W6 "use strict"; "abc".length = 5 ⇒ throw error TypeError
W7 "use strict"; "abc".x = 1 ⇒ throw error TypeError
W8 "use strict"; "abc"[0] = "z" ⇒ throw error TypeError
W9 "use strict"; (5).x = 1 ⇒ throw error TypeError
```

Derivations:
- **W1.** CanonicalNumericIndexString("01") is undefined, because ToString(1) is "1", not "01". The key -0 becomes "0" through ToPropertyKey.
- **W5 to W9.** OrdinarySetWithOwnDescriptor returns false for a non-writable own property, or for a primitive receiver (10.1.9.2 steps 2.a and 2.b).

**W10** is a Zig-level test through the host API.
- ToObject of each of true, false, 0, -0, NaN, "", "ab", a host symbol, and the host BigInt 12 gives an object. Its [[Prototype]] is the realm's matching `%X.prototype%`, and its data slot is SameValue to the input.
- ToObject of undefined and of null throws TypeError.
- ToObject of an object returns the same object.
- For "ab", [[OwnPropertyKeys]] is "0", "1", "length".
- The descriptor of "0" is {value "a", Writable false, Enumerable true, Configurable false}, and the descriptor of "length" is {value 2, all attributes false}.

**W11** uses `Engine.call`. `globalThis` is the global object of each script's realm.
- The non-strict `function f() { return typeof this; }`, called with this 5, gives `normal string "object"`.
- The strict `function g() { "use strict"; return typeof this; }`, called with this 5, gives `normal string "number"`.
- The non-strict `function h() { return this === globalThis; }`, called with this undefined, gives `normal true`.

**W12** uses `Engine.call`. The non-strict `function k() { this.length = 5; return this.length; }`, called with this "ab", gives `normal number 2`. The derivation:
- OrdinaryCallBindThis makes `this` ToObject("ab"), a String object (10.2.1.2 step 6.b).
- PutValue then calls that object's [[Set]] with the object itself as the receiver.
- OrdinarySetWithOwnDescriptor finds the own non-writable `length` and returns false at step 2.a. Non-strict code ignores the false result.
- So `this.length` reads 2.

**10. Realm and GlobalDeclarationInstantiation.**

```text
R1  (this === globalThis) + "," + typeof globalThis ⇒ normal string "true,object"
R2  "use strict"; this === globalThis ⇒ normal true
R3  (NaN !== NaN) + "," + Infinity + "," + typeof undefined ⇒ normal string "true,Infinity,undefined"
R4  function undefined() {} ⇒ throw error TypeError
R5  var ran = 1; function NaN() {} ⟫ typeof ran ⇒ throw error TypeError ⟫ normal string "undefined"
R6  var undefined = 5; undefined ⇒ normal undefined
R7  x = 1; ⟫ function x() { return 2; } x() ⟫ delete x ⇒ normal number 1 ⟫ normal number 2 ⟫ normal false
R8  var y = 1; ⟫ function y() {} typeof y ⇒ normal undefined ⟫ normal string "function"
R9  function f() { return g(); } ⟫ function g() { return 3; } f() ⇒ normal undefined ⟫ normal number 3
R10 var v = 1; ⟫ delete v ⇒ normal undefined ⟫ normal false
```

Derivations:
- **R4, R5.** CanDeclareGlobalFunction returns false for the non-configurable, non-writable `undefined` and `NaN` (9.1.1.4.15 steps 5 to 7). The error is thrown at 16.1.7 step 8, before any binding exists.
- **R6.** CanDeclareGlobalVar returns true, and Set then returns false without a throw in non-strict code.
- **R7.** The implicit global is configurable, so CreateGlobalFunctionBinding redefines it as non-configurable.
- **R8.** The existing var is {Writable true, Enumerable true}, so step 6 of 9.1.1.4.15 applies.

**R11.** Realm A runs `var q = 1;`, and then realm B runs `typeof q`. The outcomes are `normal undefined` and then `normal string "undefined"`.

**R12** uses two realms.
- Realm A runs `function fa() { null.x; } fa` and gives `normal function`.
- `defineGlobal(B, "fa", value)` copies that value into realm B.
- Realm B runs `try { fa(); } catch (e) { e instanceof TypeError }` and gives `normal false`. `fa`'s [[Realm]] is A, so the TypeError comes from realm A (10.2.1.1 step 13).
- Realm B then runs `try { null.x; } catch (e) { e instanceof TypeError }` and gives `normal true`.

**R13** is a Zig-level test. The global object's own keys and attributes equal the "Realm and intrinsics" table, in order.

**11. Error constructors and the built-ins.**

```text
E1  new TypeError("m").message ⇒ normal string "m"
E2  TypeError("m") instanceof TypeError ⇒ normal true
E3  new TypeError({ toString: function () { return "z"; } }).message ⇒ normal string "z"
E4  TypeError.name + "," + TypeError.length + "," + TypeError.prototype.name + "," + TypeError.prototype.message + "|" ⇒ normal string "TypeError,1,TypeError,|"
E5  (TypeError.prototype instanceof Error) + "," + (TypeError.prototype.constructor === TypeError) + "," + (new TypeError() instanceof Error) ⇒ normal string "true,true,true"
E6  try { null.x; } catch (e) { e.constructor === TypeError } ⇒ normal true
E7  try { nope; } catch (e) { e.constructor === ReferenceError } ⇒ normal true
E8  new Error("a", { cause: 0 }).cause ⇒ normal number 0
E9  ("cause" in new Error("a")) + "," + ("cause" in new Error("a", {})) ⇒ normal string "false,false"
E10 "" + new TypeError("m") ⇒ normal string "TypeError: m"
E11 "" + new Error() ⇒ normal string "Error"
E12 var e = new Error("x"); e.name = ""; "" + e ⇒ normal string "x"
E13 var t = new Error().toString; t() ⇒ throw error TypeError
E14 var ts = ({}).toString; ts() ⇒ normal string "[object Undefined]"
E15 var f = function () {}; f.ts = ({}).toString; f.ts() ⇒ normal string "[object Function]"
E16 var e = new Error(); e.ots = ({}).toString; e.ots() ⇒ normal string "[object Error]"
E17 var o = {}; o.valueOf() === o ⇒ normal true
E18 Error.isError(new TypeError()) + "," + Error.isError({}) ⇒ normal string "true,false"
E19 Error.length + "," + Error.name + "," + (Error.prototype.constructor === Error) ⇒ normal string "1,Error,true"
E20 ReferenceError.prototype.name ⇒ normal string "ReferenceError"
```

Derivations:
- **E1, E3, E10 to E12.** These messages come from user-supplied values, not from the engine.
- **E10 to E12.** Error.prototype.toString steps 3 to 9 apply.
- **E14.** A built-in function does not coerce `this`, so 20.1.3.6 step 1 returns "[object Undefined]".

**12. Limits and abrupt outcomes.**

```text
L1 (max_frames = 1000) function f(n) { return n === 0 ? 0 : 1 + f(n - 1); } f(998) ⇒ normal number 998
L2 (max_frames = 1000) the same f; f(999) ⇒ limit frames
L3 (max_frames = 1000) var x = 0; function f(n) { return n === 0 ? 0 : 1 + f(n - 1); } try { f(999); } catch (e) { x = 1; } finally { x = 2; } ⟫ x ⇒ limit frames ⟫ normal number 0
L4 (max_stack_bytes = 65536) function f() { return 1 + f(); } f() ⇒ limit stack
L5 (max_cells = M + 1000, where M is the live count after createRealm and `var a = {};` in a calibration engine) var a = {}; ⟫ while (true) a = { n: a }; ⇒ normal undefined ⟫ limit cells
```

Derivations:
- **L1, L2.** The frames are the script frame plus f(n) through f(0), so there are n + 2 frames. f(998) uses exactly 1000. For f(999), the push of f(0) finds 1000 frames already.
- **L3.** A limit skips catch and finally, and the realm stays usable.
- **L4.** The recursion is not a tail call.
- **L5.** L5 does not run under `checkAllAllocationFailures`.

**L6** runs `std.testing.checkAllAllocationFailures`, with the backing allocator above, over Engine.init, createRealm, and evaluateScript of S42, F10, N10, and E10 joined by LF. Every induced failure returns `error.OutOfMemory`, and no run reports `limit cells`. Nothing leaks, and the heap invariants hold.

**13. Native stack.** Each 1 MiB run uses the FP-0082 painting pattern (`parser.zig:2978-3053`) in the Debug test build. A run fails when it reaches the last 32 KiB.

- **D1.** The prelude script is `var a = 1;`. FP-0082 case 10's accepted inputs compile and run on a 1 MiB thread:
  - `a` joined by `+` with 1022 terms gives `normal number 1022`;
  - `a` inside 1021 parentheses gives `normal number 1`.
- **D2.** For each FP-0082 case 11 shape, the test binary-searches the largest n ≤ 2000 whose parse outcome is a script. It then runs that source on a 1 MiB thread with this prelude and expected outcome:

| Shape | Prelude | Expected |
| --- | --- | --- |
| `(` | `var a = 1;` | normal number 1 |
| `!` | `var a = 1;` | normal true if n is even, normal false if n is odd |
| `typeof ` | `var a = 1;` | normal string "string" |
| `{` | `var a = 1;` | normal number 1 |
| `if (a) ` | `var a = 1;` | normal number 1 |
| `(function(){` … `})` | none | normal function |
| `a(` | `var a = function (x) { return x; };` | normal function |
| `a[` | `var a = 0;` | normal undefined |
| `a?a:` | `var a = 1;` | normal number 1 |
| `a=` | `var a = 1;` | normal number 1 |
| `a**` | `var a = 1;` | normal number 1 |
| `new ` | `var a = function () {};` | throw error TypeError |
| `({a:` … `})` | `var a = 1;` | normal object |
| `l<n>:` | `var a = 1;` | normal number 1 |

The binary search assumes that acceptance is monotone in n, because depth grows with n [INFERENCE].

- **D3.** `function f(n) { return n === 0 ? 0 : 1 + f(n - 1); } f(200000)` gives `normal number 200000` on a 1 MiB thread.
- **D4.** On a 1 MiB thread, these two sources each give `normal number 10000`:
  - `function g(n) { return n === 0 ? 0 : +{ valueOf: function () { return g(n - 1) + 1; } }; } g(10000)`
  - `function h(n) { return n === 0 ? 0 : +new TypeError({ toString: function () { return "" + (h(n - 1) + 1); } }).message; } h(10000)`
  Each level builds strings of at most 5 code units, so the work is linear.
- **D5. Constancy.** On a 64 MiB thread, for each P in f, g, and h, the stack high-water mark of P(3000) minus that of P(10) is at most 4096 bytes. A compile-only probe of `a` inside 1000 parentheses, compared with 10 parentheses, meets the same bound. The test prints every measurement.

**14. Representations, tracers, and stress.**
- Cases 3 to 11 and case 20 run under {reference, nan_box, tagged_index} × {generated, manual}.
- They run again with `collect_before_each_allocation` and `quarantine_freed_cells`. `zig build test` runs that pass under reference × generated and reference × manual. `js-vm-heavy` runs it under the other four pairs.
- Every outcome line is the same, `dead_resolutions` is 0, and `expectInvariants` passes after each row.
- Row Z1, `var o = { a: "x" + 1, b: "y" + 2 }; o.a + o.b`, gives `normal string "x1y2"` in every run.

**15. Compile every accepted tree.**
- Every source of FP-0082 cases 2, 6, and 7 that parses to a script compiles and verifies. So does every prefix of such a source, and every source with one code unit deleted, as in FP-0082 case 14.
- Random sources under seed `0x4650303833000001`, with FP-0082 case 14's alphabet and length rule, compile and verify. `zig build test` runs 5,000 of them, and `js-vm-heavy` runs 50,000.
- Compiling the same tree twice gives identical bytes.
- `std.testing.checkAllAllocationFailures`, with the backing allocator above, compiles T9, T11, T18, T21, and T33 joined by LF, and nothing leaks.
- These rows each exceed 65,535 in one count and compile and run:
  - `function f() { var v0, v1, …, v69999; v69999 = 1; return v69999; } f()` gives `normal number 1`;
  - `function f(a0, a1, …, a69999) { return a69999; } f(0, 1, …, 69999)` gives `normal number 69999`;
  - `function g(a) { return a; } g(1, 1, …, 1)` with 70,000 arguments gives `normal number 1`.

**16. Opcode coverage.** In test builds, every opcode in the catalog is emitted by some source in cases 3 to 15 and executed at least once.

**17. Command line.** These run as `build.zig` steps on the installed Debug `fairpane-js-run`:
- `file tests/js/run/sum.js` holds `function f(a, b) { return a + b; }⏎f(2, 3)⏎`. It prints `normal number 5` and exits with status 0.
- `throw.js` (`throw new TypeError("x");`) prints `throw error TypeError` and exits with status 5.
- `syntax.js` (`var 1;`) prints `syntax-error unexpected_token @4` and exits with status 1.
- `unsupported.js` (`x => x`) prints `unsupported arrow_function @2` and exits with status 2.
- `missing-global.js` (`Math`) prints `unsupported Math` and exits with status 2.
- `deep.js` holds 1,100 opening parentheses, then `a`, then 1,100 closing parentheses. It exits with status 4. It prints exactly the line that `fairpane-js-parse file tests/js/run/deep.js` prints in the same build, which begins `limit depth @`.
- `invalid-utf8.js` (bytes `76 61 72 20 FF`) exits with status 3.
- A missing path exits with status 3.
- No arguments exits with status 3, and standard error contains `usage: fairpane-js-run`.
- `first.js` (`var q = 2;`) and then `second.js` (`q * 21`) print `normal undefined` and `normal number 42`, and exit with status 0.

**18. FP-0011 and FP-0082 regression.**
- FP-0011 case 7's literal gains these lines, plus any environment or code kinds that ADR 0012 names:
  - `ecmascript_function|yes|yes|…`;
  - `primitive_wrapper|yes|no|…`;
  - `string_object|yes|no|…`, with `InternalMethods.string_exotic`.
- ADR 0012 lists every new kind and layout before `tests-before.log`. The worker records the literal there, and the README diffs the implemented literal against the ADR.
- FP-0011 case 20 lists every new file.
- Every FP-0011 and FP-0082 case still passes.

**19. Host rooting.** Evaluating `({a: 1})` gives an outcome that writes `normal object`, both before and after a forced collection. After `release` and another collection, the live cell count has dropped by at least 1.

**20. Unimplemented standard globals.**

```text
G1 Array ⇒ unsupported Array
G2 typeof Function ⇒ unsupported Function
G3 var log = ""; try { log += "a"; Math; } catch (e) { log += "c"; } finally { log += "f"; } ⟫ log ⇒ unsupported Math ⟫ normal string "a"
G4 var Object = 1; Object ⇒ normal number 1
G5 Number = 2 ⇒ unsupported Number
G6 delete Array ⇒ unsupported Array
G7 globalThis.Array ⇒ normal undefined
G8 function f() { return JSON; } typeof f ⟫ f() ⇒ normal string "function" ⟫ unsupported JSON
```

Derivations:
- **G2, G5, G6.** The rule applies to the IdentifierReference before `typeof`, PutValue, or `delete` uses it.
- **G3.** No catch or finally block runs, and the realm stays usable.
- **G4.** The `var` makes `Object` resolvable, so ordinary semantics apply.
- **G7.** A property read is not an identifier reference.

**G9** is a Zig-level test.
- `unimplemented_globals` equals the frozen list of 57 names, in order.
- No listed name is an own property of a fresh realm's global object.
- None of `globalThis`, `Infinity`, `NaN`, `undefined`, `Error`, `ReferenceError`, or `TypeError` is on the list.

## Mutation controls

Each control is a `.diff` that is applied with `git apply`, run, and reversed with `git apply -R`.
The file hashes are recorded before, during, and after each control.
A crash is recorded separately from a failed assertion.

| Control | Mutation | Named case | Why it must fail |
| --- | --- | --- | --- |
| M1 | A call of an ECMAScript function re-enters `run` natively. | 13 D5, f | 2,990 extra native frames of at least 16 bytes each add at least 47,840 bytes. That exceeds both the 4096-byte bound and FP-0082's 21 KB parse baseline [INFERENCE: minimum frame size]. |
| M2 | An IfStatement without else returns empty when the test is false. | 4 S2 | UpdateEmpty keeps 1, so the row gives `normal number 1`. |
| M3 | The B.3.9 check runs after the right side. | 8 B1 | The log becomes "fgtrue". |
| M4 | IsIdentifierRef sees through parentheses. | 6 N4 | The row gives `string "x"`. |
| M5 | `[[SourceText]]` ends one code unit early. | 7 T2 | The `}` is lost. |
| M6 | OrdinaryToPrimitive calls methods by native re-entry. | 13 D5, g | The native stack grows at each level. |
| M7 | The root enumeration skips the top frame's registers. | 14 Z1 | Under stress, the object under construction is quarantined, so `dead_resolutions` is greater than 0. |
| M8 | OrdinaryCallBindThis skips ToObject. | 9 W11 | The first call gives `string "number"`. |
| M9 | `return` inside `try` skips `finally`. | 4 S33 | `c` stays 0. |
| M10 | The frame check fires one frame early. | 12 L1 | The row gives `limit frames`. |
| M11 | A String object's `length` is created writable. | 9 W10 and W12 | In W10, the "length" descriptor of ToObject("ab") has Writable true. In W12, the receiver of [[Set]] is the String object, so OrdinarySetWithOwnDescriptor passes step 2.a. It then finds the writable existing descriptor at steps 2.c to 2.f and defines the value at step 2.h. 10.4.3.2 passes the non-index key "length" to OrdinaryDefineOwnProperty, so the row gives `normal number 5`. |
| M12 | Engine-thrown errors use the first realm's prototypes. | 10 R12 | The last script gives `normal false`. |
| M13 | A listed name throws ReferenceError instead of giving the unsupported outcome. | 20 G1 | The row gives `throw error ReferenceError`. |
| M14 | The compiler truncates the argument `count` operand to 16 bits. | 15, 70,000-parameter row | 70,000 mod 65,536 is 4,464 arguments, so `a69999` is undefined and the row gives `normal undefined`. |

If a control does not fail its named case, the worker reports that and changes neither the control nor the case.

## Stop rules

1. If any expected line contradicts the cited ECMA-262 text, stop and report it. Never edit an expectation silently.
2. If a Debug 1 MiB run in case 13 D1 to D4 overflows, stop. Report the bytes per level, and do not lower any bound.
3. If the FP-0082 parser gives a non-script outcome for a source that this contract treats as a script, stop and report the row.
4. If the compile census reports `compile_failures` or `limits` greater than 0, fix the compiler within this contract. If its `discovered`, `module`, or `runs` differs from 53,616, 843, or 102,151, stop.
5. If a smoke run differs from its expectation, stop and report the file, the mode, and the outcome.
6. Apply these rules to the time budget.
   - These runs always stay in `zig build test`:
     - case 14's non-stress runs under all six pairs;
     - case 13 D1, D2, and D5, and case 12 L1 to L4;
     - case 15's FP-0082 rows, its first 5,000 random sources, and its three 70,000-count rows.
   - If `zig build test` takes more than 30 seconds longer than in `base-timing.log`, move other whole cases into `js-vm-heavy`, largest first. List each move in the README, and rerun. Never shrink or drop a case. If a mutation control's named case moves, the README records that control's run through `zig build js-vm-heavy`.
   - If the budget still fails, stop and report each case's time.
7. If a required behavior needs native re-entry into the interpreter, stop and report it.
8. If the task is too large to finish in one contract, stop and report what is done. The integrator then splits FP-0128 as "Integrator decisions" describes.
9. If ADR 0012 cannot show the per-code-unit bound for some syntax form of the FP-0082 subset, stop and report that form.

## Criterion mapping

| FP-0128 criterion | Cases and evidence |
| --- | --- |
| 1 Execute the subset | Cases 3 to 12, 17, and 20; `smoke.log` |
| 2 Compile every tree; every representation and tracer | Cases 1, 14, 15, and 16; `compile-census.log`; `heavy.log`; the first Gates run on both hosts |
| 3 Realm, environments, functions, completions, ToObject, intrinsics | Cases 3 to 5 and 9 to 11; M2, M8, M9, M11, M12 |
| 4 ADR 0012 | The ADR, reviewed against cases 1, 15, and 16 and the width rule; M14 |
| 5 Native stack and deepest inputs | Cases 13 and 15; M1, M6 |
| 6 FP-0082 obligations | Cases 6, 7, and 8; M3, M4, M5 |
| 7 No native re-entry; limit outcomes | Cases 12 and 13; M1, M6, M10 |
| 8 Unimplemented globals | Case 20; smoke file 16; M13 |

## Remaining obligations

- **FP-0129.** Safepoints, frame descriptions, stress collection at every safepoint, interrupts, and `host_context`.
- **FP-0084.**
  - `print` and `$262`.
  - The runner and its selection rule.
  - Mapping `unsupported <name>` to its unsupported category.
  - Classifying tail-call tests by feature.
- **FP-0086.** Block environments.
- **FP-0087.** Arguments objects. Its callback methods follow the continuation-frame rule.
- **FP-0089.** Accessors from script, which follow the continuation-frame rule.
- **FP-0096.** `eval` and `with`, which end compile-time resolution of function-local names.
- **FP-0012's built-in library tasks.** Every constructor and method that FP-0128 does not list. Each of these tasks removes its names from `unimplemented_globals`.
- **FP-0026's frontier decomposition.** Proper tail calls, and the legacy `caller` and `arguments` own properties.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0128/raw/`.
Run every Zig command with the locked compiler and `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
Never delete or overwrite a log.
Name the log of a failed attempt with the suffix `-attempt-N`.

1. Record `facts.log` at the base, before any change. It contains these records:
   - `git rev-parse HEAD`, and `git diff --stat 2c85bd3 HEAD -- src build.zig`, which shows whether any source file changed after the drafter's reads; any change listed there is re-read before the first test run;
   - `git show HEAD:<file>` windows for every source line that "Observed facts" and "Integrator decisions" cite;
   - `certutil -hashfile out\fp0082-census.jsonl SHA256`, which must print `0e5277cd3bad6676e588dd11e196231c95069088f45aa5e993eb947a962148c7`;
   - a `node -e` script that prints the census records of the 16 smoke files and of the seven B.3.9 files;
   - `type out\fp0082-test262\EXTRACT.json`, which binds the searched extraction to Test262 commit `2e0a56762801e275a9fdf96dc49d90ba0cddcf63`;
   - `findstr /s /m "sec-runtime-errors-for-function-call-assignment-targets"` over `out/fp0082-test262/test`, and then `findstr /n /c:"valueOf() {"` and `findstr /n /c:"for ("` in each listed file;
   - `findstr /n /r` with one `\<Name\>` word-boundary pattern for each of the 57 listed names over `harness/assert.js`, `harness/sta.js`, and the 16 smoke files; the README classifies each hit as code or comment.
2. Before staging any test, record `base-timing.log` at the base with `zig build test --summary all --cache-dir out/fp0128-base`, with the start and end times.
3. Write ADR 0012's opcode, width, and heap-kind sections and cases 1 to 20, including the updated FP-0011 case 7 literal. Record `tests-before.log` with `HEAD`, the staging command, the blob IDs, and `zig build test --summary all --cache-dir out/fp0128-before`. It must fail.
4. Record an uncached `tests-after.log`: `cmd /d /c ver`, the binding commands, and the timed `zig build test --summary all --cache-dir out/fp0128-after`.
   - It must exit with status 0.
   - It must show the D5 measurements.
   - It must take at most 30 seconds longer than `base-timing.log`.
5. Record `heavy.log` with `zig build js-vm-heavy --summary all`. It must exit with status 0.
6. Record `fmt.log` with `zig fmt --check build.zig src tests`.
7. Record `controller-tests-after.log` with `node --version` and `node tools/fairpane.mjs test`.
8. Record `js-tools-build.log` with `zig build js-tools -Doptimize=ReleaseSafe --summary all`.
9. Record `corpus-verify.log`. Record `extract.log` with `corpus-extract test262 out/fp0128-test262`; the extraction must report 53,975 files.
10. Record `compile-census.log` with `fairpane-js-run compile-census out/fp0128-test262`. It must exit with status 0.
11. Record `smoke.log`:
    - `git hash-object` of the 18 files, which are 2 harness files and 16 tests;
    - then `fairpane-js-run test262-smoke out/fp0128-test262`, which must exit with status 0 and print the expected summary line.
12. Record `mutation.log` and the diffs for M1 to M14.
13. Write `README.md`. It gives:
    - the criterion mapping;
    - the case 7 literal and its diff against ADR 0012;
    - every move into `js-vm-heavy`;
    - every attempt;
    - every resolved ambiguity.

The integrator does these steps before freezing:

1. Record the plan commit `4e65397` and the absence of `engineering/decisions/0012-*` at the base.
2. Record `spec-pages.log`. For each multipage ECMA-262 page that "Sources" cites, it records the retrieval date, the page's SHA-256, and the lines of the cited headings.
   - The pages are: `ecmascript-data-types-and-values`, `abstract-operations`, `syntax-directed-operations`, `executable-code-and-execution-contexts`, `ordinary-and-exotic-objects-behaviours`, `ecmascript-language-expressions`, `ecmascript-language-statements-and-declarations`, `ecmascript-language-functions-and-classes`, `ecmascript-language-scripts-and-modules`, `global-object`, `fundamental-objects`, and `additional-ecmascript-features-for-web-browsers`.
   - The recorded headings include the clause 19 and B.2.1 headings.

The integrator does these steps after the implementation:

1. Record `HEAD` and a status that includes ignored files for every source root, before and after the gates.
2. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0128/gates`.
3. Rerun steps 5 and 8 to 11 at the integration commit.
4. Using a script that shares no code with the Zig tool, check that `scripts` in the compile census equals the number of FP-0082 census run records whose `outcome` is `script`.
5. After the push, record the first `Gates` run that contains the change with `gh run view`, and its receipts with `gh run download`. The README reports the Windows and Linux zig-test step durations, and each must be at most 400 seconds.
   - If a zig-test step times out, the README records the receipt, and the integrator reruns the failed jobs once, as for run 37991104261.
   - A second timeout, or any zig-test step above 400 seconds, blocks acceptance. The worker then moves the cases that stop rule 6 allows into `js-vm-heavy` under a contract amendment.

## Authority

- Writable paths are `src`, `tests`, `tools`, `build.zig`, `engineering/decisions/0012-javascript-bytecode-and-dispatch.md`, and `engineering/evidence/FP-0128/`.
- These protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
- `specs/applicability/test262.json` stays unchanged.
- Only the integrator updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.

## Non-goals

- No Test262 conformance result, no runner, and no selection.
- No safepoint descriptions and no interrupts; FP-0129 owns them.
- No adaptive dispatch, no JIT, and no performance claim.
- No lexical declarations, arguments objects, accessors, classes, generators, modules, RegExp, BigInt literals, `with`, or `eval`.
- No built-ins beyond the table above.
- No proper tail calls, and no legacy `caller` or `arguments` own properties.
- No change to the C ABI, `include`, `api`, the gates, or `specs`.
- No Test262 file copied into the repository.

## Pre-freeze check findings and resolutions

The check is `out/drafts/FP-0128-check.json`, with the verdict fix-first: five majors, eight minors, and two notes.

1. **Major: the base and sources are stale, and no re-check was recorded.** Identity now names the Revision 2 head (`84ffa53` with `c28afb0`, `f397d8d`, and `1ecd24a`). Sources cite the FP-0082 contract with amendments 1 and 2, Revision 1 with its amendments 1 and 2, and Revision 2 with its amendments 1 to 3. A new Integrator decisions bullet records the re-check: the E96 rows, `writeOutcome` versus `writeDiagnostic`, the Limiter, and the per-body sets. No expected line changed. `Engine.writeOutcome` writes parse diagnostics through `parser.writeDiagnostic`.
2. **Major: ADR 0011 versus 0012.** Plan commit `4e65397` renamed the criterion, so `engineering/plan.json:4273` now reads 0012 and the contract carries it word for word. The decision cites that commit.
3. **Major: M11 cannot fail W6.** M11 now names W10 and a new host-call row, W12, where the receiver is the String object. W12 gives `normal number 2`, and under M11 it gives 5. The table shows the derivation.
4. **Major: u16 operands conflict with "no compile limit".**
   - `reg`, `count`, `const`, `name`, and `function` are u32, and `jump` is i64. A width rule ties every count to `max_source_units` (`parser.zig:37`), and stop rule 9 covers a failed proof.
   - Case 15 gains a 70,000-parameter row and a 70,000-argument row. The new M14 truncates `count` and fails the parameter row.
5. **Major: the time budget is not tied to CI.**
   - The 30-second host budget stays.
   - The first Gates run must keep each zig-test step within 400 s on both hosts, and the README reports both.
   - The `0df569a` timeout and its rerun are cited.
   - Stop rule 6 pins the criterion-bearing runs inside `zig build test`.
6. **Minor: OutOfMemory versus `limit cells`.** The heap keeps FP-0011 case 15's `error.OutOfMemory` and records the cell-limit cause, as `Limiter.exceeded` does. The engine maps that cause to `limit cells`. L5 is outside the allocation checker, and L6 never reports `limit cells`.
7. **Minor: the allocation-failure checks lacked a backing allocator.** Every allocation-failure check now names a `FailingAllocator` with `.resize_fail_index = 0` and asserts `allocated_bytes == freed_bytes` (`heap.zig:1093-1100`; `FailingAllocator.zig:81-110`).
8. **Minor: the Limiter note and `max_stack_bytes`.** Default limits folds in the state note and defines `max_stack_bytes` as logical bytes. Every case uses the parser defaults.
9. **Minor: stale citations.** These were re-cited at `9f1096d`, which is `2c85bd3` plus one plan-only commit:
   - `ast.zig:162` and `ast.zig:35-37`;
   - `parser.zig:1923-1932`, `556-561`, `1218-1221`, and `2978-3053`;
   - `heap_catalog.zig:393-407`, `409-416`, and `15-24`;
   - `value.zig:143-166`.
   At this tree, `heap.zig:209` is the `function_prototype` line itself, so that citation stays. Evidence step 1 records every cited window at the base.
10. **Minor: X59.** It now cites PutValue step 3.c.
11. **Minor: unrecorded claims.**
    - The B.3.9 claim was wrong for `cover-callexpression-and-asyncarrowhead.js`, which uses no method syntax and is unsupported at `for_in @992`. Observed facts now say so, and row B9 covers its accepted form.
    - The include, census, harness, and clause 19 claims now cite file lines.
    - Evidence step 1 and the integrator's freeze step 2 record each claim. The smoke files' remaining claim stays marked [INFERENCE] until step 1 runs.
12. **Minor: case 14 measures no stack.** The ADR sentence now names case 13's D1 to D5 and the compile-only probe.
13. **Minor: the exit status of a parser limit.** Status 4 now covers a limit from the parser or the runtime. Case 17 gains `deep.js`, whose expected line is whatever `fairpane-js-parse` prints for the same file, beginning `limit depth @`. This avoids an inferred offset.
14. **Note: the case 7 literal confirms itself.** ADR 0012 now lists every new kind and layout before `tests-before.log`, and the README diffs the implemented literal against the ADR.
15. **Note: Identity lacked gates and reviewers.** Identity now lists the required gates and reviewers.

### Second check and freeze

Agent Check0100 checked revision 2 (`out/drafts/FP-0128-check-r2.json`) and found every earlier finding resolved except for one new major finding and three minor findings, with one note.
The integrator applied each recommendation at the freeze:

- Major, width rule: the per-code-unit bound replaces the token-and-depth sum, which no ADR could show for `max_depth = maxInt(u32)`, and stop rule 9 names a syntax form instead of an `Options` value.
- Minor, evidence step 1: `findstr` uses `/c:` for the two literal searches and `/r` word-boundary patterns for the 57 names, and `facts.log` records `EXTRACT.json` of the searched extraction.
- Minor, cell limit: every representation's `max_cell_index` space, not only tagged-index, maps to `limit cells`.
- Minor, stop rule 6: case 13 D5 and case 12 L1 to L4 always stay in `zig build test`, and a moved control's run is recorded.
- Note, provenance: `facts.log` records `git diff --stat 2c85bd3 HEAD -- src build.zig` instead of citing the local reflog.

Check0100's confirmation of revision 3 returned freeze with one minor finding and one note, which the integrator applied at the freeze: `git diff --stat` replaces `git log --oneline`, which lists no paths, and the width rule allows a fixed number K of slots per record.
