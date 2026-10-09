# Roadmap without a deadline

## Stage model

Stages describe evidence, not dates.
Security and script architecture begin during foundation work.
The browser shell appears during the first vertical slice.
It is written in the first-party wrapper language on the public embedding contract from its first line.
The project does not postpone application usability until every engine feature exists.

| Stage | Deliverable | Exit evidence |
| --- | --- | --- |
| Foundation | Reproducible build, host lifecycle, C boundary, first-party wrapper, and evidence laboratory. | Actual target execution, lifetime tests, wrapper execution, and trustworthy result capture. |
| Vertical slice | Multilingual document output in a native shell window, driven through the first-party wrapper, with early script integration. | Real parser-to-frame execution through the public contract and app input traces. |
| Document fidelity | Broad HTML, CSS, text, images, SVG, and incremental behavior. | Frozen relevant manifests without concealed omissions. |
| Interactive platform | Complete runtime integration, DOM APIs, storage, networking, and application workflows. | Test262, WPT, and app workload evidence. |
| Hostile-web qualification | Broker, sandbox, resource controls, and failure containment. | Fault injection and independent security review. |
| Full browser qualification | Broad guest APIs, media, wrappers, and declared platform support. | A frozen full-profile matrix with passing evidence. |
| Stewardship | Sustainable releases and successful independent integrations. | Reproducible releases, operational response, and adoption evidence. |

## Initial frontier

`engineering/plan.json` defines concrete initial tasks.
`engineering/workstreams.json` defines the larger implementation obligations.
A workstream cannot close merely because its first task closes.
New task contracts preserve the workstream's unmet behavior.

The runtime and rendering teams can work concurrently after shared lifetime contracts stabilize.
Text work starts before a polished Latin-only demo.
Optimization experiments start early without replacing the generic correctness path.

## Initial non-ratified targets

Windows x86-64 is the first native execution target.
Linux and macOS require native execution before supported status.
AArch64 receives the same rule.
WebAssembly, mobile ports, and wrappers each need separate runtime qualification.

A cross-build proves only that compilation succeeded.
The target matrix never confuses that result with functional execution.
