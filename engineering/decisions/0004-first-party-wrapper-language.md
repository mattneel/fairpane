# ADR 0004: First-party wrapper language

Status: proposed; awaiting the owner's selection.
Owner: the project owner.
Date: 2026-10-09.
Related tasks: `FP-0029`, `FP-0017`, `FP-0021`, `FP-0023`.

## Context

The browser shell is written in the first-party wrapper language and reaches the engine only through the public embedding contract.
That contract is the versioned C ABI and the process protocol.
The shell therefore dogfoods the same contract that every other embedder uses.
The choice of language determines how the wrapper expresses ownership, queued host requests, threads, and native platform integration.

## Alternatives

`engineering/evidence/wrapper-language/research-report.md` compares fourteen candidates with cited primary sources.
Its scores are assessments, not measurements, and no candidate wrapper was built.

| Rank | Language | Main strength | Main risk |
| --- | --- | --- | --- |
| 1 | Rust | Safe foreign-owner model, thread-safety markers, low runtime weight, and native Windows bindings without a WebView. | A narrow unsafe perimeter and three platform adapters need sustained review. |
| 2 | C++ | The most direct native platform reach and RAII owners. | No language-level protection against lifetime and race defects in the privileged host. |
| 3 | C# with .NET NativeAOT | Managed ownership, tasks, and cancellation for a Windows-first host. | Retained GC and runtime machinery, and WPF or Windows Forms do not qualify under NativeAOT. |
| 4 | Swift | ARC, actors, and direct AppKit integration. | Windows and Linux chrome adapters and runtime packaging need deliberate work. |
| 5 | Go | Strong queued-host and cancellation idioms. | Cgo pointer rules, thread affinity, a GC, and weaker native UI reach. |

Zig as a C ABI consumer remains a reserve option.
It reuses the compiler pin but provides less independent foreign-language pressure.
TypeScript on Node or Bun is ineligible, because the shipped shell would carry V8 or JavaScriptCore.
TypeScript on Fairpane's own future runtime is a later self-hosting candidate, not an initial option.

## Decision

Pending.
The owner selects the language and answers the open questions below.

## Open questions for the owner

1. Which language is first-party, and which priorities order the choice?
2. Which chrome model comes first: native trusted widgets, chrome rendered by Fairpane through the public contract, or a stated hybrid?
3. Which host dependencies are acceptable, such as a declared GTK dependency on Linux or small native shims?
4. Where does the shell call the C ABI, and where does the process protocol run?

## Consequences

`FP-0029` starts after the selection and pins the selected toolchain.
`FP-0017` writes the first shell window in the selected language.

## Reversal condition

A recorded measurement or qualification failure that the selected language cannot address within the public contract.

## Sources and evidence

- `engineering/evidence/wrapper-language/research-report.md`
- `engineering/evidence/wrapper-language/research-output.json`
- `engineering/evidence/wrapper-language/research-attribution.log`
