# Engine source rules

Use first-party Zig and the pinned standard library.
Do not import development runtimes or external rendering libraries.
Keep platform I/O outside portable semantic modules.

Check allocation failure and owner teardown for each new allocation path.
Preserve lossless JavaScript string semantics.
Do not assume that UTF-8 byte offsets are DOM text offsets.

Keep generic reference paths available for optimized behavior.
Do not replace required behavior with successful no-op code.
