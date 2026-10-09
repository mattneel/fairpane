# Mechanical qualification

## Release meaning

A release profile freezes the capability matrix, standards snapshots, target matrix, and performance budgets.
A profile is broad enough to represent the declared product rather than a convenient passing subset.
The owner or an explicitly delegated body approves scope changes.

The initial `engineering/qualification.json` is a scaffold with required capability families.
It is deliberately not a frozen release profile.
Missing manifests, thresholds, or evidence make `release-check` fail.
No file in this archive supplies browser conformance results.

## Test layers

- Unit tests exercise narrow semantics and lifetime contracts.
- Metamorphic tests compare equivalent executions and incremental paths.
- Differential tests compare independent implementations and trigger standards review on disagreement.
- WPT exercises web-platform behavior through a real engine adapter.
- Test262 exercises ECMAScript behavior through the actual runtime.
- Replay workloads exercise complete application interactions and resource boundaries.
- Fuzz and fault tests exercise hostile input, allocation failure, and containment.
- Wrapper tests exercise actual foreign runtimes and native lifetimes.
- Browser shell workflows exercise the Rust wrapper, the engine-rendered chrome, and the public embedding contract.
- Separate C-only, minimal Rust, and browser-shell consumers prove that each embedder obtains the same engine capabilities.
- Shared extension scenarios compare each language's reference extension against an independent expected result, not against another implementation.
- Existing browser extensions qualify compatibility separately from extension-language parity.

WPT includes JavaScript tests, so a static renderer cannot claim their execution. [S19]
Test262 does not substitute for browser integration. [S08]
Upstream corpus revisions and local expectation policies remain separate.

## Required result categories

Each manifest preserves total discovered tests and total selected tests.
Results distinguish pass, fail, unsupported, excluded, crash, timeout, and harness error.
Exclusions require applicability reasons and independent approval.
Required behavior cannot become excluded merely because the engine fails it.

A frozen profile requires every applicable required test to pass.
A reference-image tolerance needs a recorded rationale before the run.
An implementation worker cannot widen tolerances to land its patch.

## Evidence

A result binds its source digest and policy digest to exact commands.
It identifies the compiler, operating system, architecture, and relevant hardware.
It hashes logs and output artifacts.
It records resource limits, seeds, and the complete test denominator.

The local controller writes unsigned integrity receipts.
It does not produce trusted external attestations.
`evidence-check` detects stale source and altered logs, but it cannot prove an honest worker.
Release evidence therefore consists of signed result records from a protected runner.
`attest-verify` runs from a verifier copy that the candidate workspace cannot modify, as ADR 0002 records.
It checks each record against trust input outside the candidate repository and a full commit ID in that repository.
Independent execution and protected policy remain release requirements.

## Performance

Budgets require named workloads and reference hardware.
They cover startup, interaction tails, peak memory, binary size, and power where measurable.
The benchmark preserves raw samples and environmental metadata.
No universal timing number is invented in this bootstrap.

Performance work compares generic and optimized paths under the same semantics.
A local microbenchmark win needs an integrated workload check.
Compiler changes receive their own before-and-after report.

## Completion procedure

1. Freeze the release profile and source corpus revisions.
2. Check the profile's required capabilities and target coverage.
3. Run the protected qualification suite against a clean candidate.
4. Review exclusions and all unresolved security findings independently.
5. Check performance against the frozen budgets.
6. Check wrapper and application workflows on actual targets.
7. Obtain the required release approvals.
8. Publish the evidence and known limitations with the release.

## Anti-gaming rules

A success status without actual execution is a failure.
A test that asserts a constant instead of the requested behavior is a failure.
A hardcoded fixture screenshot is not renderer qualification.
A wrapper around another engine violates the first-party profile even when compatibility results improve.
A browser shell that calls internal engine interfaces fails both browser-product and embedding-wrappers qualification.
Bootstrap success never implies completion of a higher stage.
