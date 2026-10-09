# Toolchain policy

## Zig master

The initial pin is `0.18.0-dev.120+9fe22a29b`.
The official Zig index listed that master build on October 8, 2026. [S00]
The lock contains six platform archives and their official SHA-256 values.

Master is an upgrade policy, not a floating build input.
A compiler upgrade uses a separate branch and evidence report.
A failed compiler download is not permission to substitute an arbitrary compiler.
The agent can propose a newer exact master pin with provenance when the old artifact becomes unavailable.

## Installation

`Get-Zig.ps1` installs the Windows archive under `.tools/zig/<version>/<platform>`.
`tools/fairpane.mjs install-zig` supports the locked Windows, Linux, and macOS platforms.
The installer checks the archive size and checksum before extraction.
It does not modify global compiler configuration.

Installed compiler files remain executable local build inputs.
The first-party lock protects against an unexpected download, not a hostile administrator who edits installed files.
A trusted runner reinstalls from verified artifacts or uses an independently managed compiler image.

## Compiler-sensitive code

Build APIs and platform I/O adapters are narrow boundaries.
The actual pinned compiler's library source is authoritative for build compatibility.
Documentation at a floating master URL can change after the lock date.
A build failure requires inspection, not a claim that an older remembered API remains valid.

## Development tools

The controller uses Node 22 or newer and no npm dependencies.
Bun is an alternative host, with its own required qualification before CI adoption.
OMP is external development infrastructure.
External conformance harness dependencies remain isolated from the renderer package.

## Rust toolchain

Rust is the first-party wrapper language, as ADR 0004 records.
The Rust wrapper and the browser shell use the current stable Rust release.
`toolchains/rust.lock.json` records the exact toolchain version and the digests of its official artifacts.
A `rust-toolchain.toml` file selects that exact version for every Cargo command.
A Rust toolchain upgrade follows the same separate-branch procedure as a Zig compiler upgrade.

A committed `Cargo.lock` pins every crate.
Each crate addition or upgrade passes a license check, a security advisory check, and a banned or duplicate crate check.
Each addition names the responsibility it serves from the allowed list in `engineering/dependencies.json`.
The project prefers the current stable release of the best-maintained crate for each responsibility.

## Upgrade procedure

1. Fetch the official Zig index through an approved network path.
2. Record the exact candidate version and artifact hashes.
3. Preserve the current lock and baseline results.
4. Install the candidate into a separate local directory.
5. Run correctness, ABI, safety, and performance gates.
6. Review compiler-sensitive changes separately from feature work.
7. Update the lock only after the candidate qualifies.
