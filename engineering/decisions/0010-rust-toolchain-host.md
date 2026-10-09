# ADR 0010: The Rust toolchain host on Windows

Status: proposed until `fairpane-review` and `fairpane-security` accept task `FP-0079`.
Owner: the root integrator.
Date: 2026-10-09.
Related tasks: `FP-0029`, `FP-0032`, `FP-0079`, `FP-0080`.

## Decision

On Windows, Fairpane's Rust toolchain uses the `x86_64-pc-windows-gnu` host.
On Linux, it uses the `x86_64-unknown-linux-gnu` host.
`toolchains/rust.lock.json` pins the components `rustc`, `cargo`, `rust-std`, and `rustfmt-preview` for both hosts.
It also pins `rust-mingw` for the Windows host.
`node tools/fairpane.mjs install-rust` installs the locked components under `.tools/rust/<version>/<platform>`.

## Evidence

The locked Zig compiler's native Windows target uses the GNU ABI, and `zig build` produces `fairpane.lib` for it.
A Rust program on the same ABI can link that library without an ABI bridge.
The `rust-mingw` component carries a self-contained MinGW linker and its import libraries.
`rustc -C link-self-contained=yes` therefore links a Windows program without a host linker.
The drafter of the `FP-0079` contract found no Visual Studio product through vswhere, so an MSVC host could not link on that machine.
`engineering/evidence/FP-0079/` records the installation, the version checks, and the smoke program on both hosts.

## Consequences

- An MSVC host and an MSVC-ABI engine library need their own qualification.
- `FP-0032` qualifies GPUI on the locked host.
- A host change is a reviewed lock change.

## Reversal condition

Revisit this decision when a required crate or platform service fails on the GNU host and works on an MSVC host.
Revisit it when the locked Zig compiler's native Windows target changes its ABI.
A reversal changes the lock, the engine library's ABI, and the evidence in one reviewed change.
