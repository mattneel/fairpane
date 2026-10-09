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

Rust is the first-party wrapper language and the browser-shell language, as ADR 0004 records.
The initial pin is stable Rust 1.99.0, released on October 1, 2026.
`toolchains/rust.lock.json` records the exact toolchain version and the digests of its official artifacts.
`rust-toolchain.toml` names that exact version, so a rustup user's Cargo commands select it.
The repository's commands run the locked toolchain by path, never a Rust toolchain from `PATH`.
`node tools/fairpane.mjs doctor` reports only the locked toolchain, and it starts no Rust tool from `PATH` or the working directory.
Rust nightly needs a specific feature and its own qualification case.
A Rust toolchain upgrade follows the same separate-branch procedure as a Zig compiler upgrade.

The canonical wrapper crates use only the Rust standard library and toolchain facilities.
The browser application commits its `Cargo.lock` and upgrades crates through reviewed changes.
Each application crate addition or upgrade passes license, advisory, source, ban, and duplicate checks across every declared target configuration, including build dependencies.
The application adopts the newest qualified, compatible stack, not the independently newest version of every package.
A minimal Rust consumer builds the wrapper outside the browser workspace, so workspace feature unification cannot hide a wrapper defect.

## Rust installation

`node tools/fairpane.mjs install-rust` installs the locked toolchain under `.tools/rust/<version>/<platform>`.
It downloads each locked component archive from `static.rust-lang.org` and checks its size and SHA-256 before extraction.
It reads each archive with a first-party gzip and tar reader, which accepts only regular files, directories, and GNU long names inside the archive root.
The reader also rejects a path with a control character or `:`, a component that ends in `.` or a space, and a reserved Windows device name.
It rejects a GNU long name longer than 4096 bytes before it buffers the name.
It installs exactly the files that each component's `manifest.in` lists.
It checks the version, commit, and host of the staged `rustc` before it moves the toolchain into place.
It never runs rustup, changes `PATH`, or writes outside `.tools`.
On Windows, the locked host is `x86_64-pc-windows-gnu`, as ADR 0010 records.

The lock records the SHA-256 of the official channel manifest, `https://static.rust-lang.org/dist/channel-rust-<version>.toml`.
Each component digest in the lock equals that component's `hash` value in the manifest.
The Rust build infrastructure signs the manifest with the Rust signing key, whose primary fingerprint is `108F 6620 5EAE B0AA A8DD 5E1C 85AB 96E6 FA1B E5FE`.
A lock change records a GnuPG verification of that signature and a `rust-lock-verify` run in its evidence.
The installer checks the locked digests, not the signature, so it trusts the reviewed lock as `install-zig` trusts the Zig lock.

## Upgrade procedure

1. Fetch the official Zig index through an approved network path.
2. Record the exact candidate version and artifact hashes.
3. Preserve the current lock and baseline results.
4. Install the candidate into a separate local directory.
5. Run correctness, ABI, safety, and performance gates.
6. Review compiler-sensitive changes separately from feature work.
7. Update the lock only after the candidate qualifies.
