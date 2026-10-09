# FP-0011 task contract

## Identity

Task ID: `FP-0011`, "Establish JavaScript semantic and heap catalogs".
Workstream: `javascript`.
Base: commit `8af0f20`.
Prerequisites: `FP-0005` and `FP-0009`, accepted.
The `fairpane-js` worker `FP0011Contract` drafted this contract, and the root integrator froze it.
Assigned role: `fairpane-js`.

## Sources

- ECMA-262, ECMAScript 2027 Language Specification draft, retrieved 2026-10-08.
  - Data types and values, including the String type, the Number type, `Number::add`, `Number::sameValue`, `Number::toString`, `BigInt::add`, `BigInt::toString`, string-concatenation, and Table 1 "Well-known Symbols": <https://tc39.es/ecma262/multipage/ecmascript-data-types-and-values.html>.
  - Abstract operations `ToPrimitive`, `OrdinaryToPrimitive`, `ToNumeric`, `ToNumber`, `StringToNumber`, `RoundMVResult`, `ToString`, `ToPropertyKey`, `IsCallable`, `SameValue`, `GetMethod`, and `Call`: <https://tc39.es/ecma262/multipage/abstract-operations.html>.
  - `OrdinaryGetPrototypeOf`, `OrdinaryPreventExtensions`, `OrdinaryGetOwnProperty`, `OrdinaryDefineOwnProperty`, `ValidateAndApplyPropertyDescriptor`, `OrdinaryGet`, and built-in function objects: <https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html>.
  - `ApplyStringOrNumericBinaryOperator`: <https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-applystringornumericbinaryoperator>.
  - White space and line terminators: <https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-white-space> and `#sec-line-terminators`.
  - `Error.prototype.message`, `Error.prototype.name`, NativeError constructors, and `TypeError`: <https://tc39.es/ecma262/multipage/fundamental-objects.html>.
- Zig language reference for the locked compiler `0.18.0-dev.120+9fe22a29b`: the file `doc/langref.html` of the locked archive in `toolchains/zig.lock.json`, SHA-256 `c78e915171942cddbe540200ba3ac14ecbb9e3a90b4f546933eb33e1c891da99`. Sections `#comptime`, `#compileError`, `#typeInfo`, `#struct`, `#extern-struct`, `#packed-struct`, `#Error-Union-Type`, `#inline-for`, `#embedFile`, and `#Exporting-a-C-Library`. The online master edition is [S05] <https://ziglang.org/documentation/master/>.
- The pinned standard library of the locked compiler: `lib/std/fmt/float.zig` (`binaryToDecimal`, the Ryū algorithm of <https://dl.acm.org/doi/pdf/10.1145/3360595>), `lib/std/fmt/parse_float.zig` (`parseFloat`), and `lib/std/math/big/int.zig`.
- Unicode 18.0.0 `ucd/extracted/DerivedGeneralCategory.txt`: <https://www.unicode.org/Public/18.0.0/ucd/extracted/DerivedGeneralCategory.txt>, 282143 bytes, SHA-256 `d6b151d2d40ee9b1876d26f417980f45ffae47b6055ccf7203cb31f07a030f94`, lines 3553 through 3561, general category `Zs`.
- `engineering/evidence/FP-0009/CONTRACT.md`, "Trace roots", and `src/dom.zig` for `retain`, `release`, `sweep`, and `forEachRoot`.
- `docs/JAVASCRIPT_RUNTIME.md` and `docs/QUALIFICATION.md`, "Performance".

### Observed facts that shaped the decisions

The locked compiler rejects a non-extern struct as a parameter or return type of a `callconv(.c)` function, with "not allowed in function with calling convention".
It rejects such a struct as an `extern struct` field, with "extern structs cannot contain fields of type".
It reports all three errors in one compilation.
It accepts a pointer to a non-extern struct in a `callconv(.c)` signature.
In the locked compiler, `@typeInfo` of a struct has no `decls` field, so no check can enumerate declarations.
These facts come from probes run with the locked compiler on 2026-10-08.

The `repo-check` import lint accepts only `std`, `builtin`, and `root` as named imports in `src`.
A build-options module would need an `engineering/dependencies.json` change, which is outside this task's writable paths.
The runtime is therefore a comptime-generic namespace over the value representation, and one test binary exercises every representation.

ECMA-262 marks every call site that can call user code with the `e-user-code` annotation.
On 2026-10-08, every operation of this catalog with the callback effect had at least one annotated call site, and no leaf operation had one.
This corroborates the effect flags; it is not a test input.

Node v26.7.0, a reference engine on the development host, cross-checked every frozen number vector in this contract.
No test runs a reference engine.

## Behavior

### Files

| File | Content |
| --- | --- |
| `src/js/operations.zig` | The operation catalog, the effect algebra, and catalog validation. |
| `src/js/value.zig` | The representation enumeration, the interface check, and `CellRef`. |
| `src/js/value_reference.zig` | The generic reference representation. |
| `src/js/value_nan_box.zig` | The NaN-boxing candidate. |
| `src/js/value_tagged_index.zig` | The tagged-index candidate. |
| `src/js/heap_catalog.zig` | Reference kinds, layouts, kind metadata, and the generated tracer and finalizer. |
| `src/js/heap.zig` | The cell table, allocation, roots, the collector, the manual tracer, stress modes, and the test-only verifier. |
| `src/js/number.zig` | `Number::add`, `Number::sameValue`, `Number::toString` for radix 10, and `StringToNumber`. |
| `src/js/number_vectors.zig` | The frozen vector tables of cases 21 through 23. |
| `src/js/runtime.zig` | `Runtime(representation)`: contexts, kernels, kernel binding, and `invoke`. |
| `src/js/measure.zig` | The measurement harness. |
| `src/js/measure_main_reference.zig`, `measure_main_nan_box.zig`, `measure_main_tagged_index.zig` | One executable root per representation. |
| `tests/compile_fail/*.zig` | The compile-failure fixtures of cases 4, 5, 8, and 20. |
| `build.zig` | The compile-failure checks inside `zig build test`, and the `measure` step. |
| `src/root.zig` | `pub const js = @import("js/runtime.zig");` and test references. |
| `engineering/decisions/0008-javascript-values-and-heap.md` | The architecture decision record. |

The task changes no file under `include` or `api`, and it changes neither `src/c_api.zig`, `src/abi_generated.zig`, nor `src/dom.zig`.

### Operation catalog

#### Data format

The catalog is a Zig declaration in `src/js/operations.zig`.

```zig
pub const Effects = packed struct(u4) {
    callback: bool = false,
    allocation: bool = false,
    exception: bool = false,
    heap_mutation: bool = false,
};
pub const Type = enum {
    number, boolean, value, primitive, object, string, string_units, bigint,
    property_key, numeric, method, optional_object, property_descriptor,
    optional_property_descriptor, preferred_type, optional_preferred_type, arguments,
};
pub const Operand = struct { name: []const u8, type: Type };
pub const Operation = struct {
    id: OperationId,
    name: []const u8,
    anchor: []const u8,
    operands: []const Operand,
    result: Type,
    effects: Effects,
};
pub const catalog: []const Operation = &.{ ... };
```

`OperationId` is an enumeration with one member per catalog entry.
`name` is the ECMA-262 operation name, and `anchor` is its ECMA-262 fragment identifier.
A Zig declaration is the format because the comptime binding check needs the kernel's function type in the same compilation.
A JSON or ZON file cannot name a Zig function, so it would need a second table that binds kernels, which is a second convention.
The catalog is small, so no offline generator is needed yet.

`writeTable(writer)` renders the catalog as one line per entry: `id|name|anchor|operand:type,...|result|effects`.
The effect set renders in the fixed order `callback`, `allocation`, `exception`, `heap_mutation`, comma-separated inside braces, and an empty set renders as `{}`.

#### Effects

| Flag | Meaning |
| --- | --- |
| `callback` | The operation can run user code: a built-in function behavior, a getter, or a method. User code can do anything, so this flag requires the other three. |
| `allocation` | The operation can allocate a managed cell, so a collection can run, and it can return `error.OutOfMemory`. A caller's unrooted cell references do not survive the call. |
| `exception` | The operation can return `error.Throw` with the thrown value in the heap's pending-exception slot. An engine-thrown error object is a new cell, so this flag requires `allocation`. |
| `heap_mutation` | The operation can change the script-visible state of a cell that existed before the call: its properties, its prototype, or its extensibility. Initializing a new cell is not a mutation. |

An entry's effects are an upper bound over every input.
`validate(entries)` rejects an entry whose `callback` lacks any of the other three flags, an entry whose `exception` lacks `allocation`, and a duplicate `id` or `name`.
`permits(context, operation)` holds exactly when every flag of the operation is also a flag of the context.

#### Operations

The catalog contains exactly these 23 entries in this order.
The effect `all` means `{callback, allocation, exception, heap_mutation}`.

| # | `id` | `name` | `anchor` | Operands | Result | Effects |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `number_add` | `Number::add` | `sec-numeric-types-number-add` | `x: number`, `y: number` | `number` | `{}` |
| 2 | `number_same_value` | `Number::sameValue` | `sec-numeric-types-number-sameValue` | `x: number`, `y: number` | `boolean` | `{}` |
| 3 | `same_value` | `SameValue` | `sec-samevalue` | `x: value`, `y: value` | `boolean` | `{}` |
| 4 | `is_callable` | `IsCallable` | `sec-iscallable` | `arg: value` | `boolean` | `{}` |
| 5 | `string_to_number` | `StringToNumber` | `sec-stringtonumber` | `string: string_units` | `number` | `{}` |
| 6 | `ordinary_get_own_property` | `OrdinaryGetOwnProperty` | `sec-ordinarygetownproperty` | `obj: object`, `key: property_key` | `optional_property_descriptor` | `{}` |
| 7 | `ordinary_get_prototype_of` | `OrdinaryGetPrototypeOf` | `sec-ordinarygetprototypeof` | `obj: object` | `optional_object` | `{}` |
| 8 | `ordinary_prevent_extensions` | `OrdinaryPreventExtensions` | `sec-ordinarypreventextensions` | `obj: object` | `boolean` | `{heap_mutation}` |
| 9 | `number_to_string` | `Number::toString` | `sec-numeric-types-number-tostring` | `x: number` | `string` | `{allocation}` |
| 10 | `bigint_add` | `BigInt::add` | `sec-numeric-types-bigint-add` | `x: bigint`, `y: bigint` | `bigint` | `{allocation}` |
| 11 | `bigint_to_string` | `BigInt::toString` | `sec-numeric-types-bigint-tostring` | `x: bigint` | `string` | `{allocation}` |
| 12 | `string_concat` | `string-concatenation` | `string-concatenation` | `a: string`, `b: string` | `string` | `{allocation}` |
| 13 | `ordinary_define_own_property` | `OrdinaryDefineOwnProperty` | `sec-ordinarydefineownproperty` | `obj: object`, `key: property_key`, `desc: property_descriptor` | `boolean` | `{allocation, heap_mutation}` |
| 14 | `call` | `Call` | `sec-call` | `func: value`, `this: value`, `args: arguments` | `value` | `all` |
| 15 | `get_method` | `GetMethod` | `sec-getmethod` | `obj: object`, `key: property_key` | `method` | `all` |
| 16 | `ordinary_get` | `OrdinaryGet` | `sec-ordinaryget` | `obj: object`, `key: property_key`, `receiver: value` | `value` | `all` |
| 17 | `ordinary_to_primitive` | `OrdinaryToPrimitive` | `sec-ordinarytoprimitive` | `obj: object`, `hint: preferred_type` | `primitive` | `all` |
| 18 | `to_primitive` | `ToPrimitive` | `sec-toprimitive` | `input: value`, `preferred: optional_preferred_type` | `primitive` | `all` |
| 19 | `to_numeric` | `ToNumeric` | `sec-tonumeric` | `arg: value` | `numeric` | `all` |
| 20 | `to_number` | `ToNumber` | `sec-tonumber` | `arg: value` | `number` | `all` |
| 21 | `to_string` | `ToString` | `sec-tostring` | `arg: value` | `string` | `all` |
| 22 | `to_property_key` | `ToPropertyKey` | `sec-topropertykey` | `arg: value` | `property_key` | `all` |
| 23 | `addition` | `ApplyStringOrNumericBinaryOperator` | `sec-applystringornumericbinaryoperator` | `left: value`, `right: value` | `value` | `all` |

`Number::toString` and `BigInt::toString` take radix 10 only.
`addition` is `ApplyStringOrNumericBinaryOperator` with the operator `+`.
`get_method` takes an Object, as `ToPrimitive` calls it; the `ToObject` step of `GetV` for primitives needs wrapper objects, which belong to `FP-0012`.

#### Operand and result types

| `Type` | Zig type in `Runtime(r)` |
| --- | --- |
| `number` | `f64` |
| `boolean` | `bool` |
| `value`, `primitive` | `Value`; a `primitive` is never an object |
| `object`, `string`, `bigint`, `property_key` | `CellRef` of an object kind, a string, a BigInt, or a string or symbol |
| `string_units` | `web_string.View` |
| `numeric` | `Numeric = union(enum) { number: f64, bigint: CellRef }` |
| `method`, `optional_object` | `?CellRef`, where null means undefined or null as the operation states |
| `property_descriptor` | `PropertyDescriptor` with optional `value`, `writable`, `get`, `set`, `enumerable`, and `configurable` fields; `get` and `set` hold `Accessor = union(enum) { undefined, function: CellRef }` |
| `optional_property_descriptor` | `?PropertyDescriptor` |
| `preferred_type` | `PreferredType = enum { string, number }` |
| `optional_preferred_type` | `?PreferredType` |
| `arguments` | `[]const Value` |

A kernel's return type follows from its effects.
Without `allocation`, it returns the result type.
With `allocation` and without `exception`, it returns `error{OutOfMemory}!T`.
With `exception`, it returns `error{ OutOfMemory, Throw }!T`.

#### Contexts and the leaf check

`Runtime(r).Context(effects)` is the only way to reach the heap.
Each kernel's first parameter is `*Context(entry.effects)`.
`ctx.invoke(comptime id, args)` narrows the context to the operation's effects and calls its kernel.
When `permits` fails, `invoke` stops compilation with `fairpane-js: a context with effects <E> cannot invoke <name>, which has effects <F>`.
`ctx.narrow(comptime effects)` returns a context with a subset of the effects and stops compilation for any other set.
No method widens a context.

Each heap primitive requires an effect set, and a context without it stops compilation with `fairpane-js: <method> requires effects <F>; the context has effects <E>`.

| Methods | Required effects |
| --- | --- |
| Reading kinds, numbers, string units, prototypes, and own properties | `{}` |
| `allocateString`, `allocateObject`, `allocateSymbol`, `allocateBigInt`, `allocateNumber`, `openScope`, and `collect` | `{allocation}` |
| `throwTypeError` | `{allocation, exception}` |
| `preventExtensions` | `{heap_mutation}` |
| Adding or changing a property of an existing object | `{allocation, heap_mutation}` |
| `callBehavior` | `all` |

A built-in function's behavior has the type `*const fn (*Context(all), this: Value, args: []const Value) error{ OutOfMemory, Throw }!Value`.
An indirect call therefore needs a context with every effect, and a narrower context cannot form that argument.

`bindKernels(entries, Kernels)` checks at compile time that each entry has exactly one kernel in `Kernels` and that each kernel belongs to an entry.
It checks that the kernel's first parameter is `*Context(entry.effects)`, that the remaining parameters match the operand types in order, and that the return type matches the rule above.
It stops compilation with these messages.

- `fairpane-js: kernel for <name> takes a context with effects <E>, but the operation has effects <F>`
- `fairpane-js: kernel for <name> returns error.Throw, but the operation does not have the exception effect`
- `fairpane-js: operation <name> has no kernel`

`validate` stops compilation with these messages.

- `fairpane-js: operation <name> declares callback without allocation, exception, and heap_mutation`
- `fairpane-js: operation <name> declares exception without allocation`
- `fairpane-js: duplicate operation id <id>`

#### Rooting protocol

A caller keeps every `Value` and `CellRef` argument rooted for the duration of the call.
A kernel returns its result unrooted.
A kernel roots each intermediate that it holds across an invocation with the `allocation` effect.
The stress mode of case 11 enforces this protocol at run time.

#### Implementation choices inside kernels

`Number::add` and `Number::sameValue` follow ECMA-262 exactly on `f64`.
The runtime never enables a relaxed floating-point mode.

`Number::toString` takes its shortest digits from `std.fmt.float.binaryToDecimal`.
It uses the Note 2 alternative of step 5: among the shortest digit strings it takes the closest, and on a tie the even one.
Steps 6 through 12 are first-party code that writes at most 25 code units into a fixed buffer before it allocates the result string.

`StringToNumber` implements the `StringNumericLiteral` grammar first-party over code units.
`StrWhiteSpaceChar` is U+0009, U+000A, U+000B, U+000C, U+000D, U+0020, U+00A0, U+1680, U+2000 through U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, and U+FEFF.
The `Zs` members of that list come from the Unicode 18.0.0 source above, and a source comment names that file and its SHA-256.
Input that the grammar does not match yields NaN, so a lone surrogate always does.
A decimal literal passes its first 768 significant digits, a final `1` when any later digit is nonzero, and a clamped exponent to `std.fmt.parseFloat` through a stack buffer.
Only the grammar-checked digits reach `parseFloat`, so its extra syntax, such as `_`, `inf`, and hexadecimal floats, never applies.
That result is the correctly rounded value of the whole literal.
The correctly rounded value always equals the Number of one of the two RoundMVResult options, so it conforms.
A binary, octal, or hexadecimal literal of any length rounds to nearest, ties to even, from its leading 64 significant bits and a sticky bit.
`StringToNumber` therefore never allocates.

`string_concat` returns `error.OutOfMemory` when the result length overflows `usize` or the allocation fails.
No limit below that exists, and no script-visible error results.

Engine-thrown errors are `error_object` cells with `[[Prototype]]` `%TypeError.prototype%`.
Each has an own `"message"` data property with `[[Writable]]` true, `[[Enumerable]]` false, and `[[Configurable]]` true.

| Id | Thrown by | Message |
| --- | --- | --- |
| M1 | `to_primitive`, when `%Symbol.toPrimitive%` returns an object | `Symbol.toPrimitive method returned an object` |
| M2 | `get_method`, for a non-callable method | `method is not callable` |
| M3 | `ordinary_to_primitive`, when no method yields a primitive | `cannot convert object to primitive value` |
| M4 | `to_string`, for a Symbol | `cannot convert a Symbol value to a string` |
| M5 | `to_number`, for a Symbol | `cannot convert a Symbol value to a number` |
| M6 | `to_number`, for a BigInt | `cannot convert a BigInt value to a number` |
| M7 | `addition`, for a BigInt and a Number | `cannot mix BigInt and other types in addition` |
| M8 | `call`, for a non-callable value | `value is not a function` |

### Intrinsics

`Heap.init` creates an intrinsic record of cells that are always roots.
It is not a realm, and it holds no constructors or methods.

- `object_prototype`, an ordinary object with a null prototype.
- `function_prototype`, an ordinary object whose prototype is `object_prototype`.
- `error_prototype`, an ordinary object whose prototype is `object_prototype`, with `"name"` `"Error"` and `"message"` `""`.
- `type_error_prototype`, an ordinary object whose prototype is `error_prototype`, with `"name"` `"TypeError"` and `"message"` `""`.
- `symbol_to_primitive`, a symbol whose description is `"Symbol.toPrimitive"`.
- The strings `""`, `"undefined"`, `"null"`, `"true"`, `"false"`, `"default"`, `"string"`, `"number"`, `"toString"`, `"valueOf"`, `"message"`, `"name"`, `"Error"`, and `"TypeError"`.

Each intrinsic property has `[[Writable]]` true, `[[Enumerable]]` false, and `[[Configurable]]` true.
`to_string` returns the intrinsic string cell for undefined, null, true, and false.
`number_to_string` allocates a new string for every input.

### Heap catalog

#### Cells and kinds

`CellRef` is `enum(u32) { _ }`, an index into the heap's cell table.
A cell holds its kind, a mark bit, and a payload, and each payload has its own allocation, so a `*Cell` stays valid until the cell is freed.

| Kind | Language type | Object | Callable | Internal methods |
| --- | --- | --- | --- | --- |
| `string` | String | no | no | none |
| `symbol` | Symbol | no | no | none |
| `bigint` | BigInt | no | no | none |
| `heap_number` | Number | no | no | none |
| `ordinary_object` | Object | yes | no | ordinary |
| `builtin_function` | Object | yes | yes | ordinary |
| `error_object` | Object | yes | no | ordinary |
| `platform_object` | Object | yes | no | ordinary |

`IsCallable` reads the `Callable` column.
Every switch over kinds or internal methods is exhaustive, so a later kind cannot fall through.
Only the `tagged_index` representation allocates `heap_number` cells.

#### Reference kinds

Each payload field has exactly one descriptor.

| Descriptor | Zig field type | Tracing | Finalization |
| --- | --- | --- | --- |
| `plain` | Any type that contains no `CellRef`, `Value`, or `dom.NodeHandle` | none | none |
| `value` | `Value` | visits the cell when the value holds one | none |
| `cell` | `CellRef` | visits the cell | none |
| `optional_cell` | `?CellRef` | visits the cell when present | none |
| `dom_node` | `dom.NodeHandle` | none | releases the one retain that the cell holds |
| `owned_units` | `WebString` | none | frees the code units |
| `owned_limbs` | `[]const std.math.big.Limb` | none | frees the limbs |
| `owned_list(L)` | `std.ArrayList(T)` | applies `L` to each element | applies `L` to each element, then frees the list |
| `inline(L)` | a struct | applies `L` to each field | applies `L` to each field |
| `tagged_union(L...)` | a `union(enum)` | applies the active variant's layout | applies the active variant's layout |

`checkLayout(name, Payload, layout)` stops compilation with these messages.

- `fairpane-js: layout <name> does not describe field <field>`
- `fairpane-js: field <field> of layout <name> holds a heap reference but is declared plain`
- `fairpane-js: layout <name> describes field <field>, which does not exist`

The reference check walks struct, union, optional, pointer, slice, and array types recursively.

#### Layouts

| Layout | Fields |
| --- | --- |
| `string` | `units: owned_units` |
| `symbol` | `description: optional_cell` |
| `bigint` | `positive: plain`, `limbs: owned_limbs` |
| `heap_number` | `value: plain` |
| `ObjectHeader` | `prototype: optional_cell`, `extensible: plain`, `properties: owned_list(Property)` |
| `Property` | `key: cell`, `enumerable: plain`, `configurable: plain`, `slot: tagged_union(data: inline(DataSlot), accessor: inline(AccessorSlot))` |
| `DataSlot` | `value: value`, `writable: plain` |
| `AccessorSlot` | `getter: optional_cell`, `setter: optional_cell` |
| `ordinary_object` | `object: inline(ObjectHeader)` |
| `builtin_function` | `object: inline(ObjectHeader)`, `behavior: plain`, `host_data: value`, `host_context: plain` |
| `error_object` | `object: inline(ObjectHeader)`, `error_kind: plain` |
| `platform_object` | `object: inline(ObjectHeader)`, `node: dom_node` |

`host_context` is a `?*anyopaque` to host memory, never to a managed cell.
A host that stores values in that memory roots them itself.
`error_kind` is `enum { type_error }`.

#### Trace generation experiment

The generated tracer and the generated finalizer derive every action from the layouts at compile time.
`heap.zig` also has a hand-written tracer with one switch arm per kind, which is the reference for the experiment.
`Heap.Options.tracer` selects `.generated`, the default, or `.manual`.
Both tracers stay in the tree.

#### Collector

The collector is precise, non-moving mark and sweep.

1. Every mark bit is clear between collections.
2. Marking pushes every root on a worklist, marking each cell as it pushes it.
3. Marking pops cells and pushes their unmarked referents through the selected tracer.
4. Sweeping finalizes and frees every unmarked cell, or quarantines it, and clears every mark.

The worklist capacity always covers the live cell count, and allocation reserves it.
A collection therefore never allocates.

Roots are the scope stack, the persistent roots, the pending exception, and the intrinsic record.
`openScope()` returns a scope; `scope.push(value)` returns a `Local`; `scope.close()` pops the scope's entries.
`addPersistent(value)` returns a `Persistent`, and `removePersistent` frees it.
`forEachRoot(context, visit)` visits each root exactly once.

Allocation runs a collection first when stress mode is on or when the live cell count equals `Options.max_cells`.
If the count still equals the limit, allocation returns `error.OutOfMemory`.
Allocation reserves every buffer before it changes the heap, so a failure leaves the heap unchanged.

#### Stress and quarantine

`Options.collect_before_each_allocation` runs a full collection before every managed allocation.
`Options.quarantine_freed_cells` keeps each unreachable cell intact as dead and never reuses its slot.
Resolving a dead `CellRef` increments `stats.dead_resolutions` and returns the intact cell, so a rooting error produces a counted failure instead of undefined behavior.
Quarantined cells are finalized at `deinit`.

`stats` also counts `cells_allocated`, `collections`, `behaviors_invoked`, `throws`, and `existing_cell_writes`.
A write counts as an existing-cell write when the cell was allocated before the outermost `invoke` began.

#### DOM references

`Options.dom` is an optional `*dom.Store`, which must outlive the heap.
`allocatePlatformObject(prototype, node)` calls `store.retain(node)` before it creates the cell.
The generated finalizer of `platform_object` calls `store.release(node)`.
The FP-0009 root rules therefore keep the node's whole tree alive while the platform object lives.
A direct `store.sweep()` stays safe at any time.
No DOM node references a JavaScript cell yet, so no cross-heap cycle can form.

#### Test-only verifier

`expectInvariants` checks the free list, the live count, clear marks, that every traced reference of every live cell resolves to a live cell, that every root is live, and that the store's retains from platform objects equal the number of live and quarantined platform objects.

### Value representations

#### Interface

`Representation` is `enum { reference, nan_box, tagged_index }`.
`Runtime(r)` instantiates the whole runtime for one representation.
Each candidate file declares exactly these public members.

| Member | Type |
| --- | --- |
| `Value` | a non-extern struct or a non-extern tagged union |
| `max_cell_index` | `u32` |
| `undefined_value`, `null_value` | `Value` |
| `fromBoolean` | `fn (bool) Value` |
| `fromCell` | `fn (u32) Value`, asserting that the index is at most `max_cell_index` |
| `fromInlineNumber` | `fn (f64) ?Value`, null when the number needs a `heap_number` cell |
| `classify` | `fn (Value) Class`, where `Class` is `enum { undefined, null, boolean, number, cell }` |
| `asBoolean`, `asNumber`, `asCell` | `fn (Value) bool`, `f64`, and `u32` |
| `identical` | `fn (Value, Value) bool`, encoding identity |

`value.zig` checks each member's exact type at compile time and stops compilation with `fairpane-js: representation <r> lacks <member>` or `fairpane-js: representation <r> declares <member> with type <T>`.
The compact candidates also declare a test-only `rawBits(Value) u64`.
`Heap.numberValue(f64)` boxes a number, and `Heap.numberOf(Value)` returns the number of an inline value or a `heap_number` cell.

#### `reference`

`Value` is `union(enum) { undefined, null, boolean: bool, number: f64, cell: u32 }`, 16 bytes on 64-bit targets.
`fromInlineNumber` never returns null, and `max_cell_index` is 2^32 - 1.
This representation is the generic reference for every comparison.

#### `nan_box`

`Value` is `struct { bits: u64 }`.
A number stores its IEEE 754 binary64 bits, except that every NaN stores `0x7FF8000000000000`.
A cell stores `0xFFF9000000000000 | index`.
Undefined, null, false, and true store `0xFFFA000000000000`, `0xFFFA000000000001`, `0xFFFA000000000002`, and `0xFFFA000000000003`.
Because every NaN is canonical, no number encoding reaches `0xFFF8000000000000` or above.
`max_cell_index` is 2^32 - 1, and `fromInlineNumber` never returns null.

#### `tagged_index`

`Value` is `struct { bits: u32 }`.
An integral number from -2^30 through 2^30 - 1, except -0, stores `(n << 1) | 1` in two's complement.
A cell stores `index << 2`, so `max_cell_index` is 2^30 - 1.
Undefined, null, false, and true store `0x00000002`, `0x00000006`, `0x0000000A`, and `0x0000000E`.
Every other number, including -0, NaN, infinities, and fractions, lives in a `heap_number` cell.

#### C ABI isolation

No representation type is extern, packed, or an integer-backed enum, so the compiler rejects it in every C ABI signature and extern struct.
No file under `src/js` contains `export `, `callconv(`, `extern struct`, or `extern union`.
Neither `src/c_api.zig` nor `src/abi_generated.zig` contains `@import("js`.
No public function outside tests returns a representation's raw bits.

### Measurement

`zig build measure` installs `fairpane-js-measure-reference`, `fairpane-js-measure-nan_box`, and `fairpane-js-measure-tagged_index`.
Each executable instantiates one representation and accepts no arguments.

Before it measures, the executable checks every vector of cases 21 through 23 in its own optimize mode and exits with status 1 on any difference.
It then runs each workload once as warmup and 11 more times.
Each sample creates a fresh heap and destroys it.
Time is the monotonic `std.Io.Clock.awake` clock in nanoseconds.
A counting allocator around `std.heap.smp_allocator` records requested bytes and peak live bytes.

| Workload | Steps at full size | Checksum |
| --- | --- | --- |
| `add-small-int` | Starting from 0, set `x` to `addition(x, 1)` 1,000,000 times. | `to_string(x)` is `"1000000"` |
| `add-fraction` | Starting from 0, set `x` to `addition(x, 0.5)` 1,000,000 times. | `"500000"` |
| `get-prototype-chain` | An object has 8 prototypes, and the eighth has data property `"k"` with value 7. Add `to_number(ordinary_get(o, "k", o))` 1,000,000 times with `Number::add`. | `"7000000"` |
| `number-to-string` | For `i` from 0 through 99,999, sum the code-unit lengths of `to_string(i + 0.25)`. | `788890` |
| `object-churn` | For `i` from 0 through 99,999, create an ordinary object with data properties `"a"`, `"b"`, `"c"`, and `"d"` holding `i + 0.25`, `i + 0.5`, `i + 0.75`, and `i + 1.25`, and keep every 16th object as a persistent root. Then collect. | 6250 live ordinary objects outside the intrinsics |
| `mark-generated`, `mark-manual` | Build a rooted chain of 100,000 objects linked by `"next"`, each with the four number properties of `object-churn`. Time one collection with the generated or the manual tracer. | 100,000 marked chain objects |

The first output line is a JSON object with `format` `"fairpane-js-measure"`, `version` 1, `representation`, `value_size_bytes`, `zig_version`, `target`, `cpu_model`, `optimize`, `logical_cpus`, `executable_bytes`, `clock` `"awake"`, and `allocator` `"smp_allocator"`.
Each later line is one sample with `workload`, `sample`, `warmup`, `ns`, `cells_allocated`, `bytes_allocated`, `peak_live_bytes`, `collections`, and `checksum`.
A checksum that differs from the table makes the executable exit with status 1 after it writes every line.
The harness writes raw samples only and computes no summary.

`measure.zig` exposes the workloads with a scale divisor for case 33.
At divisor 1000, the iteration and object counts divide by 1000, and the checksums are `"1000"`, `"500"`, `"7000"`, `490`, 7, and 100.

### Decision record

`engineering/decisions/0008-javascript-values-and-heap.md` records the measured choices.
Its status is "proposed by task FP-0011, experimental".
It contains these sections.

1. The operation catalog format, the effect algebra, and the rooting protocol, with the reasons above.
2. The heap catalog, the reference kinds, the collector baseline, and the DOM retain bridge with its cycle limitation.
3. The environment: the content of `raw/doctor.log` and each harness header line.
4. For each workload, representation, and run, the minimum, median, and maximum of the 11 measured samples in nanoseconds, the peak live bytes of `object-churn`, `value_size_bytes`, and `executable_bytes`.
5. The separability outcome of each pair of representations and of the two tracers for each workload.
   A difference is separable only when the two sample ranges do not overlap in both runs.
6. The application of these pre-registered rules.
   - A compact candidate becomes `FP-0012`'s default representation only when every checksum matches, it is separably faster than `reference` on at least four of the six workloads `add-small-int`, `add-fraction`, `get-prototype-chain`, `number-to-string`, `object-churn`, and `mark-generated`, and it is separably slower on none.
   - When both candidates qualify, the one with more separably faster workloads wins, and a tie keeps `reference`.
   - The generated tracer becomes `FP-0012`'s default only when case 9 passes and `mark-generated` is not separably slower than `mark-manual` under any representation.
7. The limits: one machine, one target, microbenchmarks without an integrated workload, and no speed claim beyond the recorded samples.
   `docs/QUALIFICATION.md` requires an integrated workload check before any microbenchmark win counts.
8. The consequence that `reference`, both candidates, and both tracers remain built and tested.

Every number in the record appears in, or follows by the stated computation from, the raw measurement logs.

## Exact test cases

Zig tests live beside the code in `src/js` and run through `zig build test`.
Unless a case says otherwise, each case runs under all three representations.
After every operation in cases 9 through 33, the verifier checks the heap.

### Operation catalog

1. `writeTable` output equals a frozen literal of the 23 entries in the "Operations" table, line for line.
2. `validate(catalog)` succeeds.
   `permits` equals the subset relation for all 256 pairs of effect sets.
3. `bindKernels` succeeds for every representation, and the bound table has 23 kernels whose ids follow the catalog order.
4. These fixtures run under `zig build test` as `zig build-obj -fno-emit-bin --dep fairpane -Mroot=tests/compile_fail/<file> -Mfairpane=src/root.zig` with the locked compiler.
   Each listed failure exits with status 1, and its standard error contains the listed text.

   | Fixture | Content | Standard error contains |
   | --- | --- | --- |
   | `leaf_invokes_to_number.zig` | A `{}` context invokes `to_number`. | `fairpane-js: a context with effects {} cannot invoke ToNumber, which has effects {callback, allocation, exception, heap_mutation}` |
   | `leaf_invokes_number_to_string.zig` | A `{}` context invokes `number_to_string`. | `fairpane-js: a context with effects {} cannot invoke Number::toString, which has effects {allocation}` |
   | `allocation_invokes_call.zig` | An `{allocation}` context invokes `call`. | `fairpane-js: a context with effects {allocation} cannot invoke Call, which has effects {callback, allocation, exception, heap_mutation}` |
   | `leaf_allocates.zig` | A `{}` context calls `allocateString`. | `fairpane-js: allocateString requires effects {allocation}; the context has effects {}` |
   | `mutation_throws.zig` | A `{heap_mutation}` context calls `throwTypeError`. | `fairpane-js: throwTypeError requires effects {allocation, exception}; the context has effects {heap_mutation}` |
   | `leaf_calls_behavior.zig` | A `{}` context passes itself to a built-in behavior pointer. | `expected type` |

   `leaf_positive.zig` invokes `number_add`, `number_same_value`, `same_value`, `is_callable`, `string_to_number`, `ordinary_get_own_property`, and `ordinary_get_prototype_of` from a `{}` context and exits with status 0.
5. These fixtures exit with status 1 and contain the listed text.

   | Fixture | Content | Standard error contains |
   | --- | --- | --- |
   | `catalog_callback_alone.zig` | `validate` of an entry `BadCallback` with `{callback}`. | `fairpane-js: operation BadCallback declares callback without allocation, exception, and heap_mutation` |
   | `catalog_exception_alone.zig` | `validate` of an entry `BadException` with `{exception}`. | `fairpane-js: operation BadException declares exception without allocation` |
   | `catalog_duplicate_id.zig` | `validate` of two entries with id `number_add`. | `fairpane-js: duplicate operation id number_add` |
   | `kernel_wider_context.zig` | `bindKernels` with a `Number::add` kernel that takes `*Context({allocation})`. | `fairpane-js: kernel for Number::add takes a context with effects {allocation}, but the operation has effects {}` |
   | `kernel_undeclared_throw.zig` | `bindKernels` with a `Number::sameValue` kernel that returns `error{Throw}!bool`. | `fairpane-js: kernel for Number::sameValue returns error.Throw, but the operation does not have the exception effect` |

6. During every scenario of cases 21 through 32, the `stats` counters of an invoked operation stay at zero for each effect that it lacks.
   `cells_allocated` maps to `allocation`, `behaviors_invoked` to `callback`, `throws` to `exception`, and `existing_cell_writes` to `heap_mutation`.

### Heap catalog

7. A test renders each kind's metadata and layout as `kind|object|callable|field:descriptor,...` and compares it with a frozen literal of the "Cells and kinds" and "Layouts" tables.
8. These fixtures call `checkLayout`, exit with status 1, and contain the listed text.

   | Fixture | Content | Standard error contains |
   | --- | --- | --- |
   | `layout_undescribed_field.zig` | Layout `Probe` omits field `extra`. | `fairpane-js: layout Probe does not describe field extra` |
   | `layout_plain_reference.zig` | Field `hidden` of type `?CellRef` is declared `plain`. | `fairpane-js: field hidden of layout Probe holds a heap reference but is declared plain` |
   | `layout_missing_field.zig` | Layout `Probe` describes field `ghost`. | `fairpane-js: layout Probe describes field ghost, which does not exist` |

9. For seeds 1 through 64 of `std.Random.DefaultPrng`, a heap with at least 200 cells of every kind, including accessor properties, symbol descriptions, `host_data`, and platform objects, yields identical sorted per-cell lists of visited `CellRef` values from both tracers.
   Collections with either tracer free the same cells.
10. A collection frees unrooted cells and a two-object cycle.
    It keeps cells reachable from a scope, a persistent root, the pending exception, and the intrinsic record.
    `forEachRoot` visits each root exactly once.
    A data property holding 0.5 keeps its `heap_number` cell alive under `tagged_index`.
11. Every scenario of cases 18, 19, 24, and 25 through 32 runs again with `collect_before_each_allocation` and `quarantine_freed_cells`.
    Each observable result equals the normal run, `dead_resolutions` is 0, and `collections` is at least the scenario's `cells_allocated`.
    Scenario AD19 of case 31 is one of these scenarios.
12. A test keeps a `CellRef` to an unrooted object across `collect` under quarantine and resolves it.
    `dead_resolutions` becomes exactly 1.
13. With an FP-0009 store, a document, and a detached subtree of an element with a text child, a rooted platform object for the element keeps both nodes through `store.sweep()`.
    After the root is removed and the heap collects, the next `store.sweep()` frees both nodes and reports 2.
    `release` then returns `error.StaleHandle` for the element, and the document stays.
14. `std.testing.checkAllAllocationFailures` runs a scenario with `Heap.init`, objects, `ordinary_define_own_property`, `number_to_string`, `string_concat`, `bigint_add`, `addition` with callbacks that allocate, a platform object, and `collect`.
    Each induced failure returns `error.OutOfMemory`, leaks nothing, passes the verifier, and leaves the store's node count and the platform object retains balanced.
15. With `max_cells` equal to the intrinsic cell count plus 8, eight rooted objects allocate, and the ninth returns `error.OutOfMemory` after a collection.
    With the eight unrooted, the ninth allocation succeeds.
    `max_cell_index` is 4294967295 for `reference` and `nan_box` and 1073741823 for `tagged_index`, and `Heap.init` caps `max_cells` at `max_cell_index + 1`.
16. `deinit` of a heap with scoped, persistent, unrooted, quarantined, and platform-object cells leaks nothing under `std.testing.allocator`.
    Afterward, every retain that the heap took is released.

### Value representations

17. The interface check passes for all three representations.
    Undefined, null, false, true, and the cell indices 0, 1, and `max_cell_index` round-trip, and `classify` keeps them distinct.
    `rawBits` equals the frozen encodings of the "nan_box" and "tagged_index" sections for the immediates, for cells 0, 1, and `max_cell_index`, and for the integers 0, 1, -1, 1073741823, and -1073741824 under `tagged_index`.
18. These numbers round-trip bit for bit through `numberValue` and `numberOf`: `0x0000000000000000`, `0x8000000000000000`, `0x3FF0000000000000`, `0xBFF0000000000000`, `0x0000000000000001`, `0x8000000000000001`, `0x000FFFFFFFFFFFFF`, `0x0010000000000000`, `0x7FEFFFFFFFFFFFFF`, `0xFFEFFFFFFFFFFFFF`, `0x7FF0000000000000`, `0xFFF0000000000000`, `0x433FFFFFFFFFFFFF`, `0x4340000000000000`, `0x4340000000000001`, `0xC340000000000000`, `0x3FB999999999999A`, `0x3FE0000000000000`, `0x41CFFFFFFF800000`, `0xC1D0000000000000`, `0x41D0000000000000`, `0xC1D0000000400000`, and `0x41E0000000000000`.
    `reference` and `nan_box` allocate no cell for any of them.
    `tagged_index` allocates no cell for 0, 1, -1, 1073741823, and -1073741824, and one `heap_number` cell for each of -0, 0.5, 1073741824, -1073741825, 2147483648, and +∞.
19. Each of these NaN bit patterns produces a value that `classify` reports as a number, or a `heap_number` cell under `tagged_index`, and whose `numberOf` is NaN: `0x7FF8000000000000`, `0xFFF8000000000000`, `0x7FF8000000000001`, `0x7FFFFFFFFFFFFFFF`, `0xFFF8000000000001`, `0xFFFFFFFFFFFFFFFF`, `0x7FF0000000000001`, `0x7FF4000000000000`, `0x7FF7FFFFFFFFFFFF`, `0xFFF0000000000001`, `0xFFF7FFFFFFFFFFFF`, `0xFFF9000000000005`, and `0xFFFA000000000001`.
    Under `nan_box`, each `rawBits` is `0x7FF8000000000000`.
    `Number::add(+∞, -∞)` boxes to a NaN number under every representation.
20. Fixtures `abi_reference_value.zig`, `abi_nan_box_value.zig`, and `abi_tagged_index_value.zig` each declare an exported `callconv(.c)` function that takes the representation's `Value`, one that returns it, and an `extern struct` with a `Value` field.
    Each exits with status 1, and its standard error contains `error: parameter of type`, `error: return type`, `not allowed in function with calling convention`, and `extern structs cannot contain fields of type`.
    A Zig test reads every file under `src/js` with `@embedFile` and finds none of `export `, `callconv(`, `extern struct`, and `extern union`.
    It reads `src/c_api.zig` and `src/abi_generated.zig` and finds no `@import("js`.

### Numbers and strings

21. `Number::add` gives these results, where NaN means any NaN.

    | x | y | Result |
    | --- | --- | --- |
    | `0x8000000000000000` | `0x8000000000000000` | `0x8000000000000000` |
    | `0x0000000000000000` | `0x8000000000000000` | `0x0000000000000000` |
    | `0x8000000000000000` | `0x0000000000000000` | `0x0000000000000000` |
    | `0x3FF0000000000000` | `0xBFF0000000000000` | `0x0000000000000000` |
    | `0x7FF0000000000000` | `0xFFF0000000000000` | NaN |
    | `0x7FF0000000000000` | `0x3FF0000000000000` | `0x7FF0000000000000` |
    | `0x7FEFFFFFFFFFFFFF` | `0x7FEFFFFFFFFFFFFF` | `0x7FF0000000000000` |
    | `0x3FB999999999999A` | `0x3FC999999999999A` | `0x3FD3333333333334` |
    | `0x0000000000000001` | `0x0000000000000001` | `0x0000000000000002` |
    | `0x000FFFFFFFFFFFFF` | `0x0000000000000001` | `0x0010000000000000` |
    | `0x4340000000000000` | `0x3FF0000000000000` | `0x4340000000000000` |
    | `0x4340000000000000` | `0x4000000000000000` | `0x4340000000000001` |
    | `0x4340000000000001` | `0x3FF0000000000000` | `0x4340000000000002` |
    | `0x7FF0000000000001` | `0x3FF0000000000000` | NaN |

    `Number::sameValue` is true for (`0x7FF8000000000000`, `0xFFF0000000000001`), (`0x8000000000000000`, `0x8000000000000000`), and (`0x3FF0000000000000`, `0x3FF0000000000000`).
    It is false for (`0x0000000000000000`, `0x8000000000000000`), (`0x8000000000000000`, `0x0000000000000000`), (`0x7FF0000000000000`, `0xFFF0000000000000`), and (`0x0000000000000001`, `0x8000000000000001`).
22. `Number::toString` returns these code units.

    | Bits | Result | Bits | Result |
    | --- | --- | --- | --- |
    | `0x0000000000000000` | `0` | `0x8000000000000000` | `0` |
    | `0x7FF8000000000000` | `NaN` | `0xFFF0000000000001` | `NaN` |
    | `0x7FF0000000000000` | `Infinity` | `0xFFF0000000000000` | `-Infinity` |
    | `0x3FF0000000000000` | `1` | `0xBFF0000000000000` | `-1` |
    | `0x3FB999999999999A` | `0.1` | `0x3FD3333333333334` | `0.30000000000000004` |
    | `0x405EDD2F1A9FBE77` | `123.456` | `0x4011666666666666` | `4.35` |
    | `0x3FD5555555555555` | `0.3333333333333333` | `0x4415AF1D78B58C40` | `100000000000000000000` |
    | `0x444B1AE4D6E2EF4F` | `999999999999999900000` | `0x441AC53A7E04BCDA` | `123456789012345680000` |
    | `0x444B1AE4D6E2EF50` | `1e+21` | `0x54B249AD2594C37D` | `1e+100` |
    | `0x3EB0C6F7A0B5ED8D` | `0.000001` | `0x3EB4B3FD5942CD96` | `0.000001234` |
    | `0x3EE92A737110E454` | `0.000012` | `0x3E7AD7F29ABCAF48` | `1e-7` |
    | `0xBE7AD7F29ABCAF48` | `-1e-7` | `0x3E8421F5F40D8376` | `1.5e-7` |
    | `0x3EA0C6F7A0B5ED8D` | `5e-7` | `0x3C36B082C2148B8E` | `1.23e-18` |
    | `0x0000000000000001` | `5e-324` | `0x8000000000000001` | `-5e-324` |
    | `0x0000000000000002` | `1e-323` | `0x000FFFFFFFFFFFFF` | `2.225073858507201e-308` |
    | `0x0010000000000000` | `2.2250738585072014e-308` | `0x7FEFFFFFFFFFFFFF` | `1.7976931348623157e+308` |
    | `0xFFEFFFFFFFFFFFFF` | `-1.7976931348623157e+308` | `0x7FE0000000000000` | `8.98846567431158e+307` |
    | `0x433FFFFFFFFFFFFF` | `9007199254740991` | `0x4340000000000000` | `9007199254740992` |
    | `0x4340000000000001` | `9007199254740994` | `0xC340000000000000` | `-9007199254740992` |
    | `0x41DFFFFFFFC00000` | `2147483647` | `0xC1E0000000000000` | `-2147483648` |
    | `0x4202A05F20000000` | `10000000000` | | |

    For 100,000 bit patterns from `std.Random.DefaultPrng` seed `0x4650303131000001`, excluding NaNs, infinities, and zeros, `string_to_number(Number::toString(x))` has the bits of `x`.
    For each pattern whose significand has `k > 1` digits, neither `(k - 1)`-digit neighbor, the floor and the ceiling of the significand divided by 10, converts to `x`.
23. `StringToNumber` returns these results.
    `\uXXXX` denotes one code unit, `H` is `1.00000000000000011102230246251565404236316680908203125`, and NaN means any NaN.

    | Input | Result |
    | --- | --- |
    | empty | `0x0000000000000000` |
    | ` ` | `0x0000000000000000` |
    | `\u0009\u000A\u000B\u000C\u000D\u0020\u00A0\u1680\u2000\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF42\u3000` | `0x4045000000000000` |
    | `+0` | `0x0000000000000000` |
    | `-0` | `0x8000000000000000` |
    | `-`, `+`, `.`, `1e`, `1e+`, `1_000`, `12abc`, `0x`, `-0x1F`, `0b`, `0x1p3`, `infinity`, `INFINITY`, `NaN` | NaN |
    | `0.` | `0x0000000000000000` |
    | `.5` | `0x3FE0000000000000` |
    | `5.` | `0x4014000000000000` |
    | `00012` | `0x4028000000000000` |
    | `0x1F`, `0X1f` | `0x403F000000000000` |
    | `0o17` | `0x402E000000000000` |
    | `0b101` | `0x4014000000000000` |
    | `Infinity`, `+Infinity` | `0x7FF0000000000000` |
    | `-Infinity` | `0xFFF0000000000000` |
    | `0.1` | `0x3FB999999999999A` |
    | `9007199254740993` | `0x4340000000000000` |
    | `9007199254740995` | `0x4340000000000002` |
    | `18014398509481985` | `0x4350000000000000` |
    | `0x1fffffffffffff` | `0x433FFFFFFFFFFFFF` |
    | `0x20000000000001` | `0x4340000000000000` |
    | `0x20000000000003` | `0x4340000000000002` |
    | `0x10000000000000000000` | `0x44B0000000000000` |
    | `0b` followed by 54 `1` digits | `0x4350000000000000` |
    | `1e1000` | `0x7FF0000000000000` |
    | `-1e1000` | `0xFFF0000000000000` |
    | `1e-400` | `0x0000000000000000` |
    | `-1e-400` | `0x8000000000000000` |
    | `4.9406564584124654e-324` | `0x0000000000000001` |
    | `2.4703282292062328e-324` | `0x0000000000000001` |
    | `2.4703282292062327e-324` | `0x0000000000000000` |
    | `1.7976931348623158e308` | `0x7FEFFFFFFFFFFFFF` |
    | `1.7976931348623159e308` | `0x7FF0000000000000` |
    | `123456789012345678901234567890` | `0x45F8EE90FF6C373E` |
    | `H` | `0x3FF0000000000000` |
    | `H` followed by `1` | `0x3FF0000000000001` |
    | `H` followed by 950 `0` digits and `1` | `0x3FF0000000000001` |
    | `H` followed by 951 `0` digits | `0x3FF0000000000000` |
    | `1` followed by 999 `0` digits | `0x7FF0000000000000` |
    | `0.` followed by 400 `0` digits and `1` | `0x0000000000000000` |
    | `\u180E1`, `1\u0085`, `\uD800`, `1\uDC00`, `1\u0000` | NaN |

24. A string cell of the 65,536 code units 0x0000 through 0xFFFF in order keeps every unit through `string_concat` with itself, `to_string`, which returns the identical cell, and `to_property_key`.
    Defining and getting a property under that key returns the stored value.
    `same_value` is true for two separately allocated copies and false when one unit differs.
    `string_concat` of `\uD83D` and `\uDE00` gives exactly `D83D DE00`, and of `\uDE00` and `\uD83D` gives `DE00 D83D`.
    Properties keyed `\uDC00`, `\uFFFD`, and `\uDC00\u0000` are three distinct properties.

### Operation semantics

25. `call` of a built-in function passes `this` and the arguments unchanged and returns its result.
    `call` of an ordinary object and of the number 1 throws M8.
    `get_method` returns null for undefined and null property values, the function for a callable one, and throws M2 for the number 1.
    `is_callable` is true only for a built-in function among a built-in function, an ordinary object, an error object, a platform object, a string, and a number.
    `same_value` is true for two distinct BigInt cells with value 5, true for NaN and NaN, and false for +0 and -0.
26. On an empty extensible object `O`, these hold in order.

    | Step | Action | Result |
    | --- | --- | --- |
    | OD1 | Define `"a"` with value 1 and every attribute true. | true; `ordinary_get_own_property` returns exactly that descriptor |
    | OD2 | Define `"b"` with only value 2. | true; writable, enumerable, and configurable are false |
    | OD3 | `ordinary_prevent_extensions(O)`, then define `"c"`. | true, then false; `O` is unchanged |
    | OD4 | On `"b"`: configurable true; enumerable true; a getter; writable true; value 3; value 2. | false, false, false, false, false, true |
    | OD5 | Before OD3, define non-configurable, non-writable `"z"` holding +0 and `"n"` holding NaN `0x7FF8000000000000`. Then define `"z"` with value -0, and `"n"` with value NaN `0xFFF0000000000001`. | false for `"z"`, which still holds +0; true for `"n"`, which still holds a NaN |
    | OD6 | On `"a"`: a getter `f`. | true; an accessor with getter `f`, setter undefined, and enumerable and configurable true |
    | OD7 | On `"a"`: value 5. | true; a data property with value 5, writable false, and enumerable and configurable true |
    | OD8 | On `"a"`: enumerable false. | true; only enumerable changes |
    | OD9 | On `"a"`: an empty descriptor. | true; nothing changes |

    `ordinary_get_prototype_of` returns the prototype given at creation, and null for `object_prototype`.
27. `ordinary_get` gives these results.
    OG1: an own data property returns its value.
    OG2: with `O → P1 → P2 → P3` and `"k"` 7 on `P3`, the result is 7.
    OG3: a key on no object returns undefined.
    OG4: an accessor on `P1` whose getter returns `this` returns `O`, the receiver.
    OG5: an accessor with an undefined getter returns undefined and invokes no behavior.
    OG6: a getter that throws a fresh object `V` makes the result `error.Throw`, and the pending exception is `V`.
    OG7: a symbol key and the keys `\uDC00` and `\uFFFD` each find only their own property.
    OG8: a getter that calls `collect`, allocates 1,000 objects, and returns a fresh string `g\uD800` yields exactly the units `0067 D800`.
28. `to_primitive` gives these results.
    TP1: undefined, null, true, -0, NaN, a string, a symbol, and a BigInt return unchanged, the string and symbol as the identical cell, and no behavior runs.
    TP2: a `%Symbol.toPrimitive%` method that records its argument receives `"default"`, `"string"`, and `"number"` for no preferred type, `string`, and `number`, and its result 42 is returned.
    TP3: a `%Symbol.toPrimitive%` method that returns an object throws M1.
    TP4: a `%Symbol.toPrimitive%` value of 1 throws M2.
    TP5: a `%Symbol.toPrimitive%` value of null calls `valueOf` first.
    TP6: with preferred type `string`, `toString` runs first and its `"s"` is returned.
    TP7: with preferred type `number`, a `valueOf` that returns an object is followed by `toString`, whose result is returned.
    TP8: a `valueOf` that throws `V` propagates `V`, and the call log is exactly `valueOf`.
    TP9: `valueOf` 1 and no `toString` throw M3.
    TP10: a `valueOf` that redefines `"toString"` on the input and returns an object leads to a call of the new `toString`.
    TP11: an accessor for `%Symbol.toPrimitive%` on the prototype runs with the input as receiver, and the log is the getter, then the method.
29. `to_number` returns NaN for undefined, `0x0000000000000000` for null and false, and 1 for true.
    It throws M5 for a symbol and M6 for a BigInt.
    An object whose `valueOf` returns `"0x10"` gives 16, and one whose `valueOf` returns a symbol throws M5.
    `to_numeric` returns a BigInt argument as the identical cell, returns BigInt 5 for an object whose `valueOf` returns 5n, and matches `to_number` for every other input of this case.
30. `to_string` returns the intrinsic cells for undefined, null, true, and false, and the identical cell for a string.
    It returns `-5`, `0`, and `18446744073709551617` for the BigInts -5, 0, and 2^64 + 1, and the case 22 results for numbers.
    It throws M4 for a symbol and returns exactly `0078 DC00` for an object whose `toString` returns `x\uDC00`.
    `to_property_key` returns a symbol as the identical cell, `"0"` for -0, `"1.5"` for 1.5, and `"1e+21"` for 1e21.
    For an object whose `toString` returns symbol `S`, `to_property_key` returns `S`, and `to_string` throws M4.
31. `addition` gives these results.

    | Id | Left | Right | Result |
    | --- | --- | --- | --- |
    | AD1 | 1 | 2 | 3 |
    | AD2 | `"1"` | 1 | `"11"` |
    | AD3 | 1 | `"1"` | `"11"` |
    | AD4 | true | 1 | 2 |
    | AD5 | null | 1 | 1 |
    | AD6 | undefined | 1 | NaN |
    | AD7 | `"a"` | undefined | `"aundefined"` |
    | AD8 | -0 | -0 | `0x8000000000000000` |
    | AD9 | 0.1 | 0.2 | `0x3FD3333333333334` |
    | AD10 | 1n | 2n | 3n |
    | AD11 | 2^64 as a BigInt | 1n | a BigInt whose `to_string` is `18446744073709551617` |
    | AD12 | 1n | 1 | throws M7 |
    | AD13 | `"x"` | 1n | `"x1"` |
    | AD14 | a symbol | 1 | throws M5 |
    | AD15 | `""` | a symbol | throws M4 |
    | AD16 | object `L` whose `valueOf` returns 1 | object `R` whose `valueOf` returns 2 | 3, and the behavior log is `L.valueOf`, then `R.valueOf` |
    | AD17 | `"\uD83D"` | `"\uDE00"` | exactly `D83D DE00` |
    | AD18 | 1073741823 | 1 | 1073741824, and -1073741824 + -1 is -1073741825 |
    | AD19 | an object whose `valueOf` returns a fresh string `L\uD800` | an object whose `valueOf` allocates 1,000 objects and returns `"R"` | exactly `004C D800 0052` |
    | AD20 | an object whose `valueOf` returns `addition(2, 3)` through its own context | 1 | 6 |
    | AD21 | an object whose `%Symbol.toPrimitive%` method records its argument and returns 1 | 1 | 2, and the recorded argument is `"default"` |

32. Each of M1 through M8 produces an `error_object` whose prototype is `type_error_prototype`.
    Its own `"message"` property has the frozen text and the attributes writable true, enumerable false, and configurable true.
    `takeException` returns the thrown value and clears the slot, and a fresh error object survives a `collect` between the throw and `takeException`.

### Measurement

33. At scale divisor 1000, every workload runs under all three representations, and each checksum equals the scaled value in the "Measurement" table.
    Each emitted line parses as JSON with the listed fields, the header's `value_size_bytes` is 16, 8, and 4 for `reference`, `nan_box`, and `tagged_index`, and the vector self-check passes.

### Acceptance mapping

| Plan acceptance criterion | Cases and evidence |
| --- | --- |
| Define operation effects with callback, allocation, exception, and mutation boundaries. | 1 through 6, 25 through 32 |
| Define explicit heap-reference metadata and trace generation experiments. | 7 through 16; the `mark-generated` and `mark-manual` workloads |
| Compare compact-value candidates without exposing their layout through the C ABI. | 17 through 20, 33; the measurement logs |
| Preserve numerical edge cases and arbitrary string code units in tests. | 18, 19, 21 through 24, 29 through 31 |
| Record measured design choices rather than claims of free speed. | 33; the measurement logs and the decision record |

## Evidence

Record these files under `engineering/evidence/FP-0011/raw/`.

1. `tests-before.log`: `zig build test --summary all` with the new tests and no implementation, which fails.
2. `tests-after.log`: `zig build test --summary all` with a fresh cache directory, exit status 0, and the test count.
3. `fmt.log`: `zig fmt --check src build.zig`, exit status 0.
4. `mutation-left-root.log` and `mutation-left-root.diff`: the mutation control removes the root of `leftPrimitive` in the `addition` kernel.
   It must fail case 11 on scenario AD19 with `dead_resolutions` at least 1, while case 31 still passes.
   The file hash before and after the control matches.
5. `doctor.log`: `node tools/fairpane.mjs doctor`.
6. `measure-build.log`: `zig build measure -Doptimize=ReleaseFast`.
7. `measure-<representation>-run1.log` and `measure-<representation>-run2.log` for each representation, each through `node tools/fairpane.mjs record` of `zig-out/bin/fairpane-js-measure-<representation>`.
   The runs follow the order `reference`, `nan_box`, `tagged_index`, `reference`, `nan_box`, `tagged_index`, on an otherwise idle machine, at the final implementation commit.

The integrator records `HEAD`, the staged diff, and file hashes before it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0011/gates`.

## Authority

Writable paths: `src`, `tests`, `tools`, `build.zig`, and `engineering/decisions`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No parser, bytecode, interpreter, realm, global object, execution context stack, or Test262 execution exists in this task; `FP-0012` owns them.
- No Proxy, Array, wrapper object, `ToObject`, shape, inline cache, or other exotic behavior exists.
- `Number::toString` and `BigInt::toString` support radix 10 only, and no other BigInt or Number operator exists.
- No WeakRef, FinalizationRegistry, weak reference kind, generational, incremental, concurrent, or moving collection exists.
- No Web IDL binding, DOM-to-JavaScript reference, or unified DOM marking pass exists.
- No C ABI declaration, header, or schema changes.
- No Unicode data import exists beyond the 17 `Zs` code points named above.
- No speed claim results from this task.

## Revision 1

Base: the commit that freezes this revision, whose parent is `005ef1e`.
Source finding: `engineering/evidence/FP-0011/reviews/review-1-reject.json`.
Every section above stays in force except where this revision replaces it.
Writable paths add `engineering/evidence/FP-0011`.

### Corrected observed fact

The statement that `@typeInfo` gives no way to enumerate declarations is wrong.
The locked compiler's `std.builtin.Type.Struct` has `decl_names`, which the binding check already uses.
A probe with the locked compiler records whether `decl_names` lists declarations without `pub`, and the decision record states the result.

### Enforced effect boundary

No `Context` value gives its holder a `*Heap`, a `*Runtime`, or a wider context.

- The context keeps its heap in a form that only the runtime file converts back to a heap pointer, and that conversion is not `pub`.
- The kernels live in a file other than the one that performs the conversion.
- Allocation, property mutation, throwing, collection, and calls reach the heap only through context methods whose required effects the context type must contain at compile time.
- A root context comes only from the runtime that owns the heap, through a function that takes that runtime, and never from a heap pointer or a context.

The decision record states that this boundary stops accidental reach and does not stop code that deliberately converts integers or pointers with `@ptrFromInt` or `@ptrCast`.

### StringToNumber digit scale

`stringToNumber` returns RoundMVResult of the exact mathematical value of every StrDecimalLiteral, whatever its length, digit scale, or exponent.
Scale and exponent arithmetic saturates and never overflows.
The ExponentPart saturates only at a magnitude that exceeds the literal's length by enough that the result is zero or infinity whatever its digits.
The comment on the longest `Number::toString` result names 25 code units, as in `"-0.0000012345678901234567"`.

### Revision 1 test cases

34. Compile-fail fixture `leaf_reaches_heap.zig`: a function that holds a `*Context(.{})` tries to allocate a string through the context's stored heap.
    The fixture expects a diagnostic substring that names the refused field, declaration, or type, recorded from the locked compiler.
35. Compile-fail fixture `leaf_widens_context.zig`: a function that holds a `*Context(.{})` tries to obtain a root context from what the context exposes.
    The fixture expects a recorded diagnostic substring in the same way.
36. Compile-fail fixtures for the binding check: a catalog entry without a kernel fails with `operation <name> has no kernel`, and a kernel without an entry fails with `kernel <name> belongs to no operation`, each naming the stub.
37. The fixture `leaf_calls_behavior.zig` also expects a diagnostic substring that names the `Context` parameter type, recorded from the locked compiler.
38. Number vectors, checked against Node v26.7.0 by the integrator on 2026-10-09:

    | Input | Result bits |
    | --- | --- |
    | `"0."`, then 1,000,001 `"0"`, then `"1e1000005"` | `0x408F400000000000` (1000) |
    | `"1"`, then 1,000,000 `"0"`, then `"e-1000001"` | `0x3FB999999999999A` (0.1) |
    | `"0."`, then 1,000,001 `"0"`, then `"1e1000000"` | `0x3F847AE147AE147B` (0.01) |
    | `"0."`, then 1,000,001 `"0"`, then `"1e"` and 25 `"9"` | `0x7FF0000000000000` (+Infinity) |
    | `"1"`, then 1,000,000 `"0"`, then `"e-"` and 25 `"9"` | `0x0000000000000000` (+0) |

Cases 34, 35, and 38 must fail before the fix, except the third vector, which the current code already returns.
Case 36 tests behavior that already holds, so `raw/mutation-r1.log` shows that it fails when the binding check skips each direction.

### Revision 1 evidence

The worker records these files under `engineering/evidence/FP-0011/raw/`.

1. `probe-r1.log`: the `decl_names` probe and the diagnostic text of each new or changed fixture.
2. `tests-before-r1.log`: `zig build test --summary all` on the revision base with the new tests and the old implementation.
3. `tests-after-r1.log`: `zig build test --summary all` with a fresh cache directory, exit status 0.
4. `fmt-r1.log`: `zig fmt --check src build.zig tests`, exit status 0.
5. `mutation-left-root-r1.log` and `.diff`: the left-root mutation control redone on the revised kernels.
   The log records the commands that apply and reverse the mutation and the file hashes before and after.
6. `mutation-r1.log`: the binding-check controls of case 36, recorded the same way.

The worker updates the decision record for the boundary, the probe, and the number fix.
The worker's measurement runs, if any, are not evidence.

The integrator records `HEAD` and a status that includes ignored files for every source root before the gates.
The integrator then reruns `doctor`, `measure-build`, and the six measurement runs at the integration commit on an otherwise idle machine, with no worker building.
The integrator also records the active power scheme and that the measurement processes keep the default processor affinity.
Decision record sections 3 through 6 then cite those runs and apply the pre-registered rules again.
Section 5 states any shift of sample level within a run that decides a separability outcome.
