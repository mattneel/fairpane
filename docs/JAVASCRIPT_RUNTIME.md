# Zig-native JavaScript runtime

## Objective

Fairpane owns the runtime rather than translating another engine's architecture into Zig.
ECMAScript observable behavior is the compatibility boundary.
The internal object model, compiler tiers, collector, and native interfaces remain first-party design choices.

No V8, JavaScriptCore, SpiderMonkey, QuickJS, or equivalent engine ships inside the canonical runtime.
Reference engines remain useful test oracles.

## Semantic construction

Three explicit catalogs organize repetitive machinery.
The operation catalog describes operands, results, effects, and semantic kernels.
The heap catalog describes reference kinds and object layout.
The platform catalog combines Web IDL behavior with implementation-specific effects.

Comptime can specialize code and check structural relationships. [S05]
First-party Zig generators handle large offline transformations.
The project measures compile cost and generated code size as well as runtime speed.

An annotation is not proof of semantic purity.
Restricted contexts separate leaf operations from allocation-capable or callback-capable operations.
Tests force collection and callbacks at legal boundaries.
Indirect calls still require explicit effects.

## Values and objects

The first representation experiment compares compact tagged values on qualified targets.
NaN boxing and pointer compression remain measured candidates.
No value bit pattern becomes part of the public embedding ABI.
The engine preserves signed zero, NaN behavior, and required numerical results. [S06]

Ordinary objects can use shapes and inline slots.
Arrays can specialize storage after guarded observations.
Prototype changes and unusual receivers invalidate or bypass those assumptions.
Accessors and proxies retain general property semantics.

Cache-line alignment is selective.
The benchmark compares object density, traversal locality, and interference between workers.
Padding every small object to a cache line is not a standing rule.

## Strings

JavaScript strings preserve UTF-16 code units, including unpaired surrogates. [S06]
The storage design can use one-byte strings when every code unit fits.
String indexing never silently changes to Unicode scalar or grapheme indexing.

DOMString and USVString conversions have different contracts. [S07]
The engine keeps conversion boundaries explicit.
Every exposed text offset names its unit.

## Execution contexts

One engine can host several isolated execution contexts.
A context shares no global object and no page reference with any document context.
Extension code runs in such a context through public runtime facilities, never inside a page's context.
The extension adapter settles each Promise within its context's normal job processing.

## Execution tiers

The runtime retains a generic execution mode as an independent optimization reference.
An adaptive bytecode mode specializes sites after observations.
Guard failure returns to canonical semantics.
Every speculative frame has a recoverable logical-state description.

Register bytecode is an initial experiment, not a founding commitment.
Dispatch experiments compare generated machine code on actual targets.
Superinstructions require a code-size budget and end-to-end evidence.

A first-party baseline JIT is an early research track.
A Zig-generated stencil approach competes with a small first-party assembler.
A future script cannot execute at comptime before the script exists.
Comptime constructs specialization machinery, not unknown future program results.

Arbitrary compiled functions do not automatically qualify as relocatable stencils.
Patch sites, calling conventions, stack maps, and compiler helpers need explicit contracts.
The generic engine remains supported when a platform disallows executable memory.

## SIMD and numerical policy

- Lexer kernels can classify bytes and search delimiters with a complete scalar fallback.
- String kernels can compare or search code units with checked tails.
- Hash metadata can use vector comparisons before exact key checks.
- Collector bitsets can use vector operations without losing references.
- Proven numerical kernels can specialize after alias and effect checks.

A generic JavaScript callback loop is not automatically a pure vector operation.
Target feature selection prevents unsupported instructions on older hardware.
Every vector kernel faces scalar equivalence tests and end-to-end measurements.
Fast floating-point transformations cannot discard required JavaScript behavior.

## Collector and DOM

A precise tracing system covers JavaScript and reachable DOM objects.
Temporary compiler and layout data use separate bounded arenas.
Immutable scenes and decoded resources use explicit ownership.
Foreign handles register roots when required.

The target design includes a nursery and incremental collection work.
The first implementation can use a simpler collector with compatible root and barrier contracts.
Concurrent movement requires evidence about pauses and parallel work.
Weak references and finalization need their own specification tests.

Web IDL native calls stay inside Zig.
A fast setter path checks the receiver and resolved property behavior.
Argument conversion can execute user code, so roots remain valid across conversion. [S07]
The fast path calls the canonical DOM mutation operation rather than bypassing side effects.

## Qualification

Test262 measures ECMAScript conformance, not all DOM behavior. [S08]
WPT and integrated app workloads measure platform behavior.
Collector stress and relocation stress test internal lifetime rules.
Deoptimization tests compare generic and optimized traces.

RegExp, BigInt, Intl, modules, workers, and WebAssembly remain explicit obligations.
A fast arithmetic benchmark does not establish runtime completeness.
