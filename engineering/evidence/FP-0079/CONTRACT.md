# FP-0079 task contract

## Identity

Task ID: `FP-0079`, "Pin and install the Rust 1.99.0 toolchain".
The integrator confirmed the ID at the freeze.
Workstream: `wrappers`.
Base: the commit that freezes this contract; the drafter read the tree at `b0e8e33`.
Prerequisites: none.
Parent criterion: `engineering/plan.json:1395`, the first acceptance criterion of `FP-0029`.
Assigned role: `fairpane-bindings`.
Authority: `routine-local-engineering`.
The `fairpane-bindings` worker `FP0029Contract-2` drafted this contract, and the root integrator froze it with the decisions below.

### Integrator decisions

The integrator confirmed each decision below at the freeze, and added the last six.

- `FP-0029` splits into `FP-0079`, then `FP-0080`, then the retained `FP-0029`.
  `FP-0029` keeps all 20 criteria word for word, and its contract maps criterion 1 to this task's accepted evidence.
- This task adds no wrapper code, so the lock lands in a reviewed change separate from the wrapper implementation.
- The Windows host is `x86_64-pc-windows-gnu`.
  The locked Zig compiler's native Windows target uses the GNU ABI, and `zig build` produces `fairpane.lib` for it.
  The `rust-mingw` component carries a self-contained MinGW linker and import libraries.
  vswhere lists no Visual Studio product on the drafting host, so the MSVC host cannot link there.
  `engineering/decisions/0010-rust-toolchain-host.md` records the choice.
- The Linux host is `x86_64-unknown-linux-gnu`.
- The lock pins the components `rustc`, `cargo`, `rust-std`, and `rustfmt-preview` for both hosts, and `rust-mingw` for the Windows host.
  It pins no `clippy`, no `rust-src`, and no cross-target standard library.
- The installer uses the `.tar.gz` archives, because `node:zlib` reads gzip and has no xz decoder.
- A reviewer checks authenticity once, when the lock is created, with GnuPG.
  The task commits the signed manifest, its signature, its `.sha256` file, and both copies of the signing key as evidence, so the check can be repeated offline.
  The installer checks each archive's size and SHA-256 against the lock, which is the trust model of the Zig pin (`docs/TOOLCHAIN.md:21-23`).
- The lock validator and the toolchain-file check live in `tools/lib.mjs` beside `validateLock`, following the existing convention.
  The manifest parser, the archive reader, the installer, and the version checks live in a new `tools/rust.mjs`, which imports `tools/lib.mjs`.
  `tools/lib.mjs` does not import `tools/rust.mjs`.
- The download-and-verify loop of `installZig` (`tools/lib.mjs:516-532`) becomes one exported function that both installers use.
  `install-zig` keeps its behavior and its messages.
- `rust-toolchain.toml` serves rustup users only.
  No repository command runs rustup or a Rust executable from `PATH`.
- `FP-0080` adopts `tests/rust/toolchain_smoke.rs` as the first step of the `rust-wrapper` gate.
- Writable paths add `docs/TOOLCHAIN.md`, `tests/rust`, and `engineering/evidence/FP-0079` to the paths that `FP-0029` allows.
- The drafter observed the archive sizes as HTTP `Content-Length` values, and the manifest does not sign them.
  The lock records them as download bounds only.
- The drafter observed a global rustup toolchain `1.99.0-x86_64-pc-windows-msvc` on the host.
  This task neither uses nor changes it.
- Policy change P1 protects the lock and inventories `rust-toolchain.toml` after the implementation commit, because `collectFiles` rejects a missing root (`tools/lib.mjs:61-78`).
- The integrator accepts the committed channel manifest as evidence that this task requires, with its URL, digest, and signature as provenance (`docs/GIT_OPERATIONS.md:40-41`).
- `AGENTS.md` stays unchanged; `docs/TOOLCHAIN.md` states that no repository command runs a Rust toolchain from `PATH`.
- `FP-0081` adds an engine allocation budget to `fp_engine_options`, so `FP-0029`'s minimal consumer can induce the `allocation-failure` scenario.
- `FP-0080` adds `rust-std` for `i686-unknown-linux-gnu` through a reviewed lock change and compiles its layout assertions for that target.
  This task pins no cross-target standard library.
- `FP-0080` uses a repository-root Cargo workspace with only the two wrapper crates, and `FP-0029` puts the minimal consumer in its own workspace under `tests/rust`.
- The integrator installed Node v26.7.0 user-locally in WSL Ubuntu at `$HOME/fairpane-linux/node`, outside `PATH`, after checking the archive against the release's `SHASUMS256.txt`.
  `engineering/evidence/hosts/wsl-ubuntu/node-install.log` records it.
  The Linux steps use that Node by its path.

## Sources

- Plan entry: `engineering/plan.json:1350-1423`, criterion 1 at line 1395.
- Toolchain policy: `docs/TOOLCHAIN.md`; Zig installation at lines 14-23, the Rust toolchain at 39-52, and the upgrade procedure at 54-62.
- ADR 0004: `engineering/decisions/0004-first-party-wrapper-language.md`; the wrapper build dependencies at 86-88, independent consumers at 155-166, and the toolchain at 168-174.
- Wrapper policy: `docs/ABI_AND_WRAPPERS.md:104-106`, and `engineering/dependencies.json:15-27` and `:101-108`, with the Rust host at line 105.
- Policy: `engineering/policy.json`; `source_roots` at 4-35, `policy_roots` at 36-45, `protected_paths` at 46-54, and `required_files` at 59-79.
- Controller: `tools/lib.mjs`; `collectFiles` at 61-78, `validateLock` at 92-107, `hostPlatform` at 108-113, `compilerPath` and `checkCompiler` at 114-128, `verifyArchive` at 129-133, `checkRepository` at 197-248 with the lock check at 215-216, and `installZig` at 504-551.
- Commands: `tools/fairpane.mjs`; `help` at 25-82, `doctor` at 85-94, and `install-zig` at 122. Also `tools/README.md:23`, `:46`, and `:151`.
- Zig pin pattern: `toolchains/zig.lock.json` and `scripts/Get-Zig.ps1`.
- Git rules: `docs/GIT_OPERATIONS.md:37` and `:40-41`.
- Agent rules: `AGENTS.md:21`, `:61-62`, and `:68`.
- Official channel manifest: <https://static.rust-lang.org/dist/channel-rust-1.99.0.toml>, with `.asc` and `.sha256` files at the same path.
- Rust signing key: <https://static.rust-lang.org/rust-key.gpg.ascii>, which <https://forge.rust-lang.org/infra/other-installation-methods.html> links, and the copy at <https://keybase.io/rust/pgp_keys.asc>.
- Release announcement: <https://blog.rust-lang.org/2026/10/01/Rust-1.99.0/>.

## Behavior

### The lock (plan criterion 1)

`toolchains/rust.lock.json` is exactly this object.
The only exception is `checked_date`, which is the UTC date of the recorded GnuPG verification.

```json
{
  "schema_version": 1,
  "channel": "stable",
  "version": "1.99.0",
  "release_date": "2026-10-01",
  "checked_date": "2026-10-09",
  "rustc_commit_hash": "b940084d7eb6a299eb4bfeb8e34901bc051e7ac4",
  "manifest": {
    "url": "https://static.rust-lang.org/dist/channel-rust-1.99.0.toml",
    "sha256": "ce6dddc886364f8d786514771212cebe9b731ba82d6b859951c6b0ccc516b6a2",
    "signature_url": "https://static.rust-lang.org/dist/channel-rust-1.99.0.toml.asc",
    "signing_key_url": "https://static.rust-lang.org/rust-key.gpg.ascii",
    "signing_key_fingerprint": "108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE"
  },
  "platforms": {
    "x86_64-windows": {
      "host": "x86_64-pc-windows-gnu",
      "components": [
        { "package": "rustc", "url": "https://static.rust-lang.org/dist/2026-10-01/rustc-1.99.0-x86_64-pc-windows-gnu.tar.gz", "sha256": "3c7bad76bebfda385cc1061c1f0b625b02c212dcca5ea70b7bc6773153e6f15c", "size": 161263734, "archive_root": "rustc-1.99.0-x86_64-pc-windows-gnu" },
        { "package": "cargo", "url": "https://static.rust-lang.org/dist/2026-10-01/cargo-1.99.0-x86_64-pc-windows-gnu.tar.gz", "sha256": "125f4a389c765e59c94a12ec16cd668dfe7d6884b5e8edc8eaf2575f0162890d", "size": 18667864, "archive_root": "cargo-1.99.0-x86_64-pc-windows-gnu" },
        { "package": "rust-std", "url": "https://static.rust-lang.org/dist/2026-10-01/rust-std-1.99.0-x86_64-pc-windows-gnu.tar.gz", "sha256": "5d7f8eb792439b2e85afaf27497ff0f67e3ada0ef09adf81d564028e2aa1b90b", "size": 44949786, "archive_root": "rust-std-1.99.0-x86_64-pc-windows-gnu" },
        { "package": "rust-mingw", "url": "https://static.rust-lang.org/dist/2026-10-01/rust-mingw-1.99.0-x86_64-pc-windows-gnu.tar.gz", "sha256": "6ebe238508348b3faaabb8e259874415ce674dfcb0540392fe1a94f836e51b1b", "size": 9594875, "archive_root": "rust-mingw-1.99.0-x86_64-pc-windows-gnu" },
        { "package": "rustfmt-preview", "url": "https://static.rust-lang.org/dist/2026-10-01/rustfmt-1.99.0-x86_64-pc-windows-gnu.tar.gz", "sha256": "a32c5025c2fa54f53fba92b0be6a949d3b041541917f9d33962187c06e45217a", "size": 4938158, "archive_root": "rustfmt-1.99.0-x86_64-pc-windows-gnu" }
      ]
    },
    "x86_64-linux": {
      "host": "x86_64-unknown-linux-gnu",
      "components": [
        { "package": "rustc", "url": "https://static.rust-lang.org/dist/2026-10-01/rustc-1.99.0-x86_64-unknown-linux-gnu.tar.gz", "sha256": "238e72b8617f79bc96f27a5bfeb1a208b5755fe1a48f8bc190fe403ef6d54ab8", "size": 141398713, "archive_root": "rustc-1.99.0-x86_64-unknown-linux-gnu" },
        { "package": "cargo", "url": "https://static.rust-lang.org/dist/2026-10-01/cargo-1.99.0-x86_64-unknown-linux-gnu.tar.gz", "sha256": "c2b8ba1f59e7a230aa5522684f3f7aa620b98e5ad37683a5e5cf9b41f534fa1e", "size": 14521653, "archive_root": "cargo-1.99.0-x86_64-unknown-linux-gnu" },
        { "package": "rust-std", "url": "https://static.rust-lang.org/dist/2026-10-01/rust-std-1.99.0-x86_64-unknown-linux-gnu.tar.gz", "sha256": "1dcaa01beb6bc78fdb13815b4f15214719167c58e3d79fbdf214591f8c195ee1", "size": 50364291, "archive_root": "rust-std-1.99.0-x86_64-unknown-linux-gnu" },
        { "package": "rustfmt-preview", "url": "https://static.rust-lang.org/dist/2026-10-01/rustfmt-1.99.0-x86_64-unknown-linux-gnu.tar.gz", "sha256": "9fc3a87d3d4f6e5e2bd87e6fb8779b7a95831f533cb8cc8ae1304a797c648733", "size": 3133022, "archive_root": "rustfmt-1.99.0-x86_64-unknown-linux-gnu" }
      ]
    }
  }
}
```

Each `sha256` value is the `hash` value of the same package and target in the signed manifest.
Each `size` value is an HTTP `Content-Length` that the drafter observed, and the task confirms it by download.
`[INFERENCE]` Each `archive_root` follows the observed `rust-mingw` layout, and the installer confirms it.

### Lock validation

`validateRustLock(lock)` in `tools/lib.mjs` returns `true` or throws the first applicable message below.

- An unknown key at any level: `Unexpected Rust lock key: <key>`.
- A `schema_version` other than 1 or a `channel` other than `stable`: `The Rust lock must select a stable release.`
- A `version` that does not match `^\d+\.\d+\.\d+$`: `The Rust lock needs an exact stable version.`
- A `release_date` or `checked_date` that is not `YYYY-MM-DD`: `The Rust lock needs ISO dates.`
- A `rustc_commit_hash` that is not 40 lowercase hex digits: `The Rust lock needs the 40-hex rustc commit.`
- A `manifest.url` other than `https://static.rust-lang.org/dist/channel-rust-<version>.toml`, or a `signature_url` other than that URL plus `.asc`: `The Rust lock needs the official channel manifest.`
- A `manifest.sha256` that is not 64 lowercase hex digits: `The Rust lock needs a SHA-256 manifest digest.`
- A `signing_key_url` other than `https://static.rust-lang.org/rust-key.gpg.ascii`, or a fingerprint other than the exported constant `RUST_SIGNING_KEY_FINGERPRINT`, `108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE`: `The Rust lock must name the Rust signing key.`
- A platform key outside `x86_64-windows` and `x86_64-linux`: `Unsupported Rust lock platform: <key>`.
- A `host` other than the fixed map `x86_64-windows` to `x86_64-pc-windows-gnu` and `x86_64-linux` to `x86_64-unknown-linux-gnu`: `Unexpected Rust host for <key>.`
- A component package list that is not exactly `rustc`, `cargo`, `rust-std`, and `rustfmt-preview` in that order, followed by `rust-mingw` for a `-windows-gnu` host: `The Rust components for <key> must be exactly <comma-separated list>.`
- A `url` other than `https://static.rust-lang.org/dist/<release_date>/<stem>-<version>-<host>.tar.gz`, where `<stem>` is the package without `-preview`: `Unexpected component URL for <package> on <key>.`
- An `archive_root` other than `<stem>-<version>-<host>`: `Unexpected archive root for <package> on <key>.`
- A `sha256` that is not 64 lowercase hex digits: `Invalid archive SHA-256 for <package> on <key>.`
- A `size` that is not a positive safe integer: `Invalid archive size for <package> on <key>.`

### Toolchain selection file

`rust-toolchain.toml` is byte for byte the text that `rustToolchainText(lock)` in `tools/lib.mjs` returns:

```toml
# The repository's commands run the toolchain that node tools/fairpane.mjs install-rust installs, never one from PATH.
# This file names the version in toolchains/rust.lock.json for a developer who uses rustup.
[toolchain]
channel = "1.99.0"
profile = "minimal"
components = ["rustfmt"]
```

The file ends with one line feed.
`rustToolchainProblems(lock, text)` returns an empty list for that text.
For any other text, it returns the single message `rust-toolchain.toml names <channel or "no channel">, but the lock pins <version>.` when the channel differs, and otherwise `rust-toolchain.toml differs from the text that the lock implies.`

### Repository check and doctor

`checkRepository` loads `toolchains/rust.lock.json` and calls `validateRustLock`.
It then reads `rust-toolchain.toml` and fails with the first problem from `rustToolchainProblems`.
It runs no Rust executable.

`doctor` gains a `rust` field.
When the check passes, the field is `{ available: true, path, version }`.
Otherwise, it is `{ available: false, error, expected_path }`.
`doctor` also gains a `path_rustc` field, which is `versionOf('rustc', ['-V'])` with the note `Gates never use a Rust toolchain from PATH.`

### Manifest verification

`node tools/fairpane.mjs rust-lock-verify <manifest>` reads a repository-relative manifest file.
It prints `{ result, manifest_sha256, problems }` and exits with status 1 unless `problems` is empty.
Without an argument, it exits with status 1 and prints `Usage: rust-lock-verify <repository-relative manifest path>`.

`parseChannelManifest(text)` in `tools/rust.mjs` reads `[table]` headers, `[[array-of-table]]` headers, and `key = "string"` and `key = true|false` lines.
It ignores every other line.
`rustLockProblems(lock, manifestBytes)` reports these problems in order:

- `The manifest SHA-256 <actual> differs from the lock.`
- `The manifest date <date> differs from the release date.`
- `The manifest rustc version <version> is not <lock version>.`, when `[pkg.rustc] version` does not start with `<lock version> (`.
- `The manifest rustc commit <hash> differs from the lock.`
- `The manifest has no available <package> for <host>.`
- `The manifest URL of <package> for <host> differs from the lock.`
- `The manifest hash of <package> for <host> differs from the lock.`

Packages and targets that the lock does not name are ignored.

### Archive reader

`extractTarGz(archive, archiveRoot, destination)` streams the archive through `zlib.createGunzip` and creates `destination`.
It returns `{ files, directories }`.

- It verifies every 512-byte header checksum.
  Failure message: `The archive header checksum is invalid at offset <n>.`
- It accepts the GNU magic `ustar  \0` and the POSIX magic `ustar\0` with version `00`.
  Failure message: `The archive is not a ustar or GNU tar file.`
- It accepts type `0` or NUL as a regular file and type `5` as a directory.
  It accepts type `L` as the GNU long name of the next entry, and it joins a POSIX `prefix` field to the name.
  Any other type fails with `Unsupported tar entry type "<type>" for <name>.`
- It rejects these paths with `The archive path is not accepted: <name>`:
  - a path with a leading `/` or a drive letter;
  - a path with a backslash or NUL;
  - a path with an empty, `.`, or `..` component.
  A trailing `/` on a directory is allowed.
- It rejects a path that is neither `archiveRoot` nor under `archiveRoot/` with `The archive path is outside <archiveRoot>: <name>`.
- It rejects two entries whose paths are equal without regard to case with `The archive repeats a path: <name>`.
- It rejects a stream that ends before two zero blocks or inside an entry with `The archive ends early.`
- Outside Windows, it gives a file mode `0o755` when any execute bit is set in the header, and `0o644` otherwise.

### Component installation

`installComponents(extracted, archiveRoot, toolchain, installed)` installs one extracted archive into `toolchain`.

- It requires `<archiveRoot>/rust-installer-version` to hold `3` after trimming.
  Failure message: `Unexpected installer version <value>.`
- It reads `<archiveRoot>/components` as one or more component names that match `^[a-z0-9][a-z0-9_.-]*$`.
  Failure message: `The component list is invalid.`
- For each component, it reads `<archiveRoot>/<component>/manifest.in`.
  Each line is `file:<path>` or `dir:<path>`, and the path follows the archive path rules.
- It copies each `file:` path, and each file under each `dir:` path, from `<archiveRoot>/<component>/` to the same relative path under `toolchain`.
- A listed file that is absent fails with `<component>/manifest.in names an absent file: <path>`.
- A file in the component directory that no line covers, other than `manifest.in`, fails with `<component> holds a file that manifest.in does not list: <path>`.
- A path that an earlier component already installed fails with `Two components install <path>.`
  The shared `installed` set records every installed path.
- It installs none of the archive's top-level files, such as `install.sh`, `README.md`, the licenses, `version`, or `components`.
- It returns the component names.

### Installation

`node tools/fairpane.mjs install-rust` calls `installRust(root)` and prints its result.
`installRust(root, { platform = hostPlatform(), fetch = globalThis.fetch, run })` follows these steps:

1. Validate the lock.
   A missing platform fails with `No locked Rust toolchain exists for <platform>.`
2. Set `dest` to `.tools/rust/<version>/<platform>`.
   If `dest` exists, return `{ toolchain: checkRust(root, { platform, run }), downloaded: false }`.
3. For each component in lock order, call the shared download function for `.tools/downloads/<basename of url>`.
   The function reuses an existing archive only after a size and SHA-256 check.
   It downloads with `redirect: 'error'` into a `.partial` file, stops when the byte count exceeds `size`, verifies the result, and renames it.
   Its messages are `The download exceeded the locked archive size.`, `The <package> archive size does not match the lock.`, `The <package> archive SHA-256 does not match the lock.`, and `<package> download failed with HTTP <status>.`
4. Create a stage with `mkdtemp` at `.tools/rust/<version>/.extract-`.
5. Extract component `i` to `<stage>/<i>`.
6. Install each extracted component into `<stage>/toolchain` with one shared `installed` set.
7. Run the version checks on the staged executables.
8. Write `<stage>/toolchain/fairpane-install.json` as `{ version, platform, host, rustc_commit_hash, manifest_sha256, components: [{ package, sha256, installer_components }], source }`.
   `source` is the manifest URL.
9. Rename `<stage>/toolchain` to `dest`.
10. Remove the stage in a `finally` block.
11. Return `{ toolchain: <path of dest/bin/rustc>, downloaded: true, components }`.

The installer writes nothing outside `.tools/downloads`, `.tools/rust/<version>`, and `.tools/cargo-home`.
It never runs rustup, changes `PATH`, or edits user configuration.
Like `install-zig`, it accepts an existing toolchain directory after only a version check.

### Toolchain check

`checkRust(root, { platform, run })` resolves `bin/rustc`, `bin/cargo`, `bin/rustdoc`, and `bin/rustfmt` under `dest`, with the suffix `.exe` on Windows.
A missing executable fails with `The locked Rust toolchain is absent. Run node tools/fairpane.mjs install-rust.`
It runs `rustc -vV`, `cargo -V`, `rustdoc -V`, and `rustfmt -V` with `CARGO_HOME` set to `<root>/.tools/cargo-home`, `windowsHide`, and a 30-second timeout.
It returns the `rustc` path when `toolchainVersionProblems(lock, platform, outputs)` is empty.
Otherwise, it throws the problems joined by spaces.

`toolchainVersionProblems` reports these problems:

- `Rust toolchain mismatch: expected release <v>, commit <c>, and host <h>; found <release>, <commit>, and <host>.` when any of the `release:`, `commit-hash:`, or `host:` lines of `rustc -vV` differs.
- `cargo version mismatch: <line>` unless the line matches `^cargo <version> \([0-9a-f]{9,} \d{4}-\d{2}-\d{2}\)$`.
- `rustdoc version mismatch: <line>` unless the line matches `^rustdoc <version> \(([0-9a-f]{9,}) ` and the captured hash is a prefix of `rustc_commit_hash`.
- `rustfmt version mismatch: <line>` unless the line matches `^rustfmt \d+\.\d+\.\d+-stable \(([0-9a-f]{9,}) ` and the captured hash is a prefix of `rustc_commit_hash`.

The frozen outputs are below.
`[INFERENCE]` The drafter observed them from the rustup `1.99.0-x86_64-pc-windows-msvc` toolchain, and the GNU host changes only the `host:` line.

```text
rustc 1.99.0 (b940084d7 2026-09-28)
binary: rustc
commit-hash: b940084d7eb6a299eb4bfeb8e34901bc051e7ac4
commit-date: 2026-09-28
host: x86_64-pc-windows-gnu
release: 1.99.0
LLVM version: 23.1.1

cargo 1.99.0 (5f94df478 2026-08-27)
rustdoc 1.99.0 (b940084d7 2026-09-28)
rustfmt 1.10.0-stable (b940084d7e 2026-09-28)
```

### Toolchain smoke program

`tests/rust/toolchain_smoke.rs` uses only the standard library:

```rust
use std::panic;
use std::thread;

fn main() {
    let joined = thread::spawn(|| 6 * 7).join().expect("the smoke thread panicked");
    let caught = panic::catch_unwind(|| panic!("fairpane toolchain smoke panic"));
    assert!(caught.is_err());
    println!("fairpane rust toolchain smoke: thread {joined}, unwind caught");
}
```

### Documentation and declarations

- In `docs/TOOLCHAIN.md`, replace line 44 with these two lines.
  - "`rust-toolchain.toml` names that exact version, so a rustup user's Cargo commands select it."
  - "The repository's commands run the locked toolchain by path, never a Rust toolchain from `PATH`."
- Insert a section `## Rust installation` before `## Upgrade procedure` with these lines in order.
  - "`node tools/fairpane.mjs install-rust` installs the locked toolchain under `.tools/rust/<version>/<platform>`."
  - "It downloads each locked component archive from `static.rust-lang.org` and checks its size and SHA-256 before extraction."
  - "It reads each archive with a first-party gzip and tar reader, which accepts only regular files, directories, and GNU long names inside the archive root."
  - "It installs exactly the files that each component's `manifest.in` lists."
  - "It checks the version, commit, and host of the staged `rustc` before it moves the toolchain into place."
  - "It never runs rustup, changes `PATH`, or writes outside `.tools`."
  - "On Windows, the locked host is `x86_64-pc-windows-gnu`, as ADR 0010 records."
  - "The lock records the SHA-256 of the official channel manifest, `https://static.rust-lang.org/dist/channel-rust-<version>.toml`."
  - "Each component digest in the lock equals that component's `hash` value in the manifest."
  - "The Rust build infrastructure signs the manifest with the Rust signing key, whose primary fingerprint is `108F 6620 5EAE B0AA A8DD 5E1C 85AB 96E6 FA1B E5FE`."
  - "A lock change records a GnuPG verification of that signature and a `rust-lock-verify` run in its evidence."
  - "The installer checks the locked digests, not the signature, so it trusts the reviewed lock as `install-zig` trusts the Zig lock."
- Add these two rows to the command table in `tools/README.md`.
  - "| `install-rust` | Downloads and checks the exact locked Rust toolchain components in a local directory. |"
  - "| `rust-lock-verify <manifest>` | Exits with status 1 when a channel manifest file's digest or component entries differ from `toolchains/rust.lock.json`. |"
- After `tools/README.md:151`, add "`install-rust` also accepts an existing toolchain directory after only a version check."
- Add these two lines to the `help` text of `tools/fairpane.mjs`, directly after the `install-zig` line.
  - `  install-rust                Install the exact locked Rust toolchain locally.`
  - `  rust-lock-verify <manifest> Compare the Rust lock with a channel manifest file.`
- Edit `engineering/dependencies.json`.
  - Line 105 becomes "Rust from toolchains/rust.lock.json, installed with node tools/fairpane.mjs install-rust".
  - `development` gains, after `package_dependencies`, a `verification_tools` array with one object.
    Its `name` is "GnuPG".
    Its `host` is "A GnuPG executable supplied by the host, whose exact version each verification records."
    Its `uses` is ["Verifying the OpenPGP signature of an official Rust channel manifest against the Rust signing key when a reviewed change creates or updates toolchains/rust.lock.json."].
    Its `boundary` is "A review-time tool only. No build, gate, test, installation, or runtime path runs it."
- Add `engineering/decisions/0010-rust-toolchain-host.md`.
  It has the sections Status, Owner, Date, Related tasks, Decision, Evidence, Consequences, and Reversal condition.
  Its Decision section contains the line "On Windows, Fairpane's Rust toolchain uses the `x86_64-pc-windows-gnu` host."
  Its Consequences section states three facts.
  - An MSVC host and an MSVC-ABI engine library need their own qualification.
  - `FP-0032` qualifies GPUI on the locked host.
  - A host change is a reviewed lock change.

### Stop rules

- If a downloaded archive's size or SHA-256 differs from the lock above, stop and report the observed values; do not edit the lock.
- If GnuPG does not report the required `GOODSIG` and `VALIDSIG` lines, or reports `BADSIG`, `ERRSIG`, `EXPKEYSIG`, or `REVKEYSIG`, stop.
- If the keybase key's primary fingerprint differs from the static key's, stop.
- If an archive's root, installer version, or entry types differ from this contract, stop and report the observed values.
- If the installed `rustc -vV` output differs from the frozen `release`, `commit-hash`, or `host` line, stop.
- If the Windows smoke program does not link with `-C link-self-contained=yes`, stop and record the linker output; do not install MinGW, Visual Studio, or any other linker.
- If the global rustup or Cargo state differs before and after installation, stop.
- If `$HOME/fairpane-linux/node/bin/node --version` in WSL does not print `v26.7.0`, record the probe, stop the Linux steps, and report to the integrator; do not install Node.

## Exact test cases

Controller cases go in `rustCases` in a new `tools/rust.test.mjs`.
`tools/selftest.mjs` registers `rustCases` and `removeRustFixtures` as it registers the ABI cases.
Every case name starts with `FP-0079 case N:`.
The cases need no network access and no installed Rust toolchain.

1. "FP-0079 case 1: the committed Rust lock pins the frozen 1.99.0 artifacts".
   `validateRustLock` accepts the committed lock.
   The lock deep-equals the frozen object, except that `checked_date` is an ISO date on or after `2026-10-09`.
   This case fails before the change.
2. "FP-0079 case 2: the Rust lock validator rejects every malformed field".
   Each mutation of a clone of the committed lock throws a message that matches its pattern.
   - `schema_version` 2, and then `channel` `beta`: `/stable release/`.
   - `version` `1.99`: `/exact stable version/`.
   - `release_date` `2026-10-1`: `/ISO dates/`.
   - A 39-digit `rustc_commit_hash`: `/40-hex rustc commit/`.
   - `manifest.url` ending in `channel-rust-stable.toml`, and then a `signature_url` without `.asc`: `/official channel manifest/`.
   - An uppercase `manifest.sha256`: `/SHA-256 manifest digest/`.
   - A fingerprint whose last digit changes: `/Rust signing key/`.
   - A top-level key `mirror`: `/Unexpected Rust lock key: mirror/`.
   - A platform `x86_64-freebsd`: `/Unsupported Rust lock platform: x86_64-freebsd/`.
   - Windows host `x86_64-pc-windows-msvc`: `/Unexpected Rust host for x86_64-windows/`.
   - Each of these: removing `rust-mingw` from Windows, duplicating `cargo` on Linux, and adding `rust-mingw` to Linux: `/The Rust components for x86_64-(windows|linux) must be exactly/`.
   - An `http:` rustc URL, and then a `.tar.xz` rustc URL: `/Unexpected component URL for rustc on x86_64-windows/`.
   - A wrong cargo `archive_root`: `/Unexpected archive root for cargo/`.
   - A 63-digit rust-std `sha256`: `/Invalid archive SHA-256 for rust-std/`.
   - A rustfmt-preview `size` of 0, and then of 1.5: `/Invalid archive size for rustfmt-preview/`.
3. "FP-0079 case 3: rust-toolchain.toml names the locked version".
   The committed file equals `rustToolchainText(lock)` byte for byte.
   `rustToolchainProblems` returns `[]` for it.
   For the same text with `channel = "1.98.1"`, it returns exactly `['rust-toolchain.toml names 1.98.1, but the lock pins 1.99.0.']`.
   For the text without the `profile` line, it returns the single "differs from the text that the lock implies" message.
   `checkRepository(root).result` is `pass`.
   This case fails before the change.
4. "FP-0079 case 4: rust-lock-verify compares the lock with the manifest's signed entries".
   The test builds a synthetic manifest.
   It contains `manifest-version = "2"`, `date = "2026-10-01"`, a `[pkg.rustc]` table with `version = "1.99.0 (b940084d7 2026-09-28)"` and the locked commit, and one table for each locked component.
   Each component table has `available = true` and the locked `url` and `hash`, plus `xz_url` and `xz_hash` values.
   The manifest also has an unrelated `[pkg.miri.target.x86_64-pc-windows-gnu]` table.
   Against a clone of the lock whose `manifest.sha256` is the fixture's digest, `rustLockProblems` returns `[]`.
   Each variant below recomputes that digest and returns exactly its one message.
   - The date `2026-09-30`.
   - The rustc version `1.98.1 (aaaaaaaaa 2026-08-01)`.
   - Another commit.
   - The Windows rustc hash changed: `The manifest hash of rustc for x86_64-pc-windows-gnu differs from the lock.`
   - The Linux cargo URL changed.
   - `available = false` for rust-mingw.
   - A missing Linux rustfmt-preview table: `The manifest has no available rustfmt-preview for x86_64-unknown-linux-gnu.`
   With the committed lock unchanged, the first fixture returns only the manifest SHA-256 message.
   `node tools/fairpane.mjs rust-lock-verify` without an argument exits with status 1 and prints the usage line.
5. "FP-0079 case 5: the archive reader accepts only regular files, directories, and GNU long names inside the root".
   A writer in the test builds GNU tar headers with valid checksums, and `zlib.gzipSync` compresses them.
   The accepted archive has root `fx-1.0.0-x86_64-pc-windows-gnu`.
   It holds a directory, a file whose 140-byte path needs an `L` entry, a mode `0755` file, and an empty file.
   `extractTarGz` returns `{ files: 3, directories: 2 }`, and every byte matches.
   Outside Windows, the mode `0755` file is executable and the others have mode `0644`.
   Each rejected fixture throws its frozen message:
   - a symlink (type `2`), a hard link (type `1`), a pax header (type `x`), and a character device (type `3`);
   - the paths `/etc/x`, `C:/x`, `fx-1.0.0-x86_64-pc-windows-gnu\x`, `fx-1.0.0-x86_64-pc-windows-gnu/../x`, and `fx-1.0.0-x86_64-pc-windows-gnu/./x`;
   - a path under `other/`;
   - the paths `…/A` and `…/a` in one archive;
   - one checksum byte changed;
   - the uncompressed tar cut by 600 bytes before compression;
   - the magic `ustar\0` with version `99`.
   Control M3 must fail this case.
6. "FP-0079 case 6: a component installs exactly what its manifest.in lists".
   The fixture root has `rust-installer-version` `3`, `components` `fx-tool`, and `fx-tool/manifest.in` with `file:bin/fx-tool.exe` and `dir:share/doc/fx`.
   It also has `install.sh`, `README.md`, and `version`.
   `installComponents` returns `['fx-tool']`, and the toolchain holds exactly `bin/fx-tool.exe` and the two files under `share/doc/fx`.
   Each of these fails with its frozen message:
   - a listed file that is absent;
   - an extra `fx-tool/bin/stray.exe`;
   - a line `file:../x`;
   - a component name `a/b`;
   - an installer version `4`;
   - a second archive whose component also installs `bin/fx-tool.exe`, with the same `installed` set.
   Control M4 must fail this case.
7. "FP-0079 case 7: install-rust verifies, stages, checks, and then installs, and leaves nothing behind on failure".
   For each platform `x86_64-windows` and `x86_64-linux`, the test creates a fixture root with a copy of the committed lock.
   It replaces each component's `sha256` and `size` with those of a fixture archive whose root and component layout match the real archive.
   It injects a `fetch` that serves the fixture bytes by locked URL and counts calls.
   It injects a `run` that returns the frozen version outputs with the platform's host.
   The first call returns `downloaded: true`.
   The fixture root then holds only `.tools/downloads/<each basename>` and `.tools/rust/1.99.0/<platform>/**`.
   No `.partial` file or `.extract-` directory remains, and the receipt deep-equals the frozen shape.
   A second call returns `downloaded: false` and makes no fetch.
   Each fresh-root variant throws its message and leaves no `dest`, no `.partial` file, and no stage:
   - one byte more than `size`: `/exceeded the locked archive size/`;
   - wrong bytes of the right size: `/rustc archive SHA-256 does not match the lock/`, with no archive in `.tools/downloads`;
   - a corrupt archive already in `.tools/downloads`, with no fetch;
   - HTTP 404: `/rustc download failed with HTTP 404/`;
   - a `run` that reports host `x86_64-pc-windows-msvc`: `/Rust toolchain mismatch/`.
8. "FP-0079 case 8: the version checks accept only the locked release, commit, and host".
   `toolchainVersionProblems` returns `[]` for the frozen outputs of each platform.
   Each variant returns its one message:
   - `release: 1.98.1`;
   - a different `commit-hash`;
   - `host: x86_64-pc-windows-msvc`;
   - `cargo 1.98.0 (5f94df478 2026-08-27)`;
   - `rustdoc 1.99.0 (aaaaaaaaa 2026-09-28)`;
   - `rustfmt 1.10.0-stable (aaaaaaaaaa 2026-09-28)`.
   Removing the `LLVM version:` line changes nothing.
9. "FP-0079 case 9: the controller documents and exposes the Rust commands".
   The `help` output contains both frozen lines.
   `tools/README.md` contains both frozen rows and the sentence about an existing toolchain directory.
   The JSON output of `doctor` has a boolean `rust.available` and a `path_rustc.note` equal to `Gates never use a Rust toolchain from PATH.`
10. "FP-0079 case 10: the toolchain documents and declarations record the pin".
    `engineering/dependencies.json` has the frozen `required_hosts` entry and the GnuPG `verification_tools` object.
    `docs/TOOLCHAIN.md` contains each frozen sentence as its own line.
    ADR 0010 contains its frozen Decision line.

### Mutation controls

Each control edits the final tree, runs the named command, and records its diff, output, and exit status.
Restore the tree after each control.
Record a crash separately from a failed assertion.

- Control M1: change the last digit of the Windows rustc `sha256` in `toolchains/rust.lock.json`.
  `rust-lock-verify` on the committed manifest must exit with status 1 and print `The manifest hash of rustc for x86_64-pc-windows-gnu differs from the lock.`
- Control M2: change the channel in `rust-toolchain.toml` to `1.98.1`.
  `node tools/fairpane.mjs check` must exit with status 1 and print `rust-toolchain.toml names 1.98.1, but the lock pins 1.99.0.`
- Control M3: skip the header checksum check in `tools/rust.mjs`.
  Case 5 must fail.
- Control M4: skip the check for unlisted files in `installComponents`.
  Case 6 must fail.

### Criterion mapping

| Criterion | Cases and evidence |
| --- | --- |
| Pin stable Rust 1.99.0 with verified official artifact digests, separate from the wrapper | 1, 2, 4, M1, `gpg-verify.log`, and `rust-lock-verify.log` |
| Name the official source of every digest and record a GnuPG verification | 4, 10, `provenance-fetch.log`, and `gpg-verify.log` |
| Install under `.tools` with size and digest checks and no global change | 5, 6, 7, M3, M4, `install-rust.log`, and `global-state.log` |
| Name the locked version in `rust-toolchain.toml` and check it | 3 and M2 |
| Execute the installed toolchain on Windows and Linux | 8, `toolchain-versions.log`, `toolchain-smoke.log`, and the `linux-*` logs |
| Protect the lock and the selection file | P1 and the integration gates on its head |

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0079/raw/`.
Never delete or overwrite a log.
Name a log of a failed attempt with the suffix `-attempt-N`, and list each one with its cause in the README.
Use `C:/Windows/System32/curl.exe` for downloads and `C:/Program Files/Git/usr/bin/gpg.exe` for GnuPG.
Run every Rust executable by its path under `.tools/rust/1.99.0/<platform>/bin`, with `--env CARGO_HOME=C:\src\fairpane\.tools\cargo-home`.
No step runs Zig or rustup.

1. Write cases 1 to 10 on the base before any implementation change.
2. Record `controller-tests-before.log` with `node tools/fairpane.mjs test`.
   It must fail, because `tools/rust.mjs` and the Rust lock do not exist.
3. Record `provenance-fetch.log` with one `curl.exe --proto =https --tlsv1.2 -sSf -o <file> <url>` call for each of these files.
   Each file goes into `engineering/evidence/FP-0079/raw/provenance/`.
   - `channel-rust-1.99.0.toml`
   - `channel-rust-1.99.0.toml.asc`
   - `channel-rust-1.99.0.toml.sha256`
   - `rust-key.gpg.ascii`, from the static URL.
   - `rust-key-keybase.asc`, from the keybase URL; this call alone may add `-L`.
4. Record `gpg-verify.log` with these commands.
   - `gpg --version`.
   - A `node -e` call that creates `out/fp0079-gnupg` and `out/fp0079-gnupg-keybase` with mode `0o700`.
   - `gpg --homedir out/fp0079-gnupg --batch --import` of the static key.
   - `gpg --homedir out/fp0079-gnupg --batch --with-colons --fingerprint`, whose first `fpr` line names `108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE`.
   - The same import and listing for the keybase key in `out/fp0079-gnupg-keybase`.
   - `gpg --homedir out/fp0079-gnupg --batch --status-fd 1 --verify` of the signature and the manifest.
   The verification output must contain `[GNUPG:] GOODSIG 85AB96E6FA1BE5FE`.
   It must also contain a `[GNUPG:] VALIDSIG` line whose first and last fingerprint fields are `108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE`.
   If Git's gpg cannot use the home directory, record that attempt and repeat the step with `wsl.exe -e gpg` and `/mnt/c/...` paths.
5. Record `rust-lock-verify.log` with `node tools/fairpane.mjs rust-lock-verify engineering/evidence/FP-0079/raw/provenance/channel-rust-1.99.0.toml`.
   The exit status must be 0.
6. Record `global-state.log` with a `node -e` call that lists `%USERPROFILE%\.rustup\toolchains` and `%USERPROFILE%\.cargo\bin` and prints the SHA-256 of `%USERPROFILE%\.rustup\settings.toml`.
7. Delete `.tools/rust/1.99.0/x86_64-windows` and the five locked Windows archives in `.tools/downloads` if they exist.
8. Record `install-rust.log` with `node tools/fairpane.mjs install-rust`, which must report `downloaded: true`.
9. Append a second `install-rust` run to `install-rust.log`, which must report `downloaded: false`.
10. Append the same `node -e` call to `global-state.log`.
    Its output must equal the first output.
11. Record `toolchain-versions.log` with `rustc -vV`, `cargo -V`, `rustdoc -V`, and `rustfmt -V`.
    Append a `node -e` call that prints `.tools/rust/1.99.0/x86_64-windows/fairpane-install.json`.
12. Record `toolchain-smoke.log` with `rustc --edition 2024 -C link-self-contained=yes -o out/fp0079/toolchain-smoke.exe tests/rust/toolchain_smoke.rs`.
    Then run `out/fp0079/toolchain-smoke.exe`.
    The run must exit with status 0 and print `fairpane rust toolchain smoke: thread 42, unwind caught`, and its standard error must contain `fairpane toolchain smoke panic`.
13. Record `linux-probe.log` with `wsl.exe -d Ubuntu -e bash -c '"$HOME/fairpane-linux/node/bin/node" --version'`, which must print `v26.7.0`.
    Then copy the worktree's working files, without `.git` and `.tools`, into a WSL-native directory `$HOME/fairpane-linux/work/FP-0079`, because the `/mnt/c` mount does not keep Linux file modes.
    Record that copy, and a listing of the blob ID of every file under `tools`, `toolchains`, `tests/rust`, and `rust-toolchain.toml` in the copy, in `linux-copy.log`.
    Record the Linux steps in that copy through `wsl.exe`, running Node by its path.
    - `linux-install-rust.log`, with the same two runs as steps 8 and 9.
    - `linux-toolchain-versions.log`.
    - `linux-toolchain-smoke.log`, which builds `out/fp0079/toolchain-smoke-linux` without `-C link-self-contained`, and then runs it.
    If the probe fails, apply the stop rule.
14. Record `mutation.log` with controls M1 to M4, and store each diff as `mutation-<control>.diff`.
15. Record `controller-tests-after.log` with `node --version` and then `node tools/fairpane.mjs test`.
16. Record `check-after.log` with `node tools/fairpane.mjs check`.
17. Write `engineering/evidence/FP-0079/README.md`.
    It states the worktree `HEAD`, the criterion mapping, each control's result, each stop-rule outcome, the targets that ran, and every resolved ambiguity.

The integrator lands P1 after the reviews accept the implementation commit.
The integrator records `git rev-parse HEAD` and `git status --porcelain=v1 --ignored --untracked-files=all` in `raw/integration-binding.log` before the gates.
The integrator runs `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0079/gates` on the P1 head.
The integrator appends `HEAD` and the same status to `raw/integration-binding.log` after the last run.

## Authority

Writable paths: `toolchains/rust.lock.json`, `rust-toolchain.toml`, `tools`, `tests/rust`, `engineering/dependencies.json`, `engineering/decisions/0010-rust-toolchain-host.md`, `docs/TOOLCHAIN.md`, and `engineering/evidence/FP-0079/`.
Local install directories: `.tools/downloads`, `.tools/rust`, and `.tools/cargo-home`.
Scratch directories: `out/fp0079`, `out/fp0079-gnupg`, and `out/fp0079-gnupg-keybase`.
Protected paths stay unchanged in the implementation commit: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
The integrator alone applies P1 and updates `engineering/state.json`, `engineering/HANDOFF.md`, and `engineering/plan.json`.
Required reviewers: `fairpane-review` and `fairpane-security`.
Required gates: `repo-check` and `controller-test`.

## Non-goals

- No `fairpane-sys` or `fairpane` crate, no `Cargo.toml`, and no `Cargo.lock` is created.
- No gate, gate kind, or CI workflow changes, and `install-rust` does not enter the Gates workflow.
- No MSVC host, no cross-target standard library, no `clippy`, and no `rust-src` is pinned.
- No first-party OpenPGP verifier is written, and the installer does not check signatures.
- No rustup command runs, and the existing global rustup toolchains stay untouched.
- The worker installs no Node, GnuPG, MinGW, or Visual Studio; the integrator's user-local WSL Node is the only Node on Linux.
- `install-zig` keeps its behavior and messages, and `scripts/Get-Zig.ps1` stays unchanged.
- No support claim is made for the Rust wrapper.

## Revision 1

Base: the commit that freezes this revision.
Source findings: `reviews/review-1-reject.json` and `reviews/security-review-1-accept.json`.
Every section above stays in force except where this revision replaces it.
Writable paths stay as above.

### Integrator decisions

- Review 1 rejected `04342e2` for one major finding: `doctor` started `rustc` from `PATH` with the repository as its working directory, and case 9 runs `doctor` in every controller test.
  On a host with rustup, that `rustc` is the rustup proxy, which reads `rust-toolchain.toml` and may install 1.99.0 and `rustfmt` into the global rustup home.
  No `PATH` probe is safe against a proxy that reads the toolchain file, and the probe only reports a toolchain that no gate uses, so `doctor` drops it.
- The lock values stay unchanged; both reviews approved them.
- The component order rule at line 138 is corrected to the frozen lock's order: `rustc`, `cargo`, `rust-std`, then `rust-mingw` for a `-windows-gnu` host, then `rustfmt-preview`.
  The implementation already follows the lock.
- The security review's archive findings are folded in, because this revision changes the same reader.

### Behavior

- `doctor` has no `path_rustc` field, and it starts no `rustc`, `cargo`, `rustdoc`, `rustfmt`, or `rustup` from `PATH` or the working directory.
- The archive path rules also reject a path with a code unit from U+0000 to U+001F, a `:` in any component, a component that ends in `.` or a space, and a component whose name before its first `.` is a reserved Windows device name, compared without regard to case.
  The reserved names are those that Microsoft's "Naming Files, Paths, and Namespaces" lists; the worker records the list and its URL.
  The message stays `The archive path is not accepted: <name>`.
- A GNU `L` entry whose payload is longer than 4096 bytes fails with `The archive long name is longer than 4096 bytes.` before the reader buffers it.
- `checkRust` starts each version check with its working directory set to the toolchain's `bin` directory.

### Exact test cases

1. Case 9: the JSON output of `doctor` has a boolean `rust.available` and no `path_rustc` key.
   With a directory first on `PATH` that holds a program named `rustc` (`rustc.exe` on Windows) that writes a marker file when it starts, `doctor` run from the repository root leaves no marker.
   The same program, started directly by the test, writes the marker, so the case shows that the program works.
2. Case 5 gains a rejection fixture with its exact message for each of these: a GNU long name with a `..` component, a leading `/`, a drive letter, an embedded NUL, and a path outside the root; a POSIX prefix of `<root>/..`; a prefix that makes an empty component; a file and a directory whose paths differ only in case; an `L` entry at the end of the archive; an `L` payload of 4097 bytes; a component with `:`; a component with U+0001; the components `CON`, `nul.txt`, and `COM1`; a component that ends in `.`; and a component that ends in a space.
3. Mutation controls: control M5 makes `doctor` start `rustc` from `PATH` again and must fail case 9; control M6 removes the `:` rule and must fail case 5.

Cases 1 and 2 must fail on `04342e2` before the change, except the parts of case 2 that the old rules already reject; the README names those parts.

### Revision 1 evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0079/raw/`, with the suffix `-r1`, and keep each failed attempt as its own log.

1. `tests-before-r1.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `global-state-r1.log` before and after `node tools/fairpane.mjs test`: the listing of `%USERPROFILE%\.rustup\toolchains`, each toolchain's `lib\rustlib\components` file, the SHA-256 of `%USERPROFILE%\.rustup\settings.toml`, and the listing of `%USERPROFILE%\.cargo\bin`; both outputs must be equal.
3. `claims-r1.log`: the SHA-256 of both key files, a probe of whether the worktree's `.tools\cargo-home` exists, and the Windows version, for the README claims that review 1 found without a log; or the README drops those claims.
4. `mutation-r1.log` and its diffs for M5 and M6, `controller-tests-after-r1.log`, and `check-after-r1.log`.
5. The README gains a `## Revision 1` section.
   It states that the first implementation's worktree was based on `9cc81ea` and that the integrator committed it as `04342e2` on top of `789ad50`.

After both reviews accept this revision, the integrator records `node tools/fairpane.mjs rust-lock-verify engineering/evidence/FP-0079/raw/provenance/channel-rust-1.99.0.toml` on the committed tree, lands policy change P1, and runs the gates on the P1 head with the binding records that the Evidence section describes.