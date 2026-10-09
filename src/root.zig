//! Experimental Fairpane bootstrap. No browser capabilities exist yet.

pub const c_api = @import("c_api.zig");
pub const dom = @import("dom.zig");
pub const engine = @import("engine.zig");
pub const handles = @import("handles.zig");
pub const js = @import("js/runtime.zig");
pub const web_string = @import("web_string.zig");

comptime {
    _ = c_api;
}

test {
    _ = @import("abi_scenarios.zig");
    _ = c_api;
    _ = dom;
    _ = engine;
    // The laboratory drives the engine but is not part of the library's API.
    _ = @import("lab.zig");
    _ = handles;
    _ = js;
    _ = web_string;
}
