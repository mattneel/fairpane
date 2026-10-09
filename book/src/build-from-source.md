# Build from source

These commands build and test the candidate Zig library.
They do not produce a working browser.

## Controller commands

Use Node 22 or newer.
Run these commands from the repository root.

```text
node tools/fairpane.mjs install-zig
node tools/fairpane.mjs doctor
node tools/fairpane.mjs check
node tools/fairpane.mjs test
node tools/fairpane.mjs run zig-test
node tools/fairpane.mjs run zig-build
```

The controller uses the exact compiler in `toolchains/zig.lock.json`.
It never selects a compiler from `PATH`.
The `zig-test` gate runs the locked compiler with `build test`.
The `zig-build` gate runs it with `build`.
Both gates keep the compiler cache inside the repository.
The build installs the candidate library and experimental C header under `zig-out/`.

[Toolchain policy](toolchain.md) describes the compiler pin and installation boundary.
The existing setup instructions follow.

{{#include ../../START_HERE.md}}
