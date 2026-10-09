//! FP-0013, FP-0108, FP-0111, and FP-0119 text and font tests. `build.zig` roots a test artifact here that imports the library module as `fairpane`.

test {
    _ = @import("seed_test.zig");
    _ = @import("fixture_test.zig");
    _ = @import("synthetic_test.zig");
    _ = @import("malformed_test.zig");
    _ = @import("bounds_test.zig");
    _ = @import("grapheme_seed_test.zig");
    _ = @import("glyf_test.zig");
    _ = @import("layout_test.zig");
    _ = @import("layout_fixture_test.zig");
}
