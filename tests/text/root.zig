//! FP-0013 text and font tests. `build.zig` roots a test artifact here that imports the library module as `fairpane`.

test {
    _ = @import("seed_test.zig");
    _ = @import("fixture_test.zig");
    _ = @import("synthetic_test.zig");
    _ = @import("malformed_test.zig");
}
