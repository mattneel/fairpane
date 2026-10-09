//! Experimental Fairpane bootstrap. No browser capabilities exist yet.

pub const c_api = @import("c_api.zig");
pub const css = @import("css/css.zig");
pub const dom = @import("dom.zig");
pub const encoding = @import("encoding/root.zig");
pub const engine = @import("engine.zig");
pub const font = @import("font/opentype.zig");
pub const handles = @import("handles.zig");
pub const html = @import("html/root.zig");
pub const js = @import("js/runtime.zig");
pub const text = @import("text/text.zig");
pub const unicode = @import("unicode/properties.zig");
pub const web_string = @import("web_string.zig");

comptime {
    _ = c_api;
}

test {
    _ = @import("abi_scenarios.zig");
    _ = c_api;
    _ = css;
    _ = dom;
    _ = encoding;
    _ = engine;
    _ = font;
    _ = html;
    // The laboratory drives the engine but is not part of the library's API.
    _ = @import("lab.zig");
    _ = @import("lab_identity_test.zig");
    _ = handles;
    _ = @import("memory_budget.zig");
    _ = js;
    _ = unicode;
    _ = @import("unicode/properties_test.zig");
    _ = @import("unicode/reference_test.zig");
    _ = web_string;
    _ = text;
    _ = @import("text/grapheme_test.zig");
}
