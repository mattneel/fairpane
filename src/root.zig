//! Experimental Fairpane bootstrap. No browser capabilities exist yet.

pub const c_api = @import("c_api.zig");
pub const handles = @import("handles.zig");
pub const web_string = @import("web_string.zig");

comptime {
    _ = c_api;
}

test {
    _ = c_api;
    _ = handles;
    _ = web_string;
}
