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

## Upgrade procedure

1. Fetch the official Zig index through an approved network path.
2. Record the exact candidate version and artifact hashes.
3. Preserve the current lock and baseline results.
4. Install the candidate into a separate local directory.
5. Run correctness, ABI, safety, and performance gates.
6. Review compiler-sensitive changes separately from feature work.
7. Update the lock only after the candidate qualifies.
