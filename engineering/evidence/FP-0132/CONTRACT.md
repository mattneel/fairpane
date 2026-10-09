# FP-0132 task contract: lock the i686-unknown-linux-gnu Rust standard library

## Identity

Task ID: `FP-0132`, created in plan commit `d945fa7`.
Title: "Lock the i686-unknown-linux-gnu Rust standard library".
Workstream: `wrappers`.
Base: the commit that freezes this contract. The drafter checked every line citation against the base, `c6f8d70` or later.
Prerequisite: `FP-0079`, accepted (`engineering/state.json:928-934`). The plan entry lists only `FP-0079` in `depends_on` (`engineering/plan.json:4313`). `FP-0021` is not a prerequisite of this slice. `FP-0133` depends on it.
Parent: this is the first slice of the `FP-0080` split. The other slices are `FP-0133`, which generates `fairpane-sys`, and `FP-0134`, which links it and adds the Rust gates. `FP-0080` is the closing task (`engineering/plan.json:3370`), and its criterion 10 is at line 3390.
Assigned role: `fairpane-bindings`.
Authority: `routine-local-engineering`, plus one protected lock change, P1, that the integrator applies after independent approval.
Required reviewers: `fairpane-review` and `fairpane-security`.
Required gates: `repo-check` and `controller-test`.
The `fairpane-bindings` worker `FP0080Contract` drafted this contract. The root integrator freezes it with the decisions below.

### Integrator decisions

- `FP-0080` splits into `FP-0132`, then `FP-0133`, then `FP-0134`. `FP-0080` keeps its 13 criteria word for word as the closing task.
- `FP-0132` adds no wrapper code, no Cargo file, and no gate. It serves the part of `FP-0080` criterion 10 that reads "through a reviewed lock change that adds its standard library".
- The 32-bit target is `i686-unknown-linux-gnu`, as the `FP-0079` contract decided (`engineering/evidence/FP-0079/CONTRACT.md:51-52`). It is 32-bit x86 Linux, the architecture of the `x86-linux-musl` C layout check of `FP-0021` (`engineering/evidence/FP-0021/README.md:77`).
- The lock gains an optional top-level member, `targets`. It maps a target triple to one `rust-std` component with the five keys of a host component. One archive serves every host, so `install-rust` installs every locked target into every host toolchain.
- `i686-unknown-linux-gnu` is the only accepted target. A new target needs a reviewed tools change and a reviewed lock change.
- `rust-toolchain.toml` gets no `targets` line, and no command runs rustup. `rustToolchainText` ignores `targets`.
- The toolchain check compares the installed receipt, `fairpane-install.json`, with the lock before it runs any version check.
- `install-rust` replaces a toolchain whose receipt differs from the lock only after the new toolchain passes its checks. It keeps the old toolchain until then.
- P1 is a protected change. The worker writes it as `raw/p1-rust-lock.diff` and applies it in the worktree only for evidence.
- The integrator records the independent approval of P1 as `engineering/evidence/FP-0132/reviews/policy-p1-approve.json` in its own commit. The integrator then commits exactly that diff as P1. FP-0079's P2 followed the same order: `d63f5b1` recorded the approval, and `2e07f89` changed the policy.
- The code lands as three commits: A, then P1, then B. Each commit passes `check` and the controller tests. The evidence directory lands after B.
- The plan entry allows `docs/TOOLCHAIN.md` (`engineering/plan.json:4315`).
- No GnuPG step needs the network. P1 keeps the manifest digest `ce6dddc886364f8d786514771212cebe9b731ba82d6b859951c6b0ccc516b6a2`, so the worker repeats the signature check offline on the committed `FP-0079` provenance files.
- The base runs ordinary controller cases on four worker threads (`tools/README.md:388`). A case that changes the working directory, the environment, or a module-level function declares `{ processWide }` (`tools/README.md:395-400`).
- The cases of `tools/rust.test.mjs` pass that declaration through; since FP-0107 revision 2, the final `map` of `rustCases` already does, as `tools/attest.test.mjs:295` does.
- The new and amended controller cases add at most 1000 ms of case time on the development host, as "Test cost" defines it.
- Agent Check0132 checked the draft twice: its first check (fix-first, 4 blockers) led to this revision, and its re-check (fix-first, 1 major) moved the base runs after a toolchain install, so both measurements run `doctor`'s version checks; the integrator applied its fixes at the freeze.

## Sources

- Plan entry: `engineering/plan.json:4310-4330` at `9982925`, with six acceptance criteria at lines 4321-4326. `engineering/state.json:999` records the task.
- `docs/ABI_AND_WRAPPERS.md:87-112` and `engineering/decisions/0004-first-party-wrapper-language.md:31-44,86-89,168-174`.
- `engineering/decisions/0010-rust-toolchain-host.md`, which the plan entry lists to read.
- `engineering/evidence/FP-0079/CONTRACT.md`:
  - decisions at lines 19-56;
  - the lock at 76-122;
  - the installer at 232-257;
  - the toolchain check at 259-289;
  - evidence at 496-555.
- `engineering/evidence/FP-0079/README.md` and `engineering/evidence/FP-0079/raw/gpg-verify.log:68-70`, the accepted `GOODSIG` and `VALIDSIG` lines.
- `toolchains/rust.lock.json`: 36 lines. Line 35 is `  }` and closes `platforms`, and line 36 is `}`.
- The committed, GnuPG-verified Rust 1.99.0 channel manifest, `engineering/evidence/FP-0079/raw/provenance/channel-rust-1.99.0.toml`, has 943,486 bytes. Lines 27120-27125 hold the following:
  - `[pkg.rust-std.target.i686-unknown-linux-gnu]`;
  - `available = true`;
  - `url = "https://static.rust-lang.org/dist/2026-10-01/rust-std-1.99.0-i686-unknown-linux-gnu.tar.gz"`;
  - `hash = "2b7db847af9888ddb249d3e1c8aeaeeb82ae529bf62426b82330a4cddac8bb38"`.
- `channel-rust-1.99.0.toml.asc` and `rust-key.gpg.ascii` in the same directory.
- The archive size:
  - The drafter observed `Content-Length: 46083412` with `curl.exe --proto =https --tlsv1.2 -sSfI` at 2026-10-09T18:08:58Z, and no log records that observation.
  - Evidence step 6 records it in `i686-head.log`.
  - The manifest does not sign sizes, so the lock records the size as a download bound only (`engineering/evidence/FP-0079/CONTRACT.md:43-44`).
- `tools/lib.mjs`:
  - `RUST_KEYS` at 135-140;
  - `rejectUnknownKeys` at 147-149;
  - `validateRustLock` at 151-187;
  - `rustToolchainText` at 189-195;
  - `verifyArchive` and `fetchLockedArchive` at 224-250.
- `tools/rust.mjs`:
  - the `node:fs` default import at line 5;
  - `rustLockProblems` at 68-89;
  - `installComponents` at 266-308;
  - `loadLock` at 340-344;
  - `verifyToolchain` at 354-367;
  - `checkRust` at 369-373;
  - `installRust` at 380-409, which stages at `path.join(stage, 'toolchain')` on line 396.
- `tools/rust.test.mjs`:
  - `FROZEN_LOCK` at 48-83;
  - `componentArchive` at 139-161;
  - `installFixture` at 163-187;
  - `manifestText` at 195-208;
  - `rustCases` at 297-586;
  - the `map` at 586.
- The case registration and the runner:
  - `tools/selftest.mjs:37` defines `test`, and `:238` registers the Rust cases.
  - `tools/selftest.mjs:1466-1482` stubs `fs.rmSync` and declares `processWide`, which is the precedent.
  - `tools/test-runner.mjs:12` sets the concurrency to 4.
  - `tools/README.md:380-400` describes the runner.
- `tools/README.md:170-171`, `docs/TOOLCHAIN.md:56-74`, `tools/fairpane.mjs:96-97` (the `doctor` field `rust`), and `AGENTS.md:63`, which says that local receipts are integrity records.

### Observed facts that shaped the decisions

- `RUST_KEYS.lock` (`tools/lib.mjs:136`) has no `targets`, and `validateRustLock` rejects every unknown key first (`:152`). The base therefore throws `Unexpected Rust lock key: targets` for any lock that has a target.
- The validator requires each platform's components to be exactly `rustc`, `cargo`, `rust-std`, optionally `rust-mingw`, and `rustfmt-preview` (`tools/lib.mjs:174-177`). A cross-target `rust-std` therefore cannot join a platform list.
- `rustLockProblems` looks up each component under `pkg.<package>.target.<host>` (`tools/rust.mjs:79-87`), so it cannot check a component for a target other than the host.
- `installRust` returns after only a version check when the toolchain directory exists (`tools/rust.mjs:384`). An existing `FP-0079` toolchain would therefore never receive a new target.
- `installRust` fetches every archive before it creates the stage (`tools/rust.mjs:388-394`).
- `FP-0079` case 1 compares the committed lock with `FROZEN_LOCK` except for `checked_date` (`tools/rust.test.mjs:303`).
- Case 4's `manifestText` (`:197`) and case 7's `installFixture` (`:165`) read only `lock.platforms`.
- Case 9 requires the old line at `tools/README.md:171` (`tools/rust.test.mjs:550`).
- `tools/rust.test.mjs:586` maps each case as `([name, fn, declaration]) => ({ name, fn, ...declaration })`, so a case's `{ processWide }` declaration reaches the runner through `tools/selftest.mjs:238`.
- `doctor` reports `rust: { available: false, error, expected_path }` when `checkRust` throws (`tools/fairpane.mjs:96-97`).
- Controller cases need no network and no installed Rust toolchain (`engineering/evidence/FP-0079/CONTRACT.md:363`). Every `rustc` run in this contract is a recorded command, not a controller case.
- On the four-worker base, `engineering/evidence/FP-0107/gates/2026-10-09T19-07-25-511Z-controller-test-4c916c75.log` records these case times:
  - `FP-0079` case 1: 1 ms (line 411);
  - case 4: 108 ms (line 417);
  - case 7: 318 ms (line 423);
  - case 9: 611 ms (line 427).
- The same cases took 1, 128, 232, and 2082 ms in the one-thread log `engineering/evidence/FP-0107/gates/2026-10-09T18-01-14-088Z-controller-test-7a9ee339.log:403,409,415,419`. One case can vary by hundreds of milliseconds between runs, so the budget uses medians.

## Behavior

### Files

| File | Change |
| --- | --- |
| `tools/lib.mjs` | `RUST_KEYS.lock` gains `targets`, and `validateRustLock` checks it. |
| `tools/rust.mjs` | `rustLockProblems` checks targets. `installRust` installs targets and replaces a stale toolchain. `checkRust` compares the receipt. |
| `tools/rust.test.mjs` | Cases `FP-0132 case 1` to `FP-0132 case 6`, the amendments to `FP-0079` cases 1, 4, 7, and 9. |
| `tests/rust/pointer_width_probe.rs` | New. It holds the `no_std` pointer-width probe. |
| `docs/TOOLCHAIN.md` | Seven lines in `## Rust installation`. |
| `tools/README.md` | Line 171 changes. |
| `toolchains/rust.lock.json` | Only P1 changes it, and only the integrator applies P1. |

### Lock format

After P1, the lock has this member directly after `platforms`:

```json
  "targets": {
    "i686-unknown-linux-gnu": { "package": "rust-std", "url": "https://static.rust-lang.org/dist/2026-10-01/rust-std-1.99.0-i686-unknown-linux-gnu.tar.gz", "sha256": "2b7db847af9888ddb249d3e1c8aeaeeb82ae529bf62426b82330a4cddac8bb38", "size": 46083412, "archive_root": "rust-std-1.99.0-i686-unknown-linux-gnu" }
  }
```

P1 makes these changes and no others:

- Line 35 of the lock changes from `  }` to `  },`.
- The three lines above go in before the final `}`.
- `checked_date` becomes the UTC date of the `FP-0132` GnuPG verification. If that date is `2026-10-09`, the line stays unchanged.

No other byte of the lock changes.
The tests call this object `FROZEN_TARGETS`.

### Lock validation

`validateRustLock` keeps every existing rule and message.
In its first phase, when `lock.targets` is a non-array object, it also checks each target entry that is a non-array object. It reports an unknown key in such an entry with the existing message `Unexpected Rust lock key: <key>`.
After the platform loop, when `lock.targets` is not `undefined`, it checks the targets in lock order and throws the first applicable message:

1. `The Rust lock targets must be a nonempty object.` unless `targets` is a non-array object with at least one key.
2. `Unsupported Rust lock target: <triple>` unless the triple is `i686-unknown-linux-gnu`.
3. `The Rust lock target <triple> must name rust-std.` unless the entry is an object whose `package` is `rust-std`.
4. `Unexpected component URL for rust-std on <triple>.` unless `url` is `https://static.rust-lang.org/dist/<release_date>/rust-std-<version>-<triple>.tar.gz`.
5. `Unexpected archive root for rust-std on <triple>.` unless `archive_root` is `rust-std-<version>-<triple>`.
6. `Invalid archive SHA-256 for rust-std on <triple>.` unless `sha256` is 64 lowercase hexadecimal digits.
7. `Invalid archive size for rust-std on <triple>.` unless `size` is a positive safe integer.

A lock without `targets` stays valid.

### Manifest verification

`rustLockProblems` keeps its checks and messages.
After the platform loop, it checks each target, in lock order, against `pkg.<package>.target.<triple>`. It reports these problems:

- `The manifest has no available rust-std for <triple>.` when the table is absent or `available` is not `true`.
- `The manifest URL of rust-std for <triple> differs from the lock.`
- `The manifest hash of rust-std for <triple> differs from the lock.`

### Installation

The expected component list of a platform starts with the platform's components in lock order, each as `{ package, sha256 }`. It continues with each target in lock order, as `{ package: 'rust-std', target: <triple>, sha256 }`.
`installRust(root, { platform, fetch, run })` follows these steps.

1. Load and validate the lock.
2. If `dest` exists and its receipt matches the lock, as "Toolchain check" defines, return `{ toolchain: checkRust(root, { platform, run }), downloaded: false }`.
3. Fetch or reuse each platform component, then each target component, through `fetchLockedArchive`.
   - A target's `name` and `title` are `rust-std (<triple>)`.
   - A digest failure therefore reads, for example, `The rust-std (i686-unknown-linux-gnu) archive SHA-256 does not match the lock.`
4. Create the stage, and extract every archive into it.
   - Install the platform components, and then the target components, with `installComponents`.
   - The components share one `installed` set.
   - The staged toolchain stays at `path.join(stage, 'toolchain')`.
5. Run the version checks on the staged toolchain, as `FP-0079` does.
6. Write the receipt.
   - A target's receipt entry is `{ package: 'rust-std', target: <triple>, sha256, installer_components }`.
   - A platform entry keeps its `FP-0079` form.
7. If `dest` does not exist, rename the staged toolchain to `dest`. Return `{ toolchain, downloaded: true, components }`.
8. If `dest` exists, follow these substeps:
   1. Rename `dest` to a sibling `.replaced-<random>` directory.
   2. Rename the staged toolchain to `dest`.
   3. Remove the `.replaced-` directory.
   4. Return `{ toolchain, downloaded: true, replaced: true, components }`.

If any step before the first rename in step 8 fails, `dest` keeps its earlier contents. No `.extract-`, `.replaced-`, or `.partial` entry remains.
If the second rename in step 8 fails, `installRust` renames the `.replaced-` directory back to `dest` before it rethrows.
If the removal of the `.replaced-` directory fails, `installRust` still returns the step 8 result. It adds `replaced_cleanup_error: <message>`.
A run that is interrupted between the two renames of step 8 can leave a `.replaced-` directory and no `dest`. That directory stays in place, and a later installation does not remove it.
The comment above `installRust` changes. It states that `installRust` accepts an existing toolchain whose receipt matches the lock after a version check, and that it replaces a toolchain whose receipt differs.

### Toolchain check

`checkRust(root, { platform, run })` first requires the four executables, as it does now.
It then reads `<dest>/fairpane-install.json`.
The receipt matches the lock when all of these conditions hold:

- The receipt parses as JSON.
- Its `version`, `platform`, `host`, `rustc_commit_hash`, and `manifest_sha256` equal the lock's values.
- Its `components` entries, reduced to `package`, `target` when present, and `sha256`, equal the expected component list in order.

If the receipt does not match, `checkRust` throws `The installed Rust toolchain differs from the lock. Run node tools/fairpane.mjs install-rust.` before it runs any version check.
If it matches, `checkRust` runs the version checks, as it does now.
The staged check inside `installRust` runs only the version checks, because the receipt does not exist yet.

### Pointer-width probe

`tests/rust/pointer_width_probe.rs` holds exactly this text:

```rust
//! A metadata build of this library for a target checks two facts.
//! The locked toolchain holds that target's standard library.
//! The compiler evaluates constant assertions without code generation.
//! The library compiles only for a target whose pointers are 4 bytes wide.

#![no_std]

const _: () = assert!(core::mem::size_of::<usize>() == 4, "the probe needs 4-byte pointers");
```

The probe must pass `rustfmt --check --edition 2024`. If `rustfmt` requires a whitespace change, the worker applies only that change and records it in the README.
`FP-0134` adopts the probe in the `rust-wrapper` gate.

### Documentation

- In `docs/TOOLCHAIN.md`, insert these lines in this order after line 66, "On Windows, the locked host is `x86_64-pc-windows-gnu`, as ADR 0010 records.":
  - "The lock's `targets` member names the standard library of each cross-compilation target."
  - "`i686-unknown-linux-gnu` is the only accepted target, so the wrapper's layout assertions can compile for a 32-bit target."
  - "`install-rust` installs each locked target's standard library into every host toolchain and records it in `fairpane-install.json`."
  - "It replaces a toolchain whose `fairpane-install.json` differs from the lock, and it keeps the earlier toolchain until the new one passes its checks."
  - "The toolchain check rejects such a toolchain before it runs any version check, so `doctor` reports it as unavailable."
  - "`fairpane-install.json` is a local integrity record, not a security boundary, so anyone who can write `.tools` controls the toolchain."
  - "`rust-toolchain.toml` names no target, because no repository command runs rustup."
- `tools/README.md:171` becomes "`install-rust` also accepts an existing toolchain directory whose `fairpane-install.json` matches the lock after only a version check, and it replaces one whose receipt differs; the receipt is a local integrity record, so a pull request that adds a toolchain directory with a matching receipt controls the toolchain."

### Landing order

1. Commit A holds every change in the files table except the lock.
   - In commit A, `FP-0132 case 1` accepts a committed lock that has no `targets` member.
   - It also accepts a committed lock whose `targets` member is exactly `FROZEN_TARGETS`.
2. The integrator commits `engineering/evidence/FP-0132/reviews/policy-p1-approve.json` in its own commit.
3. Commit P1 holds exactly `raw/p1-rust-lock.diff`.
4. Commit B changes only `tools/rust.test.mjs`. In commit B, `FP-0132 case 1` requires exactly `FROZEN_TARGETS` in the committed lock. The worker records B as `raw/commit-b.diff`.
5. Commit E holds `engineering/evidence/FP-0132/` without `gates/`. The integrator commits the gate receipts and `raw/integration-binding.log` with the task record.

### Stop rules

- If the `Content-Length` in `i686-head.log` is not `46083412`, stop and report it.
- If the downloaded i686 archive is not 46083412 bytes long, stop and report its size and SHA-256. Never edit the frozen entry.
- If its SHA-256 is not `2b7db847af9888ddb249d3e1c8aeaeeb82ae529bf62426b82330a4cddac8bb38`, stop and report its size and SHA-256. Never edit the frozen entry.
- If the GnuPG verification lacks `[GNUPG:] GOODSIG 85AB96E6FA1BE5FE`, stop.
- If it lacks a `[GNUPG:] VALIDSIG` line whose first and last fingerprint fields are `108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE`, stop.
- If it reports `BADSIG`, `ERRSIG`, `EXPKEYSIG`, or `REVKEYSIG`, stop.
- If the SHA-256 of the committed manifest is not `ce6dddc886364f8d786514771212cebe9b731ba82d6b859951c6b0ccc516b6a2`, stop.
- If the i686 archive differs from these expected values, stop and report the observed values:
  - its archive root is `rust-std-1.99.0-i686-unknown-linux-gnu`;
  - its installer version is `3`;
  - its `components` file names exactly `rust-std-i686-unknown-linux-gnu`.
  - `[INFERENCE]` These values follow the naming of the `FP-0079` archives.
- If the archive reader or `installComponents` rejects an entry of the i686 archive, stop and report the observed values.
- If the before probe for i686 exits with status 0, stop. The locked `rustc` then found a standard library outside its toolchain.
- If the i686 probe fails after installation, stop and record the output. Never change the probe's assertion.
- If a host probe succeeds, stop and record the output. Never change the probe's assertion.
- If either global-state log on Windows or Linux shows two different outputs, stop.
- If the added controller case time exceeds 1000 ms on the development host, stop and report each case's median times.
- If `$HOME/fairpane-linux/node/bin/node --version` in WSL does not print `v26.7.0`, stop the Linux steps and report to the integrator. Do not install Node.

## Exact test cases

Controller cases go at the end of `rustCases` in `tools/rust.test.mjs`. Each case name starts with `FP-0132 case N:`.
The final `map` of `rustCases` already passes a third array element through, as `tools/attest.test.mjs:295` does.
The cases import only names that the base already exports. These are `validateRustLock`, `rustToolchainText`, `installRust`, `checkRust`, `rustLockProblems`, and the existing helpers. A base run therefore reports failed cases instead of a module link error.
The cases need no network and no installed Rust toolchain.
Let `L` be a clone of `FROZEN_LOCK` with `targets` set to a clone of `FROZEN_TARGETS`.
`installFixture` builds a fixture archive for every component of its fixture lock, including each target, with `componentArchive('rust-std', <triple>)`. Its fixture lock is the committed lock, with `targets` set or removed when a case asks for that.
In cases 3, 4, and 6, `N` is the number of platform components. `T` is the target's receipt entry, `{ package: 'rust-std', target: 'i686-unknown-linux-gnu', sha256: <fixture digest>, installer_components: ['rust-std-i686-unknown-linux-gnu'] }`. `C` is the platform receipt entries followed by `T`.

### Controller cases

1. `FP-0132 case 1: the Rust lock validator accepts the frozen target and rejects every malformed target`.
   - `validateRustLock(L)` returns `true`.
   - Each row below applies one change to a fresh clone of `L`, and `validateRustLock` throws exactly the message.

   | Row | Change | Message |
   | --- | --- | --- |
   | a | `targets = {}` | `The Rust lock targets must be a nonempty object.` |
   | b | `targets = []` | `The Rust lock targets must be a nonempty object.` |
   | c | `targets = null` | `The Rust lock targets must be a nonempty object.` |
   | d | add `x86_64-unknown-linux-musl` with a copy of the i686 entry | `Unsupported Rust lock target: x86_64-unknown-linux-musl` |
   | e | add `x86_64-unknown-linux-gnu` with a copy of the i686 entry | `Unsupported Rust lock target: x86_64-unknown-linux-gnu` |
   | f | i686 `package = 'rustc'` | `The Rust lock target i686-unknown-linux-gnu must name rust-std.` |
   | g | i686 entry is the string `rust-std` | `The Rust lock target i686-unknown-linux-gnu must name rust-std.` |
   | h | i686 `url` with `2026-10-02` in place of `2026-10-01` | `Unexpected component URL for rust-std on i686-unknown-linux-gnu.` |
   | i | i686 `url` ending in `.tar.xz` | `Unexpected component URL for rust-std on i686-unknown-linux-gnu.` |
   | j | i686 `archive_root = 'rust-std-1.99.0-i686-unknown-linux-musl'` | `Unexpected archive root for rust-std on i686-unknown-linux-gnu.` |
   | k | i686 `sha256` in upper case | `Invalid archive SHA-256 for rust-std on i686-unknown-linux-gnu.` |
   | l | i686 `size = 0` | `Invalid archive size for rust-std on i686-unknown-linux-gnu.` |
   | m | i686 `size = 1.5` | `Invalid archive size for rust-std on i686-unknown-linux-gnu.` |
   | n | i686 `mirror = 'https://example.invalid/'` | `Unexpected Rust lock key: mirror` |

   - `rustToolchainText(L)` equals `rustToolchainText(FROZEN_LOCK)`.
   - In commit A, `committedLock().targets` is `undefined` or deep-equal to `FROZEN_TARGETS`.
   - In commit B, `committedLock().targets` is deep-equal to `FROZEN_TARGETS`.
2. `FP-0132 case 2: rust-lock-verify checks each target against the signed manifest`.
   - Read the bytes of `engineering/evidence/FP-0079/raw/provenance/channel-rust-1.99.0.toml` once.
   - `rustLockProblems(L, <bytes>)` returns `[]`.
   - Change the last digit of the i686 `sha256` in `L` from `8` to `9`. The same call then returns exactly `['The manifest hash of rust-std for i686-unknown-linux-gnu differs from the lock.']`.
   - `manifestText` also writes a `[pkg.rust-std.target.<triple>]` table for each target of its lock.
   - Start from `L`, and update its digest as `manifestProblems` does. Each edit below then gives exactly one problem:
     - The i686 table's `hash` set to 64 `d` characters: `The manifest hash of rust-std for i686-unknown-linux-gnu differs from the lock.`
     - Its `url` with `2026-10-02`: `The manifest URL of rust-std for i686-unknown-linux-gnu differs from the lock.`
     - Its `available = false`: `The manifest has no available rust-std for i686-unknown-linux-gnu.`
     - The table removed: `The manifest has no available rust-std for i686-unknown-linux-gnu.`
3. `FP-0132 case 3: install-rust installs each locked target into every host toolchain and replaces a stale toolchain only after the new one passes`. Run these rows for each platform in `HOSTS`.
   - Fresh install, on fixture F1 with `targets`:
     - The result deep-equals `{ toolchain: <dest>/bin/rustc[.exe], downloaded: true, components: C }`.
     - The fetch count is `N + 1`.
     - The files under the fixture root are exactly these:
       - the lock;
       - the downloads;
       - every listed component file under `dest`, including `lib/rustlib/i686-unknown-linux-gnu/lib/libstd-fixture.rlib`;
       - `dest/fairpane-install.json`.
     - The receipt's `components` deep-equal `C`.
   - Second run on F1:
     - It returns `{ toolchain, downloaded: false }`.
     - The fetch count stays `N + 1`.
   - The next three rows share fixture F2, in this order.
     - F2 first installs without `targets`.
     - Its lock then gains `FROZEN_TARGETS` with the fixture digest and size.
     - Before the first row, the case saves the listing of `dest` and the receipt bytes.
   - Failed replacement by digest:
     - The fetch serves the target's URL with bytes of the same length, all `0x41`.
     - The run rejects with exactly `The rust-std (i686-unknown-linux-gnu) archive SHA-256 does not match the lock.`
     - The listing of `dest` and the receipt bytes equal the saved ones.
     - No `.extract-`, `.replaced-`, or `.partial` entry exists.
   - Failed replacement by version:
     - The fetch serves the correct bytes.
     - The injected version outputs name the host `x86_64-pc-windows-msvc`.
     - The run rejects with a message that matches `/Rust toolchain mismatch/`.
     - `dest` is unchanged, as in the previous row.
   - Replacement:
     - The run returns `{ toolchain, downloaded: true, replaced: true, components: C }`.
     - F2's total fetch count is `N + 2`: `N` for its first install, one rejected target fetch in the digest row, and one target fetch in the version row. The replacement row fetches nothing.
     - `.tools/rust/1.99.0` lists exactly `[platform]`.
     - The target file exists.
     - No `.extract-`, `.replaced-`, or `.partial` entry exists.
     - The receipt's `components` deep-equal `C`.
     - `checkRust(dir, { platform, run })` returns the `rustc` path.
4. `FP-0132 case 4: the toolchain check rejects a toolchain whose receipt differs from the lock before any version check`. For each platform in `HOSTS`, use one fixture installed with `targets`.
   - `checkRust(dir, { platform, run })` returns `<dest>/bin/rustc[.exe]`.
   - Each row below changes the fixture, and the case restores the fixture after the row.
   - In each row, `checkRust` throws exactly `The installed Rust toolchain differs from the lock. Run node tools/fairpane.mjs install-rust.`
   - In each row, the injected run records no call.

   | Row | Change |
   | --- | --- |
   | a | The receipt's target `sha256` becomes 64 `f` characters. |
   | b | The receipt is deleted. |
   | c | The fixture lock loses `targets`. |
   | d | The receipt's `manifest_sha256` becomes 64 `0` characters. |
   | e | The receipt holds the text `{`. |

5. `FP-0132 case 5: the toolchain documents describe the locked targets`.
   - `docs/TOOLCHAIN.md` contains the seven new lines in order.
   - Each line comes after the line "On Windows, the locked host is `x86_64-pc-windows-gnu`, as ADR 0010 records." and before `## Upgrade procedure`.
   - `tools/README.md` contains the new line 171 text.
   - It no longer contains "`install-rust` also accepts an existing toolchain directory after only a version check."
6. `FP-0132 case 6: install-rust restores the earlier toolchain when the new one cannot move into place`.
   - Register the case with `{ processWide: 'the fs.renameSync and fs.rmSync functions of the node:fs module' }` as the third element of its array.
   - For each platform in `HOSTS`, use one fixture F3. F3 first installs without `targets`, and its lock then gains `FROZEN_TARGETS` with the fixture digest and size.
   - Row a, a failed second rename:
     - Replace `fs.renameSync` with a function that throws `Error('injected rename failure')` when two conditions hold:
       - the source's base name is `toolchain`;
       - the last two components of the destination are `1.99.0` and the platform.
     - In every other call, the function calls the original.
     - Restore `fs.renameSync` in `finally`.
     - The run rejects with exactly `injected rename failure`.
     - The listing of `dest` and the receipt bytes equal those before the run.
     - No `.extract-`, `.replaced-`, or `.partial` entry exists.
   - Row b, a failed removal, on F3 after row a:
     - Replace `fs.rmSync` with a function that throws `Error('injected removal failure')` when its target's base name starts with `.replaced-`.
     - In every other call, the function calls the original.
     - Restore `fs.rmSync` in `finally`.
     - The run returns `{ toolchain, downloaded: true, replaced: true, components: C, replaced_cleanup_error: 'injected removal failure' }`.
     - The receipt's `components` deep-equal `C`.
     - `.tools/rust/1.99.0` lists the platform and exactly one `.replaced-` directory.
     - The receipt in the `.replaced-` directory equals the receipt before row a.

### Amended FP-0079 cases

Each amendment keeps every existing assertion of the case.

- Case 1 compares the committed lock, without `checked_date` and `targets`, with `FROZEN_LOCK` without `checked_date`.
- Case 4's `manifestText` writes the target tables that `FP-0132 case 2` describes. With the committed lock, its expectations stay unchanged.
- Case 7's `installFixture` builds target archives, and its expectations include each target of the committed lock:
  - the expected listing;
  - the components;
  - the fetch counts;
  - the receipt.
- In commit A, the committed lock has no target, so case 7's expectations stay unchanged.
- Case 9 requires the new `tools/README.md:171` text in place of the old line.

### Base failures

`controller-tests-before.log` runs the suite with only `tools/rust.test.mjs` changed.
It must exit with status 1 after it runs every case. Exactly `FP-0132` cases 1 to 6 and `FP-0079` case 9 must report `not ok`.

- Cases 1 to 4 and case 6 each build a lock with `targets`.
  - `tools/lib.mjs:136` omits `targets` from `RUST_KEYS.lock`, and `:152` throws `Unexpected Rust lock key: targets`.
  - `rustLockProblems` (`tools/rust.mjs:69`) validates the lock first.
  - `installRust` and `checkRust` also validate the lock first, through `loadLock` (`tools/rust.mjs:340-343`).
  - In case 6, the base install without `targets` succeeds. The next run then rejects with `Unexpected Rust lock key: targets`, not with `injected rename failure`, and the `finally` blocks restore both functions.
- Case 5 fails for two reasons. `docs/TOOLCHAIN.md:56-74` has none of the seven lines, and `tools/README.md:171` still holds the old line.
- `FP-0079` case 9 fails because `tools/README.md:171` still holds the old line.
- The other amended cases pass on the base, because the committed lock has no target.

### Recorded Rust checks

These checks run with the locked `rustc` by its path, outside the controller tests. In each command, `<target>` is the triple of its row, and `<out>` is the output path of its row.

```text
rustc --edition 2024 --crate-type lib --crate-name pointer_width_probe --emit metadata --target <target> -o <out> tests/rust/pointer_width_probe.rs
```

| Check | Command | Expected |
| --- | --- | --- |
| Before, Windows | The probe command for `i686-unknown-linux-gnu` with the output `out/fp0132/pointer-width-i686.rmeta`, on the toolchain from the base lock. | Status 1. The output contains `E0463`. `[INFERENCE]` rustc reports a missing `core` crate with E0463. |
| After, each host | The same command as "Before". | Status 0, and `out/fp0132/pointer-width-i686.rmeta` exists. |
| Host, Windows | The probe command for `x86_64-pc-windows-gnu` with the output `out/fp0132/pointer-width-host.rmeta`. | Status 1. The output contains `the probe needs 4-byte pointers`. |
| Host, Linux | The probe command for `x86_64-unknown-linux-gnu` with the output `out/fp0132/pointer-width-host.rmeta`. | Status 1. The output contains `the probe needs 4-byte pointers`. |
| Target library | `rustc --print target-libdir --target i686-unknown-linux-gnu`, followed by a `node -e` check. | After trimming, the output equals `path.join(<toolchain>, 'lib', 'rustlib', 'i686-unknown-linux-gnu', 'lib')` on the host. That directory holds at least one `.rlib` file. The check prints `equal: true` and the number of `.rlib` files. |
| Pointer width | `rustc --print cfg --target i686-unknown-linux-gnu` | A line `target_pointer_width="32"`. |
| Format | `rustfmt --check --edition 2024 tests/rust/pointer_width_probe.rs` | Status 0. |
| Doctor, A | `node tools/fairpane.mjs doctor` on the A tree with the base lock and the base-installed toolchain. | `rust.available` is `true`. |
| Doctor, P1 | The same command after P1 and before `install-rust`. | `rust.available` is `false`, and `rust.error` is exactly `The installed Rust toolchain differs from the lock. Run node tools/fairpane.mjs install-rust.` |
| Doctor, after | The same command after `install-rust`. | `rust.available` is `true`. |

The host rows show that a metadata build evaluates constant assertions, so `FP-0133` can rely on that behavior. `[INFERENCE]` rustc evaluates every free constant item during analysis, which `--emit metadata` runs.

### Mutation controls

Each control is a `.diff`. Apply it with `git apply`, run the command, and reverse it with `git apply -R`.
Record the SHA-256 of each changed file before, during, and after the control. Record a crash separately from a failed assertion.
All controls run after commit B, on the A+P1+B tree.
Controls M1 to M4 and M6 to M9 run `node tools/rust.test.mjs`. Control M5 runs the recorded `rustc` commands on Windows.

| Control | Mutation | Must fail, and why |
| --- | --- | --- |
| M1 | The target allowlist test becomes always true. | `FP-0132 case 1`, rows d and e. Each now reports the URL message. |
| M2 | `rustLockProblems` skips the hash comparison for targets. | `FP-0132 case 2`. The real-manifest call with the changed digit and the `hash` row return `[]`. |
| M3 | The receipt comparison in `checkRust` and in step 2 of `installRust` uses only the platform components. Installation and the receipt still include targets. | `FP-0132 case 3`, because its second run on F1 reinstalls instead of returning `downloaded: false`. `FP-0132 case 4`, because `checkRust` throws on the unchanged fixture. |
| M4 | `installRust` removes an existing `dest` right after the receipt comparison fails, before it fetches any archive. | `FP-0132 case 3`, because both failed-replacement rows find `dest` absent. |
| M5 | In the probe, `== 4` becomes `== 8`. Run the i686 and the Windows host commands. | The i686 build exits with status 1 and prints `the probe needs 4-byte pointers`. The host build exits with status 0. |
| M6 | Remove `targets` from the lock. | `FP-0132 case 1`, on its commit B assertion. `FP-0079` cases 1 and 7 pass. |
| M7 | `checkRust` runs the version checks before it compares the receipt. | `FP-0132 case 4`, because the injected run records calls in rows a to e. |
| M8 | Remove the rename back from step 8. | `FP-0132 case 6`, row a, because it finds `dest` absent. |
| M9 | Let the error from the removal of the `.replaced-` directory propagate. | `FP-0132 case 6`, row b, because the run rejects with `injected removal failure`. |

### Criterion mapping

| FP-0132 criterion | Evidence |
| --- | --- |
| 1. Lock the i686 `rust-std` under `targets` from the signed manifest, through a separate protected change with independent approval | P1 (`raw/p1-rust-lock.diff`), `reviews/policy-p1-approve.json`, `i686-head.log`, `gpg-verify.log`, `rust-lock-verify.log`, cases 1 and 2, and M1, M2, and M6 |
| 2. Install every target into every host toolchain from its digest-checked archive, and check the receipt before any version check | Case 3 (both `HOSTS` and the digest row), case 4, M3, M7, `install-rust.log`, `linux-install-rust.log`, `toolchain-targets.log`, `linux-toolchain-targets.log`, and the three doctor logs |
| 3. Replace a toolchain whose receipt differs only after the new one passes its checks | Case 3 (the replacement row and both failed-replacement rows), case 6, M4, M8, M9, and `install-rust.log` with `replaced: true` |
| 4. Keep `rust-toolchain.toml` free of targets, and run no rustup command | `FP-0079` case 3 (the exact text), case 1 (`rustToolchainText(L)`), `global-state.log`, `linux-global-state.log`, and `protected-paths.log` |
| 5. Compile a `no_std` probe crate for i686 with the locked toolchain on Windows and Linux | `probe-before.log`, `probe-after.log`, `linux-probe-after.log`, and M5 |
| 6. Amend the affected FP-0079 cases without dropping an assertion, and add at most one second | The amended `FP-0079` cases 1, 4, 7, and 9, `raw/commit-b.diff`, `controller-tests-base.log`, `controller-tests-after.log`, and the added-time table in the README |

Rows 1 and 5 serve the `FP-0080` criterion 10 part "through a reviewed lock change that adds its standard library". `FP-0133` owns the Rust assertions and their 32-bit compilation.

### Test cost

For each case, the median is the median of its `# duration_ms` values in three suite runs.
The added time is the sum of two parts:

- the median of each of `FP-0132` cases 1 to 6 in `controller-tests-after.log`;
- for each of `FP-0079` cases 1, 4, 7, and 9, its median in `controller-tests-after.log` minus its median in `controller-tests-base.log`.

The added time must be at most 1000 ms on the development host.
The README reports, for each new and amended case, its three values and its median in both logs, and then the added time.
`[INFERENCE]` The drafter estimates about 600 ms. That estimate scales from `FP-0079` case 7, which ran 318 ms for 14 installs.
`FP-0132` adds no Zig test, so the time of the `zig-test` gate does not change.

The base and after runs both have an installed toolchain whose receipt matches the lock of their tree, so FP-0079 case 9's `doctor` runs the four version checks in both.
The README also reports the median `# duration_ms total` of the three runs in `controller-tests-base.log` and in `controller-tests-after.log`, without a bound.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0132/raw/`.
Never delete or overwrite a log. Name a failed attempt with the suffix `-attempt-N`, and list it with its cause in the README.
Run every Rust executable by its path under `<worktree>/.tools/rust/1.99.0/<platform>/bin`, with `--env CARGO_HOME=<worktree>/.tools/cargo-home`.
Use `C:/Program Files/Git/usr/bin/gpg.exe` for GnuPG.
No step runs Zig or rustup.

1. Delete `.tools/rust/1.99.0/x86_64-windows` if it exists. Record `install-base.log` with `node tools/fairpane.mjs install-rust` on the unmodified base, which must report `downloaded: true`, and a `node -e` print of the receipt.
2. Record the first output of `global-state.log` with a `node -e` call. It lists these items:
   - `%USERPROFILE%/.rustup/toolchains`;
   - each toolchain's `lib/rustlib/components`;
   - the SHA-256 of `%USERPROFILE%/.rustup/settings.toml`;
   - `%USERPROFILE%/.cargo/bin`.
   The call reports an absent item as `absent`.
3. Record `controller-tests-base.log` on the unmodified base, with the toolchain from step 1 installed. It records `git rev-parse HEAD`, `node --version`, a `node -e` print of `.tools/rust/1.99.0/x86_64-windows/fairpane-install.json`, and three runs of `node tools/fairpane.mjs test`.
4. Write cases 1 to 6 and the four amendments in `tools/rust.test.mjs`, and change no other file.
   - Record `controller-tests-before.log` with `git rev-parse HEAD`, `git status`, the staging command `git add -- tools/rust.test.mjs`, the blob ID of the staged file, and `node tools/fairpane.mjs test`.
   - The base-failure rule applies.
   - Record `index-reset.log` with `git restore --staged -- tools/rust.test.mjs`.
   - Then write `tests/rust/pointer_width_probe.rs`.
5. Record `probe-before.log` with the "Before, Windows" row.
6. Record `i686-head.log` with `curl.exe --proto =https --tlsv1.2 -sSfI https://static.rust-lang.org/dist/2026-10-01/rust-std-1.99.0-i686-unknown-linux-gnu.tar.gz`.
7. Record `gpg-verify.log` with these commands:
   1. `gpg --version`.
   2. A `node -e` call that creates `out/fp0132-gnupg` with mode `0o700`.
   3. `gpg --homedir out/fp0132-gnupg --batch --import engineering/evidence/FP-0079/raw/provenance/rust-key.gpg.ascii`.
   4. `gpg --homedir out/fp0132-gnupg --batch --with-colons --fingerprint`.
   5. A `node -e` call that prints the SHA-256 of the committed manifest.
   6. `gpg --homedir out/fp0132-gnupg --batch --status-fd 1 --verify` with the `.asc` file and the manifest.
   Apply the GnuPG stop rules.
8. Implement commit A.
   - Record `rust-cases-development.log` with `node tools/rust.test.mjs`.
   - Record `controller-tests-after-a.log` with `node --version` and `node tools/fairpane.mjs test`. It must exit with status 0.
   - Record `check-after-a.log` with `node tools/fairpane.mjs check`. It must exit with status 0.
   - Record `doctor-a.log` with the "Doctor, A" row.
9. Apply P1 in the worktree.
   - Store `git diff -- toolchains/rust.lock.json` as `raw/p1-rust-lock.diff`, and record the lock's SHA-256 before and after the change.
   - Record `rust-lock-verify.log` with `node tools/fairpane.mjs rust-lock-verify engineering/evidence/FP-0079/raw/provenance/channel-rust-1.99.0.toml`. It must exit with status 0 and report no problems.
   - Record `doctor-p1.log` with the "Doctor, P1" row.
   - Record `controller-tests-after-p1.log` and `check-after-p1.log`. Both must exit with status 0.
10. Record `install-rust.log` with these commands:
    1. A `node -e` listing of `.tools/downloads` with sizes.
    2. `install-rust`, which must report `downloaded: true` and `replaced: true`.
    3. The same listing again.
    4. A second `install-rust`, which must report `downloaded: false`.
    The listings must show that the run added only the i686 archive. Then record `doctor-after.log` with the "Doctor, after" row.
11. Append the step 2 call to `global-state.log`. Its output must equal the first output.
12. Record `toolchain-targets.log` with `rustc -vV`, the target-library row, the pointer-width row, a `node -e` listing of the target library directory, and a `node -e` print of the receipt.
13. Record `probe-after.log` with the "After", "Host, Windows", and "Format" rows.
14. Apply commit B, and store it as `raw/commit-b.diff`.
    - Before the three runs, record a `node -e` print of the same receipt. Its `components` must include the i686 entry, so that `doctor` runs the version checks in both logs.
    - Record `controller-tests-after.log` with `node --version` and three runs of `node tools/fairpane.mjs test`. Each run must exit with status 0.
    - Record `check-after.log` with `node tools/fairpane.mjs check`. It must exit with status 0.
    - Record `protected-paths.log` with `git diff --stat <base>` and `git diff --exit-code <base> -- rust-toolchain.toml AGENTS.md docs/CHARTER.md engineering/qualification.json engineering/policy.json engineering/gates.json toolchains/zig.lock.json specs/corpora.json`. The second command must exit with status 0.
15. Record `linux-probe.log` with `wsl.exe -d Ubuntu -e bash -c '"$HOME/fairpane-linux/node/bin/node" --version'`.
    - Copy the A+P1+B working files, without `.git` and `.tools`, into `$HOME/fairpane-linux/work/FP-0132`.
    - Record the copy in `linux-copy.log`, with the Git blob IDs of every file under `tools`, `toolchains`, and `tests/rust`, and of `docs/TOOLCHAIN.md`, from the copy and from the worktree.
    - The two listings must be equal.
    - If `$HOME/fairpane-linux/work/FP-0079-r1/.tools/downloads` exists, copy its four Linux archives into the copy's `.tools/downloads`, reading the source only.
    - Copy the verified i686 archive from the worktree's `.tools/downloads` in the same way.
16. Record these logs in the copy:
    - `linux-global-state.log`, before the first `install-rust` and again after the second one. It lists `$HOME/.rustup/toolchains` and `$HOME/.cargo/bin`, and it prints the SHA-256 of `$HOME/.rustup/settings.toml`. Each absent item appears as `absent`. The two outputs must be equal.
    - `linux-install-rust.log`, with two runs. The first reports `downloaded: true`, and the second reports `downloaded: false`.
    - `linux-toolchain-targets.log`.
    - `linux-probe-after.log`, with the "After", "Host, Linux", and "Format" rows.
    - `linux-tests.log`, with `node tools/rust.test.mjs`, which must pass every case.
17. On the A+P1+B tree, record `mutation.log` with M1 to M9, and store `mutation-M1.diff` to `mutation-M9.diff`.
18. Write `engineering/evidence/FP-0132/README.md`. It gives these items:
    - the worktree `HEAD`;
    - the criterion mapping;
    - the observed size and SHA-256 of the i686 archive;
    - each control's result;
    - each stop rule's outcome;
    - the added-time table;
    - the targets that ran;
    - every resolved ambiguity.
    The README also states that `fairpane-install.json` is a forgeable local integrity record. Because of this change, it now decides whether an existing toolchain is reused.

The integrator then does the following.

1. Commit A. Record the independent approval of P1 as `reviews/policy-p1-approve.json` in its own commit. Commit exactly `raw/p1-rust-lock.diff` as P1, and then commit B and E.
2. Record `HEAD` and `git status --porcelain=v1 --ignored --untracked-files=all` in `raw/integration-binding.log` before and after the gates.
3. Run `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0132/gates` on the head after E.
4. Record `raw/bun-selftest.log` with Bun and `tools/selftest.mjs`.

## Authority

Writable paths: `tools`, `tests/rust`, `docs/TOOLCHAIN.md`, and `engineering/evidence/FP-0132/`.
The integrator alone applies P1 to `toolchains/rust.lock.json`.
The worker changes `toolchains/rust.lock.json` in its worktree only for two purposes:

- to apply `raw/p1-rust-lock.diff`;
- to apply and reverse `mutation-M6.diff`.

It records the lock's SHA-256 before and after each such change.
Local install directories: `.tools/downloads`, `.tools/rust`, and `.tools/cargo-home`. Scratch directories: `out/fp0132` and `out/fp0132-gnupg`.
Only `install-rust` and the `i686-head.log` request use the network.
Commits A and B leave these protected paths unchanged:

- `AGENTS.md`;
- `docs/CHARTER.md`;
- `engineering/qualification.json`;
- `engineering/policy.json`;
- `engineering/gates.json`;
- `toolchains/zig.lock.json`;
- `toolchains/rust.lock.json`;
- `specs/corpora.json`;
- `rust-toolchain.toml`.

The integrator alone updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
Required reviewers: `fairpane-review` and `fairpane-security`. Required gates: `repo-check` and `controller-test`.

## Non-goals

- No `fairpane-sys` or `fairpane` crate, no `Cargo.toml`, no `Cargo.lock`, and no `build.rs`.
- No gate, no gate kind, no change to `engineering/gates.json`, and no change to the Gates workflow.
- No change to `rust-toolchain.toml`, `rustToolchainText`, or `install-zig`.
- No target other than `i686-unknown-linux-gnu`, no MSVC host, no `clippy`, and no `rust-src`.
- No linking or execution of i686 code, and no i686 C toolchain.
- No first-party OpenPGP verifier, and no signature check in the installer.
- No rustup command, and no change to the global rustup or Cargo state.
- No removal of a `.replaced-` directory that an interrupted run leaves.
- No support claim for the Rust wrapper.

## The other slices

`FP-0133` does the following:

- It generates `fairpane-sys` with Rust layout assertions.
- It compiles those assertions for the host and for `i686-unknown-linux-gnu` with this slice's standard library.
- It proves that the crate resolves no third-party crate.
- It declares the wrapper's target configurations.
- It adds the crate roots to the source inventory.

`FP-0134` links a `fairpane-sys` test against the native library on Windows and Linux. It also implements, registers, and runs the `rust-fmt` and `rust-wrapper` gates.
