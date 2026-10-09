//! HTML tree construction (HTML Standard §13.2.4 and §13.2.6), at whatwg/html commit
//! `efc54f7b70858d9fcf06d1a5871ae215f448c029`, for documents outside tables, templates, framesets, and foreign content.
//!
//! The parser implements every branch of the ten modes that `modes.implemented` reports: initial, before html,
//! before head, in head, in head noscript, after head, in body, text, after body, and after after body. It keeps the stack
//! of open elements, the list of active formatting elements with the Noah's Ark clause, the head and form element
//! pointers, and the frameset-ok flag, and it runs the adoption agency algorithm. Every element that it creates is in the
//! HTML namespace, so the adjusted current node is never foreign, and the dispatcher always selects the current mode.
//!
//! The parser reports `unsupported` exactly where the standard would apply behavior outside those modes: a token for an
//! unimplemented mode, the in head `template` start tag, and the in body `math` and `svg` start tags. `owner` names the
//! task that owns each one. It never skips such behavior or substitutes something else.
//!
//! A `characters` step holds a run of characters. The parser processes it with the result of processing each code point
//! as its own character token: a branch that reprocesses a character leaves the rest of the run to the mode it switches
//! to, and a parse error for a character has that character's own source position from `Tokenizer.characterPosition`.
//!
//! At a `script` end tag in the text mode, `run` returns a script boundary. `FP-0019` owns script preparation, the
//! insertion point, the script nesting level, and the parser pause flag. The parser retains every node that its stack,
//! its list, its element pointers, or its script states reference, so a caller may change the tree between calls of `run`.
//!
//! Steps that the subset never reaches are not implemented here: foster parenting and resetting the insertion mode
//! belong to `FP-0102`, templates and framesets to `FP-0103`, foreign content to `FP-0104`, and the fragment case to
//! `FP-0105`. Speculative parsing, custom element definitions, form-owner association, the reset algorithm of resettable
//! elements, process internal resource links, the steps that set the parser cannot change the mode flag, and `iframe`
//! `srcdoc` documents belong to the FP-0026 frontier decomposition; none of them changes a tree.
//! The `meta` branch changes no encoding, because the parser takes decoded code units and the confidence is never
//! tentative; `FP-0126` owns that hook.

const std = @import("std");
const builtin = @import("builtin");
const dom = @import("../dom.zig");
const web_string = @import("../web_string.zig");
const tokenizer = @import("tokenizer.zig");
const error_codes = @import("errors.zig");
const modes = @import("modes.zig");
const Allocator = std.mem.Allocator;
const NodeHandle = dom.NodeHandle;
const View = web_string.View;
const CodeUnitIndex = web_string.CodeUnitIndex;
const Position = tokenizer.Position;
const Attribute = tokenizer.Attribute;
const Mode = modes.Mode;

pub const ScriptingMode = enum { normal, disabled };

pub const Options = struct { scripting: ScriptingMode };

pub const Unsupported = union(enum) {
    /// The token must be processed by the rules of a mode that `modes.implemented` reports false for.
    mode: Mode,
    /// The in head rules reached a `template` start tag (146325), which FP-0103 owns.
    template_start_tag,
    /// The in body rules reached a `math` or `svg` start tag (147725, 147748), which FP-0104 owns.
    foreign_start_tag,
};

/// The owner task of an unsupported feature.
pub fn owner(feature: Unsupported) []const u8 {
    return switch (feature) {
        .mode => |mode| modes.owner(mode).?,
        .template_start_tag => "FP-0103",
        .foreign_start_tag => "FP-0104",
    };
}

pub const Outcome = union(enum) {
    need_input,
    script: struct { element: NodeHandle, offset: CodeUnitIndex },
    done,
    unsupported: struct { feature: Unsupported, offset: CodeUnitIndex },
};

/// `code` is null for a tree-construction error that the standard names no code for.
pub const TreeParseError = struct { code: ?error_codes.ErrorCode, position: Position };

pub const ScriptState = struct { parser_document: ?NodeHandle, force_async: bool, already_started: bool };

pub const Error = error{ OutOfMemory, HandleSpaceExhausted, HierarchyRequest, ChunkPending, InputFinished };

/// Test builds count each executed branch of each implemented mode, in the flat order of `modes.branchIndex`.
pub var coverage: if (builtin.is_test) [modes.branch_count]u64 else void = if (builtin.is_test) @splat(0) else {};

inline fn hit(comptime mode: Mode, comptime branch: []const u8) void {
    hitCount(mode, branch, 1);
}

inline fn hitCount(comptime mode: Mode, comptime branch: []const u8, count: usize) void {
    if (builtin.is_test) coverage[comptime modes.branchIndex(mode, branch)] += count;
}

fn ascii(comptime text: []const u8) []const u16 {
    const units = comptime blk: {
        var buffer: [text.len]u16 = undefined;
        for (text, &buffer) |byte, *unit| unit.* = byte;
        break :blk buffer;
    };
    return &units;
}

const html_namespace: View = .{ .units = ascii("http://www.w3.org/1999/xhtml") };

/// The tag names that some step of the subset names, and `other` for every other name.
const Tag = enum {
    a,
    address,
    applet,
    area,
    article,
    aside,
    b,
    base,
    basefont,
    bgsound,
    big,
    blockquote,
    body,
    br,
    button,
    caption,
    center,
    code,
    col,
    colgroup,
    dd,
    details,
    dialog,
    dir,
    div,
    dl,
    dt,
    em,
    embed,
    fieldset,
    figcaption,
    figure,
    font,
    footer,
    form,
    frame,
    frameset,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    head,
    header,
    hgroup,
    hr,
    html,
    i,
    iframe,
    image,
    img,
    input,
    keygen,
    li,
    link,
    listing,
    main,
    marquee,
    math,
    menu,
    meta,
    nav,
    nobr,
    noembed,
    noframes,
    noscript,
    object,
    ol,
    optgroup,
    option,
    p,
    param,
    plaintext,
    pre,
    rb,
    rp,
    rt,
    rtc,
    ruby,
    s,
    sarcasm,
    script,
    search,
    section,
    select,
    small,
    source,
    strike,
    strong,
    style,
    summary,
    svg,
    table,
    tbody,
    td,
    template,
    textarea,
    tfoot,
    th,
    thead,
    title,
    tr,
    track,
    tt,
    u,
    ul,
    wbr,
    xmp,
    /// Any other name. Steps compare such names by their code units.
    other,

    /// The longest name of a named tag.
    const longest = 10;

    fn of(name: []const u16) Tag {
        if (name.len > longest) return .other;
        var bytes: [longest]u8 = undefined;
        for (name, bytes[0..name.len]) |unit, *byte| {
            if (unit >= 0x80) return .other;
            byte.* = @intCast(unit);
        }
        return std.meta.stringToEnum(Tag, bytes[0..name.len]) orelse .other;
    }
};

/// The special category (142134 to 142166), for HTML elements.
fn isSpecial(tag: Tag) bool {
    return switch (tag) {
        .address, .applet, .area, .article, .aside, .base, .basefont, .bgsound, .blockquote, .body, .br, .button => true,
        .caption, .center, .col, .colgroup, .dd, .details, .dir, .div, .dl, .dt, .embed, .fieldset, .figcaption => true,
        .figure, .footer, .form, .frame, .frameset, .h1, .h2, .h3, .h4, .h5, .h6, .head, .header, .hgroup, .hr => true,
        .html, .iframe, .img, .input, .keygen, .li, .link, .listing, .main, .marquee, .menu, .meta, .nav => true,
        .noembed, .noframes, .noscript, .object, .ol, .p, .param, .plaintext, .pre, .script, .search, .section => true,
        .select, .source, .style, .summary, .table, .tbody, .td, .template, .textarea, .tfoot, .th, .thead => true,
        .title, .tr, .track, .ul, .wbr, .xmp => true,
        else => false,
    };
}

fn isHeading(tag: Tag) bool {
    return switch (tag) {
        .h1, .h2, .h3, .h4, .h5, .h6 => true,
        else => false,
    };
}

/// The elements that the in body end-of-file, `body` end tag, and `html` end tag entries allow on the stack.
fn closableAtEnd(tag: Tag) bool {
    return switch (tag) {
        .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc, .tbody, .td, .tfoot, .th, .thead, .tr, .body, .html => true,
        else => false,
    };
}

fn isWhitespace(unit: u16) bool {
    return switch (unit) {
        0x09, 0x0A, 0x0C, 0x0D, 0x20 => true,
        else => false,
    };
}

/// The number of code points of `units`, where a surrogate pair is one code point and every other unit is its own.
fn codePointCount(units: []const u16) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (index < units.len) : (count += 1) {
        const pair = units[index] >= 0xD800 and units[index] <= 0xDBFF and index + 1 < units.len and
            units[index + 1] >= 0xDC00 and units[index + 1] <= 0xDFFF;
        index += if (pair) 2 else 1;
    }
    return count;
}

/// The five scope algorithms of 142191 to 142279, for elements in the HTML namespace.
const Scope = enum { default, list_item, button, table };

fn isScopeBoundary(tag: Tag, scope: Scope) bool {
    if (scope == .table) return tag == .html or tag == .table or tag == .template;
    return switch (tag) {
        .applet, .caption, .html, .table, .td, .th, .marquee, .object, .select, .template => true,
        .ol, .ul => scope == .list_item,
        .button => scope == .button,
        else => false,
    };
}

/// ASCII case-insensitive equality of code units and an ASCII string.
fn equalIgnoringCase(units: []const u16, text: []const u8) bool {
    if (units.len != text.len) return false;
    for (units, text) |unit, byte| {
        if (unit >= 0x80 or std.ascii.toLower(@intCast(unit)) != std.ascii.toLower(byte)) return false;
    }
    return true;
}

fn startsWithIgnoringCase(units: []const u16, text: []const u8) bool {
    return units.len >= text.len and equalIgnoringCase(units[0..text.len], text);
}

fn equalAscii(units: []const u16, text: []const u8) bool {
    if (units.len != text.len) return false;
    for (units, text) |unit, byte| {
        if (unit != byte) return false;
    }
    return true;
}

/// The public identifiers that set quirks mode when a DOCTYPE token's public identifier starts with one (145906 to 145966).
const quirks_public_prefixes = [_][]const u8{
    "+//Silmaril//dtd html Pro v0r11 19970101//",
    "-//AS//DTD HTML 3.0 asWedit + extensions//",
    "-//AdvaSoft Ltd//DTD HTML 3.0 asWedit + extensions//",
    "-//IETF//DTD HTML 2.0 Level 1//",
    "-//IETF//DTD HTML 2.0 Level 2//",
    "-//IETF//DTD HTML 2.0 Strict Level 1//",
    "-//IETF//DTD HTML 2.0 Strict Level 2//",
    "-//IETF//DTD HTML 2.0 Strict//",
    "-//IETF//DTD HTML 2.0//",
    "-//IETF//DTD HTML 2.1E//",
    "-//IETF//DTD HTML 3.0//",
    "-//IETF//DTD HTML 3.2 Final//",
    "-//IETF//DTD HTML 3.2//",
    "-//IETF//DTD HTML 3//",
    "-//IETF//DTD HTML Level 0//",
    "-//IETF//DTD HTML Level 1//",
    "-//IETF//DTD HTML Level 2//",
    "-//IETF//DTD HTML Level 3//",
    "-//IETF//DTD HTML Strict Level 0//",
    "-//IETF//DTD HTML Strict Level 1//",
    "-//IETF//DTD HTML Strict Level 2//",
    "-//IETF//DTD HTML Strict Level 3//",
    "-//IETF//DTD HTML Strict//",
    "-//IETF//DTD HTML//",
    "-//Metrius//DTD Metrius Presentational//",
    "-//Microsoft//DTD Internet Explorer 2.0 HTML Strict//",
    "-//Microsoft//DTD Internet Explorer 2.0 HTML//",
    "-//Microsoft//DTD Internet Explorer 2.0 Tables//",
    "-//Microsoft//DTD Internet Explorer 3.0 HTML Strict//",
    "-//Microsoft//DTD Internet Explorer 3.0 HTML//",
    "-//Microsoft//DTD Internet Explorer 3.0 Tables//",
    "-//Netscape Comm. Corp.//DTD HTML//",
    "-//Netscape Comm. Corp.//DTD Strict HTML//",
    "-//O'Reilly and Associates//DTD HTML 2.0//",
    "-//O'Reilly and Associates//DTD HTML Extended 1.0//",
    "-//O'Reilly and Associates//DTD HTML Extended Relaxed 1.0//",
    "-//SQ//DTD HTML 2.0 HoTMetaL + extensions//",
    "-//SoftQuad Software//DTD HoTMetaL PRO 6.0::19990601::extensions to HTML 4.0//",
    "-//SoftQuad//DTD HoTMetaL PRO 4.0::19971010::extensions to HTML 4.0//",
    "-//Spyglass//DTD HTML 2.0 Extended//",
    "-//Sun Microsystems Corp.//DTD HotJava HTML//",
    "-//Sun Microsystems Corp.//DTD HotJava Strict HTML//",
    "-//W3C//DTD HTML 3 1995-03-24//",
    "-//W3C//DTD HTML 3.2 Draft//",
    "-//W3C//DTD HTML 3.2 Final//",
    "-//W3C//DTD HTML 3.2//",
    "-//W3C//DTD HTML 3.2S Draft//",
    "-//W3C//DTD HTML 4.0 Frameset//",
    "-//W3C//DTD HTML 4.0 Transitional//",
    "-//W3C//DTD HTML Experimental 19960712//",
    "-//W3C//DTD HTML Experimental 970421//",
    "-//W3C//DTD W3 HTML//",
    "-//W3O//DTD W3 HTML 3.0//",
    "-//WebTechs//DTD Mozilla HTML 2.0//",
    "-//WebTechs//DTD Mozilla HTML//",
};

/// The public identifier prefixes that depend on whether the system identifier is missing or empty.
const html401_public_prefixes = [_][]const u8{ "-//W3C//DTD HTML 4.01 Frameset//", "-//W3C//DTD HTML 4.01 Transitional//" };

/// The public identifier prefixes that set limited-quirks mode regardless of the system identifier.
const xhtml_public_prefixes = [_][]const u8{ "-//W3C//DTD XHTML 1.0 Frameset//", "-//W3C//DTD XHTML 1.0 Transitional//" };

fn startsWithAny(units: []const u16, prefixes: []const []const u8) bool {
    for (prefixes) |prefix| {
        if (startsWithIgnoringCase(units, prefix)) return true;
    }
    return false;
}

/// The document mode that a DOCTYPE token sets in the initial insertion mode (145895 to 145985), or null for no change.
fn doctypeMode(doctype: tokenizer.Doctype) ?dom.DocumentMode {
    const name = if (doctype.name) |view| view.units else &.{};
    const public_id = if (doctype.public_identifier) |view| view.units else null;
    const system_id = if (doctype.system_identifier) |view| view.units else null;
    if (doctype.force_quirks or !equalAscii(name, "html")) return .quirks;
    if (public_id) |public| {
        if (equalIgnoringCase(public, "-//W3O//DTD W3 HTML Strict 3.0//EN//") or
            equalIgnoringCase(public, "-/W3C/DTD HTML 4.0 Transitional/EN") or
            equalIgnoringCase(public, "HTML")) return .quirks;
    }
    if (system_id) |system| {
        if (equalIgnoringCase(system, "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd")) return .quirks;
    }
    const public = public_id orelse return null;
    if (startsWithAny(public, &quirks_public_prefixes)) return .quirks;
    const system_missing_or_empty = if (system_id) |system| system.len == 0 else true;
    if (system_missing_or_empty and startsWithAny(public, &html401_public_prefixes)) return .quirks;
    if (startsWithAny(public, &xhtml_public_prefixes)) return .limited_quirks;
    if (!system_missing_or_empty and startsWithAny(public, &html401_public_prefixes)) return .limited_quirks;
    return null;
}

/// A start or end tag token as tree construction processes it. The in body `image` entry renames it, and branches that
/// acknowledge the self-closing flag set `acknowledged`.
const TagToken = struct {
    name: []const u16,
    tag: Tag,
    attributes: []const Attribute,
    self_closing: bool,
    acknowledged: bool = false,

    fn is(token: *const TagToken, comptime tags: []const Tag) bool {
        return std.mem.indexOfScalar(Tag, tags, token.tag) != null;
    }

    fn acknowledge(token: *TagToken) void {
        token.acknowledged = true;
    }
};

const Token = union(enum) {
    doctype: tokenizer.Doctype,
    start_tag: *TagToken,
    end_tag: *TagToken,
    comment: View,
    processing_instruction: tokenizer.ProcessingInstruction,
    end_of_file,
};

/// What a mode's rules did with a token.
const Flow = union(enum) {
    handled,
    /// The rules switched the insertion mode and reprocess the token in it.
    reprocess,
    /// The parser stops processing the token with this outcome.
    outcome: Outcome,
};

const OpenElement = struct { node: NodeHandle, tag: Tag };

/// The attributes of the token that created a formatting element, which the parser owns.
const OwnedAttributes = struct {
    list: []Attribute = &.{},
    units: []u16 = &.{},

    fn copy(gpa: Allocator, attributes: []const Attribute) Allocator.Error!OwnedAttributes {
        if (attributes.len == 0) return .{};
        var total: usize = 0;
        for (attributes) |attribute| total += attribute.name.units.len + attribute.value.units.len;
        const units = try gpa.alloc(u16, total);
        errdefer gpa.free(units);
        const list = try gpa.alloc(Attribute, attributes.len);
        var used: usize = 0;
        for (attributes, list) |attribute, *owned| {
            const name = units[used..][0..attribute.name.units.len];
            @memcpy(name, attribute.name.units);
            used += name.len;
            const value = units[used..][0..attribute.value.units.len];
            @memcpy(value, attribute.value.units);
            used += value.len;
            owned.* = .{ .name = .{ .units = name }, .value = .{ .units = value }, .name_span = attribute.name_span, .value_span = attribute.value_span };
        }
        return .{ .list = list, .units = units };
    }

    fn deinit(owned: *OwnedAttributes, gpa: Allocator) void {
        gpa.free(owned.list);
        gpa.free(owned.units);
        owned.* = undefined;
    }

    /// Whether both lists pair up by name and value, in any order. Each list has distinct names, and every attribute of a
    /// token is in no namespace.
    fn same(a: []const Attribute, b: []const Attribute) bool {
        if (a.len != b.len) return false;
        for (a) |left| {
            const paired = for (b) |right| {
                if (left.name.eql(right.name)) break left.value.eql(right.value);
            } else false;
            if (!paired) return false;
        }
        return true;
    }
};

const FormattingEntry = union(enum) {
    marker,
    element: struct { node: NodeHandle, tag: Tag, attributes: OwnedAttributes },
};

/// Where the adoption agency algorithm puts the new formatting element in the list.
const Bookmark = union(enum) {
    /// The position of the formatting element.
    formatting_element,
    /// Immediately after this element.
    after: NodeHandle,
};

/// Maps a store failure to the parser's errors. The parser names only live nodes, because it retains every node that it
/// keeps, and no step of the subset inserts before a reference child, so lookup errors and `NotFound` cannot occur.
fn storeError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.HandleSpaceExhausted => error.HandleSpaceExhausted,
        error.HierarchyRequest => error.HierarchyRequest,
        else => unreachable,
    };
}

pub const Parser = struct {
    gpa: Allocator,
    store: *dom.Store,
    document_node: NodeHandle,
    scripting: ScriptingMode,
    tokenizer: tokenizer.Tokenizer,

    mode: Mode = .initial,
    original_mode: Mode = .initial,
    stack: std.ArrayList(OpenElement) = .empty,
    formatting: std.ArrayList(FormattingEntry) = .empty,
    head: ?NodeHandle = null,
    form: ?NodeHandle = null,
    frameset_ok: bool = true,
    /// Whether the next token is ignored when it is a U+000A character token (pre, listing, and textarea).
    ignore_line_feed: bool = false,
    scripts: std.AutoHashMapUnmanaged(NodeHandle, ScriptState) = .empty,
    parse_errors: std.ArrayList(TreeParseError) = .empty,
    /// The sticky failure: `OutOfMemory`, `HandleSpaceExhausted`, or `HierarchyRequest`.
    failure: ?Error = null,
    /// The `done` or `unsupported` outcome, which every later `run` returns.
    ended: ?Outcome = null,
    /// The start and end of the token being processed.
    token_start: Position = undefined,
    token_end: Position = undefined,

    /// Creates an HTML document in no-quirks mode, a tokenizer, and an empty stack, list, and error list.
    pub fn init(gpa: Allocator, store: *dom.Store, options: Options) Error!Parser {
        const document_node = store.createHtmlDocument() catch |err| return storeError(err);
        return .{
            .gpa = gpa,
            .store = store,
            .document_node = document_node,
            .scripting = options.scripting,
            .tokenizer = .init(gpa),
        };
    }

    /// Releases every node that the parser retains and frees the parser's memory. The document stays in the store.
    pub fn deinit(p: *Parser) void {
        for (p.stack.items) |entry| p.release(entry.node);
        p.stack.deinit(p.gpa);
        for (p.formatting.items) |*entry| switch (entry.*) {
            .marker => {},
            .element => |*element| {
                p.release(element.node);
                element.attributes.deinit(p.gpa);
            },
        };
        p.formatting.deinit(p.gpa);
        if (p.head) |node| p.release(node);
        if (p.form) |node| p.release(node);
        var scripts = p.scripts.keyIterator();
        while (scripts.next()) |node| p.release(node.*);
        p.scripts.deinit(p.gpa);
        p.parse_errors.deinit(p.gpa);
        p.tokenizer.deinit();
        p.* = undefined;
    }

    pub fn document(p: *const Parser) NodeHandle {
        return p.document_node;
    }

    /// Passes `chunk` to the tokenizer, which borrows it until `run` returns `need_input`, or until `deinit`.
    pub fn feed(p: *Parser, chunk: []const u16) Error!void {
        if (p.failure) |err| return err;
        return p.tokenizer.feed(chunk);
    }

    /// Marks the end of the input after any borrowed chunk.
    pub fn finish(p: *Parser) Error!void {
        if (p.failure) |err| return err;
        return p.tokenizer.finish();
    }

    /// Processes tokens until the tokenizer needs input, a `script` end tag ends the text mode, the parser stops parsing,
    /// or the next step needs behavior outside the subset. After `done` or `unsupported`, it returns the same outcome
    /// again and reads no input. `OutOfMemory`, `HandleSpaceExhausted`, and `HierarchyRequest` are sticky.
    pub fn run(p: *Parser) Error!Outcome {
        if (p.failure) |err| return err;
        if (p.ended) |outcome| return outcome;
        return p.runTokens() catch |err| {
            p.failure = err;
            return err;
        };
    }

    /// Every parse error in step order: tokenizer errors with their codes, and tree-construction errors.
    pub fn errors(p: *const Parser) []const TreeParseError {
        return p.parse_errors.items;
    }

    /// The state of a `script` element that a `script` start tag created, or null for any other node.
    pub fn scriptState(p: *const Parser, element: NodeHandle) ?ScriptState {
        return p.scripts.get(element);
    }

    fn runTokens(p: *Parser) Error!Outcome {
        while (true) {
            // Every element that the parser creates is in the HTML namespace, so the adjusted current node is never foreign.
            p.tokenizer.adjusted_current_node_is_foreign = false;
            const step = (p.tokenizer.next() catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.ChunkPending, error.InputFinished => unreachable,
            }) orelse unreachable; // The end-of-file token always stops parsing or ends in `unsupported`.
            switch (step) {
                .need_input => return .need_input,
                .parse_error => |e| try p.parse_errors.append(p.gpa, .{ .code = e.code, .position = e.position }),
                .token => |token| if (try p.processToken(token)) |outcome| return outcome,
            }
        }
    }

    fn processToken(p: *Parser, token: tokenizer.Token) Error!?Outcome {
        p.token_start = token.span.start;
        p.token_end = token.span.end;
        const ignore_line_feed = p.ignore_line_feed;
        p.ignore_line_feed = false;
        switch (token.kind) {
            .characters => |view| {
                const first: usize = if (ignore_line_feed and view.units[0] == '\n') 1 else 0;
                return p.processCharacters(view.units, first);
            },
            .doctype => |doctype| return p.dispatch(.{ .doctype = doctype }),
            .comment => |data| return p.dispatch(.{ .comment = data }),
            .processing_instruction => |instruction| return p.dispatch(.{ .processing_instruction = instruction }),
            .end_of_file => return p.dispatch(.end_of_file),
            .end_tag => |tag| {
                var end_tag = tagToken(tag);
                return p.dispatch(.{ .end_tag = &end_tag });
            },
            .start_tag => |tag| {
                var start_tag = tagToken(tag);
                const outcome = try p.dispatch(.{ .start_tag = &start_tag });
                if (outcome != null) return outcome;
                // A start tag whose self-closing flag no branch acknowledged (142510 to 142516). The error follows every
                // other error of the token.
                if (start_tag.self_closing and !start_tag.acknowledged) {
                    try p.parse_errors.append(p.gpa, .{ .code = .non_void_html_element_start_tag_with_trailing_solidus, .position = p.token_start });
                }
                return null;
            },
        }
    }

    fn tagToken(tag: tokenizer.Tag) TagToken {
        return .{ .name = tag.name.units, .tag = Tag.of(tag.name.units), .attributes = tag.attributes, .self_closing = tag.self_closing };
    }

    /// The tree construction dispatcher (145185 to 145208). The adjusted current node is always null or an HTML element,
    /// so it processes the token by the rules of the current insertion mode.
    fn dispatch(p: *Parser, token: Token) Error!?Outcome {
        while (true) {
            if (!modes.implemented(p.mode)) return p.unsupported(.{ .mode = p.mode }, p.token_start.offset);
            const flow = switch (p.mode) {
                .initial => try p.initial(token),
                .before_html => try p.beforeHtml(token),
                .before_head => try p.beforeHead(token),
                .in_head => try p.inHead(token),
                .in_head_noscript => try p.inHeadNoscript(token),
                .after_head => try p.afterHead(token),
                .in_body => try p.inBody(token),
                .text => try p.text(token),
                .after_body => try p.afterBody(token),
                .after_after_body => try p.afterAfterBody(token),
                else => unreachable,
            };
            switch (flow) {
                .handled => return null,
                .reprocess => continue,
                .outcome => |outcome| return outcome,
            }
        }
    }

    fn unsupported(p: *Parser, feature: Unsupported, offset: CodeUnitIndex) Outcome {
        const outcome: Outcome = .{ .unsupported = .{ .feature = feature, .offset = offset } };
        p.ended = outcome;
        return outcome;
    }

    /// Stop parsing (149578 onward). Only step 4, which pops all nodes off the stack, belongs to the parser.
    fn stopParsing(p: *Parser) Flow {
        while (p.stack.items.len != 0) p.popCurrent();
        p.ended = .done;
        return .{ .outcome = .done };
    }

    // Parse errors.

    /// A tree-construction parse error at the start of the token being processed.
    fn parseError(p: *Parser) Error!void {
        try p.parseErrorAt(p.token_start);
    }

    fn parseErrorAt(p: *Parser, position: Position) Error!void {
        try p.parse_errors.append(p.gpa, .{ .code = null, .position = position });
    }

    // Store access. The parser retains every node that it names, so lookups cannot fail.

    fn retain(p: *Parser, node: NodeHandle) void {
        p.store.retain(node) catch unreachable;
    }

    fn release(p: *Parser, node: NodeHandle) void {
        p.store.release(node) catch unreachable;
    }

    fn kindOf(p: *Parser, node: NodeHandle) dom.Kind {
        return p.store.nodeKind(node) catch unreachable;
    }

    fn parentOf(p: *Parser, node: NodeHandle) ?NodeHandle {
        return p.store.parentNode(node) catch unreachable;
    }

    fn nodeDocument(p: *Parser, node: NodeHandle) NodeHandle {
        return p.store.nodeDocument(node) catch unreachable;
    }

    fn localName(p: *Parser, element: NodeHandle) []const u16 {
        return (p.store.elementName(element) catch unreachable).?.local_name.units;
    }

    fn hasElementChild(p: *Parser, node: NodeHandle) bool {
        var children = p.store.children(node) catch unreachable;
        while (children.next()) |child| {
            if (p.kindOf(child) == .element) return true;
        }
        return false;
    }

    /// Whether `ancestor` is an inclusive ancestor of `node`. No node has a host yet, so it is the host-including relation.
    fn isInclusiveAncestor(p: *Parser, ancestor: NodeHandle, node: NodeHandle) bool {
        var cursor: ?NodeHandle = node;
        while (cursor) |current| : (cursor = p.parentOf(current)) {
            if (std.meta.eql(current, ancestor)) return true;
        }
        return false;
    }

    fn append(p: *Parser, parent: NodeHandle, node: NodeHandle) Error!void {
        p.store.appendChild(parent, node) catch |err| return storeError(err);
    }

    // The stack of open elements.

    fn currentNode(p: *const Parser) OpenElement {
        return p.stack.items[p.stack.items.len - 1];
    }

    fn popCurrent(p: *Parser) void {
        p.release(p.stack.pop().?.node);
    }

    fn removeFromStack(p: *Parser, index: usize) void {
        p.release(p.stack.orderedRemove(index).node);
    }

    fn pushElement(p: *Parser, element: OpenElement) Error!void {
        try p.stack.ensureUnusedCapacity(p.gpa, 1);
        p.retain(element.node);
        p.stack.appendAssumeCapacity(element);
    }

    fn stackIndex(p: *const Parser, node: NodeHandle) ?usize {
        var index = p.stack.items.len;
        while (index > 0) {
            index -= 1;
            if (std.meta.eql(p.stack.items[index].node, node)) return index;
        }
        return null;
    }

    /// Whether `entry` is an HTML element with the tag name `name`, whose tag is `tag`.
    fn isNamed(p: *Parser, entry: OpenElement, tag: Tag, name: []const u16) bool {
        if (entry.tag != tag) return false;
        return tag != .other or std.mem.eql(u16, p.localName(entry.node), name);
    }

    fn currentIs(p: *const Parser, tag: Tag) bool {
        return p.currentNode().tag == tag;
    }

    /// "Has an element in the specific scope" for an element type of the HTML namespace other than `other`.
    fn hasInScope(p: *const Parser, tag: Tag, scope: Scope) bool {
        std.debug.assert(tag != .other);
        var index = p.stack.items.len;
        while (index > 0) {
            index -= 1;
            const entry = p.stack.items[index].tag;
            if (entry == tag) return true;
            if (isScopeBoundary(entry, scope)) return false;
        }
        unreachable; // The html element is a boundary of every scope.
    }

    /// "Has an element in the specific scope" for one node.
    fn hasNodeInScope(p: *const Parser, node: NodeHandle, scope: Scope) bool {
        var index = p.stack.items.len;
        while (index > 0) {
            index -= 1;
            const entry = p.stack.items[index];
            if (std.meta.eql(entry.node, node)) return true;
            if (isScopeBoundary(entry.tag, scope)) return false;
        }
        return false;
    }

    fn hasHeadingInScope(p: *const Parser) bool {
        var index = p.stack.items.len;
        while (index > 0) {
            index -= 1;
            const entry = p.stack.items[index].tag;
            if (isHeading(entry)) return true;
            if (isScopeBoundary(entry, .default)) return false;
        }
        unreachable;
    }

    fn hasTemplate(p: *const Parser) bool {
        for (p.stack.items) |entry| {
            if (entry.tag == .template) return true;
        }
        return false;
    }

    /// Whether the stack holds a node other than the elements that `closableAtEnd` allows.
    fn hasUnclosableNode(p: *const Parser) bool {
        for (p.stack.items) |entry| {
            if (!closableAtEnd(entry.tag)) return true;
        }
        return false;
    }

    fn popUntilTag(p: *Parser, tag: Tag) void {
        std.debug.assert(tag != .other);
        while (true) {
            const popped = p.currentNode().tag;
            p.popCurrent();
            if (popped == tag) return;
        }
    }

    /// Generate implied end tags (145819 to 145830), except for elements with the tag `except`.
    fn generateImpliedEndTags(p: *Parser, except: ?Tag) void {
        while (true) {
            const tag = p.currentNode().tag;
            if (except != null and tag == except.?) return;
            switch (tag) {
                .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc => p.popCurrent(),
                else => return,
            }
        }
    }

    /// Close a `p` element (147833 to 147847).
    fn closeP(p: *Parser) Error!void {
        p.generateImpliedEndTags(.p);
        if (!p.currentIs(.p)) try p.parseError();
        p.popUntilTag(.p);
    }

    fn closePInButtonScope(p: *Parser) Error!void {
        if (p.hasInScope(.p, .button)) try p.closeP();
    }

    // Creating and inserting nodes.

    /// Create an element for a token (145342 to 145462) in the HTML namespace. The element's node document is the node
    /// document of `intended_parent`. Speculative parsing, custom element definitions, the reset algorithm, and form-owner
    /// association belong to the FP-0026 frontier decomposition and change no tree.
    fn createElementForToken(p: *Parser, name: []const u16, attributes: []const Attribute, intended_parent: NodeHandle) Error!NodeHandle {
        const element = p.store.createElement(p.nodeDocument(intended_parent), html_namespace, .{ .units = name }) catch |err| return storeError(err);
        for (attributes) |attribute| {
            p.store.setAttribute(element, null, attribute.name, attribute.value) catch |err| return storeError(err);
        }
        return element;
    }

    /// Insert an element at the adjusted insertion location (145488 to 145527), with the location (`target`, null).
    fn insertAtLocation(p: *Parser, element: NodeHandle, target: NodeHandle) Error!void {
        if (p.parentOf(element) != null) return;
        if (p.isInclusiveAncestor(element, target)) return;
        if (p.kindOf(target) == .document and p.hasElementChild(target)) return;
        try p.append(target, element);
    }

    /// Insert an HTML element for a token (145558 to 145561): the appropriate place for inserting a node is the end of
    /// the current node, because foster parenting is never enabled and the current node is never a template.
    fn insertHtmlElement(p: *Parser, name: []const u16, tag: Tag, attributes: []const Attribute) Error!NodeHandle {
        try p.stack.ensureUnusedCapacity(p.gpa, 1);
        const target = p.currentNode().node;
        const element = try p.createElementForToken(name, attributes, target);
        try p.insertAtLocation(element, target);
        p.retain(element);
        p.stack.appendAssumeCapacity(.{ .node = element, .tag = tag });
        return element;
    }

    fn insertTagElement(p: *Parser, token: *const TagToken) Error!NodeHandle {
        return p.insertHtmlElement(token.name, token.tag, token.attributes);
    }

    /// Insert an HTML element for a start tag token with no attributes.
    fn insertImpliedElement(p: *Parser, comptime tag: Tag) Error!NodeHandle {
        return p.insertHtmlElement(ascii(@tagName(tag)), tag, &.{});
    }

    /// Insert a character (145672 to 145704) for each code point of `units`, at the end of the current node.
    fn insertCharacters(p: *Parser, units: []const u16) Error!void {
        const target = p.currentNode().node;
        if (p.kindOf(target) == .document) return;
        if (p.store.lastChild(target) catch unreachable) |last| {
            if (p.kindOf(last) == .text) {
                p.store.appendData(last, .{ .units = units }) catch |err| return storeError(err);
                return;
            }
        }
        const node = p.store.createText(p.nodeDocument(target), .{ .units = units }) catch |err| return storeError(err);
        try p.append(target, node);
    }

    /// Insert a comment (145750 to 145769) at the end of `target`, or of the current node when `target` is null.
    fn insertComment(p: *Parser, data: View, target: ?NodeHandle) Error!void {
        const parent = target orelse p.currentNode().node;
        const node = p.store.createComment(p.nodeDocument(parent), data) catch |err| return storeError(err);
        try p.append(parent, node);
    }

    /// Insert a processing instruction (145771 to 145793) at the end of `target`, or of the current node.
    fn insertProcessingInstruction(p: *Parser, instruction: tokenizer.ProcessingInstruction, target: ?NodeHandle) Error!void {
        const parent = target orelse p.currentNode().node;
        const node = p.store.createProcessingInstruction(p.nodeDocument(parent), instruction.target, instruction.data) catch |err| return storeError(err);
        try p.append(parent, node);
    }

    fn switchTokenizer(p: *Parser, state: tokenizer.ContentState) Error!void {
        p.tokenizer.switchTo(state) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.SwitchNotAllowed => unreachable,
        };
    }

    /// The generic raw text and RCDATA element parsing algorithms (145795 to 145816).
    fn parseTextElement(p: *Parser, token: *const TagToken, state: tokenizer.ContentState) Error!void {
        _ = try p.insertTagElement(token);
        try p.switchTokenizer(state);
        p.original_mode = p.mode;
        p.mode = .text;
    }

    // The list of active formatting elements.

    fn formattingIndex(p: *const Parser, node: NodeHandle) ?usize {
        var index = p.formatting.items.len;
        while (index > 0) {
            index -= 1;
            switch (p.formatting.items[index]) {
                .marker => {},
                .element => |element| if (std.meta.eql(element.node, node)) return index,
            }
        }
        return null;
    }

    /// The last element with the tag `tag` after the last marker.
    fn lastFormattingAfterMarker(p: *const Parser, tag: Tag) ?usize {
        var index = p.formatting.items.len;
        while (index > 0) {
            index -= 1;
            switch (p.formatting.items[index]) {
                .marker => return null,
                .element => |element| if (element.tag == tag) return index,
            }
        }
        return null;
    }

    fn removeFormattingAt(p: *Parser, index: usize) void {
        var entry = p.formatting.orderedRemove(index);
        switch (entry) {
            .marker => {},
            .element => |*element| {
                p.release(element.node);
                element.attributes.deinit(p.gpa);
            },
        }
    }

    fn insertMarker(p: *Parser) Error!void {
        try p.formatting.append(p.gpa, .marker);
    }

    /// Push onto the list of active formatting elements (142306 to 142329), with the Noah's Ark clause.
    fn pushFormatting(p: *Parser, node: NodeHandle, token: *const TagToken) Error!void {
        var attributes = try OwnedAttributes.copy(p.gpa, token.attributes);
        errdefer attributes.deinit(p.gpa);
        try p.formatting.ensureUnusedCapacity(p.gpa, 1);
        var count: usize = 0;
        var earliest: usize = undefined;
        var index = p.formatting.items.len;
        while (index > 0) {
            index -= 1;
            switch (p.formatting.items[index]) {
                .marker => break,
                .element => |element| if (element.tag == token.tag and OwnedAttributes.same(element.attributes.list, token.attributes)) {
                    count += 1;
                    earliest = index;
                },
            }
        }
        if (count >= 3) p.removeFormattingAt(earliest);
        p.retain(node);
        p.formatting.appendAssumeCapacity(.{ .element = .{ .node = node, .tag = token.tag, .attributes = attributes } });
    }

    fn isMarkerOrOpen(p: *const Parser, entry: FormattingEntry) bool {
        return switch (entry) {
            .marker => true,
            .element => |element| p.stackIndex(element.node) != null,
        };
    }

    /// Reconstruct the active formatting elements (142331 to 142377).
    fn reconstructFormatting(p: *Parser) Error!void {
        const length = p.formatting.items.len;
        if (length == 0) return;
        if (p.isMarkerOrOpen(p.formatting.items[length - 1])) return;
        // Rewind to the entry after the last marker or open element.
        var index = length - 1;
        while (index > 0 and !p.isMarkerOrOpen(p.formatting.items[index - 1])) index -= 1;
        // Create and advance.
        while (index < length) : (index += 1) {
            const entry = &p.formatting.items[index].element;
            const element = try p.insertHtmlElement(p.localName(entry.node), entry.tag, entry.attributes.list);
            p.retain(element);
            p.release(entry.node);
            entry.node = element;
        }
    }

    /// Clear the list of active formatting elements up to the last marker (142379 to 142395).
    fn clearFormattingToMarker(p: *Parser) void {
        while (p.formatting.items.len != 0) {
            const last = p.formatting.items.len - 1;
            const was_marker = p.formatting.items[last] == .marker;
            p.removeFormattingAt(last);
            if (was_marker) return;
        }
    }

    // Character tokens.

    /// Processes the units of a `characters` step from `first`, as if each code point were its own token.
    fn processCharacters(p: *Parser, units: []const u16, first: usize) Error!?Outcome {
        var index = first;
        while (index < units.len) {
            if (!modes.implemented(p.mode)) {
                return p.unsupported(.{ .mode = p.mode }, p.tokenizer.characterPosition(index).offset);
            }
            index = switch (p.mode) {
                .initial => try p.initialCharacters(units, index),
                .before_html => try p.beforeHtmlCharacters(units, index),
                .before_head => try p.beforeHeadCharacters(units, index),
                .in_head => try p.inHeadCharacters(units, index),
                .in_head_noscript => try p.inHeadNoscriptCharacters(units, index),
                .after_head => try p.afterHeadCharacters(units, index),
                .in_body => try p.inBodyCharacters(units, index),
                .text => try p.textCharacters(units, index),
                .after_body => try p.afterBodyCharacters(units, index),
                .after_after_body => try p.afterAfterBodyCharacters(units, index),
                else => unreachable,
            };
        }
        return null;
    }

    /// Returns the end of the run of whitespace units that starts at `index`.
    fn whitespaceEnd(units: []const u16, index: usize) usize {
        var end = index;
        while (end < units.len and isWhitespace(units[end])) end += 1;
        return end;
    }

    /// The in body rules for the run of non-NULL characters `units`: reconstruct the active formatting elements, insert
    /// the characters, and, for any character other than whitespace, set the frameset-ok flag to "not ok".
    /// Reconstruction before a later character of the run finds the last entry open, so it does nothing.
    fn inBodyRun(p: *Parser, units: []const u16) Error!void {
        var whitespace: usize = 0;
        for (units) |unit| {
            if (isWhitespace(unit)) whitespace += 1;
        }
        hitCount(.in_body, "whitespace", whitespace);
        hitCount(.in_body, "other character", codePointCount(units) - whitespace);
        try p.reconstructFormatting();
        try p.insertCharacters(units);
        if (whitespace != units.len) p.frameset_ok = false;
    }

    fn initialCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        hitCount(.initial, "whitespace", end - index);
        if (end == units.len) return end;
        hit(.initial, "else");
        try p.initialAnythingElse(p.tokenizer.characterPosition(end));
        return end;
    }

    fn beforeHtmlCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        hitCount(.before_html, "whitespace", end - index);
        if (end == units.len) return end;
        hit(.before_html, "else");
        try p.beforeHtmlAnythingElse();
        return end;
    }

    fn beforeHeadCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        hitCount(.before_head, "whitespace", end - index);
        if (end == units.len) return end;
        hit(.before_head, "else");
        try p.beforeHeadAnythingElse();
        return end;
    }

    fn inHeadCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        if (end != index) {
            hitCount(.in_head, "whitespace", end - index);
            try p.insertCharacters(units[index..end]);
            return end;
        }
        hit(.in_head, "else");
        p.inHeadAnythingElse();
        return index;
    }

    fn inHeadNoscriptCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        if (end != index) {
            hitCount(.in_head_noscript, "whitespace, comment, processing instruction, or start basefont, bgsound, link, meta, noframes, or style", end - index);
            // Using the rules for in head.
            hitCount(.in_head, "whitespace", end - index);
            try p.insertCharacters(units[index..end]);
            return end;
        }
        hit(.in_head_noscript, "else");
        try p.parseErrorAt(p.tokenizer.characterPosition(index));
        p.inHeadNoscriptAnythingElse();
        return index;
    }

    fn afterHeadCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        if (end != index) {
            hitCount(.after_head, "whitespace", end - index);
            try p.insertCharacters(units[index..end]);
            return end;
        }
        hit(.after_head, "else");
        try p.afterHeadAnythingElse();
        return index;
    }

    fn inBodyCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        if (units[index] == 0) {
            hit(.in_body, "NULL");
            try p.parseErrorAt(p.tokenizer.characterPosition(index));
            return index + 1;
        }
        const end = std.mem.indexOfScalarPos(u16, units, index, 0) orelse units.len;
        try p.inBodyRun(units[index..end]);
        return end;
    }

    fn textCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        hitCount(.text, "character", codePointCount(units[index..]));
        try p.insertCharacters(units[index..]);
        return units.len;
    }

    fn afterBodyCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        if (end != index) {
            hitCount(.after_body, "whitespace", end - index);
            try p.inBodyRun(units[index..end]);
            return end;
        }
        hit(.after_body, "else");
        try p.parseErrorAt(p.tokenizer.characterPosition(index));
        p.mode = .in_body;
        return index;
    }

    fn afterAfterBodyCharacters(p: *Parser, units: []const u16, index: usize) Error!usize {
        const end = whitespaceEnd(units, index);
        if (end != index) {
            hitCount(.after_after_body, "DOCTYPE, whitespace, or start html", end - index);
            try p.inBodyRun(units[index..end]);
            return end;
        }
        hit(.after_after_body, "else");
        try p.parseErrorAt(p.tokenizer.characterPosition(index));
        p.mode = .in_body;
        return index;
    }

    // The anything else entries that characters share with other tokens.

    fn initialAnythingElse(p: *Parser, position: Position) Error!void {
        // The document is never an iframe srcdoc document, and the parser cannot change the mode flag is false.
        try p.parseErrorAt(position);
        p.store.setDocumentMode(p.document_node, .quirks) catch unreachable;
        p.mode = .before_html;
    }

    fn beforeHtmlAnythingElse(p: *Parser) Error!void {
        try p.stack.ensureUnusedCapacity(p.gpa, 1);
        const element = p.store.createElement(p.document_node, html_namespace, .{ .units = ascii("html") }) catch |err| return storeError(err);
        try p.append(p.document_node, element);
        p.retain(element);
        p.stack.appendAssumeCapacity(.{ .node = element, .tag = .html });
        p.mode = .before_head;
    }

    fn setHead(p: *Parser, head: NodeHandle) void {
        std.debug.assert(p.head == null);
        p.retain(head);
        p.head = head;
    }

    fn beforeHeadAnythingElse(p: *Parser) Error!void {
        p.setHead(try p.insertImpliedElement(.head));
        p.mode = .in_head;
    }

    fn inHeadAnythingElse(p: *Parser) void {
        p.popCurrent();
        p.mode = .after_head;
    }

    fn inHeadNoscriptAnythingElse(p: *Parser) void {
        p.popCurrent();
        p.mode = .in_head;
    }

    fn afterHeadAnythingElse(p: *Parser) Error!void {
        _ = try p.insertImpliedElement(.body);
        p.frameset_ok = true;
        p.mode = .in_body;
    }

    // The insertion modes.

    /// 13.2.6.4.1, the initial insertion mode.
    fn initial(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .comment => |data| {
                hit(.initial, "comment");
                try p.insertComment(data, p.document_node);
            },
            .processing_instruction => |instruction| {
                hit(.initial, "processing instruction");
                try p.insertProcessingInstruction(instruction, p.document_node);
            },
            .doctype => |doctype| {
                hit(.initial, "DOCTYPE");
                try p.initialDoctype(doctype);
            },
            .start_tag, .end_tag, .end_of_file => {
                hit(.initial, "else");
                try p.initialAnythingElse(p.token_start);
                return .reprocess;
            },
        }
        return .handled;
    }

    fn initialDoctype(p: *Parser, doctype: tokenizer.Doctype) Error!void {
        const name = if (doctype.name) |view| view.units else &.{};
        const legacy = if (doctype.system_identifier) |system| equalAscii(system.units, "about:legacy-compat") else true;
        if (!equalAscii(name, "html") or doctype.public_identifier != null or !legacy) try p.parseError();
        const empty: View = .{ .units = &.{} };
        const node = p.store.createDocumentType(
            p.document_node,
            .{ .units = name },
            doctype.public_identifier orelse empty,
            doctype.system_identifier orelse empty,
        ) catch |err| return storeError(err);
        var has_doctype_or_element = false;
        var children = p.store.children(p.document_node) catch unreachable;
        while (children.next()) |child| {
            switch (p.kindOf(child)) {
                .document_type, .element => has_doctype_or_element = true,
                else => {},
            }
        }
        if (!has_doctype_or_element) try p.append(p.document_node, node);
        if (doctypeMode(doctype)) |mode| p.store.setDocumentMode(p.document_node, mode) catch unreachable;
        p.mode = .before_html;
    }

    /// 13.2.6.4.2, the before html insertion mode.
    fn beforeHtml(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .doctype => {
                hit(.before_html, "DOCTYPE");
                try p.parseError();
                return .handled;
            },
            .comment => |data| {
                hit(.before_html, "comment");
                try p.insertComment(data, p.document_node);
                return .handled;
            },
            .processing_instruction => |instruction| {
                hit(.before_html, "processing instruction");
                try p.insertProcessingInstruction(instruction, p.document_node);
                return .handled;
            },
            .start_tag => |tag| if (tag.tag == .html) {
                hit(.before_html, "start html");
                try p.stack.ensureUnusedCapacity(p.gpa, 1);
                const element = try p.createElementForToken(tag.name, tag.attributes, p.document_node);
                try p.insertAtLocation(element, p.document_node);
                p.retain(element);
                p.stack.appendAssumeCapacity(.{ .node = element, .tag = .html });
                p.mode = .before_head;
                return .handled;
            },
            .end_tag => |tag| if (tag.is(&.{ .head, .body, .html, .br })) {
                hit(.before_html, "end head, body, html, or br");
            } else {
                hit(.before_html, "other end tag");
                try p.parseError();
                return .handled;
            },
            .end_of_file => {},
        }
        hit(.before_html, "else");
        try p.beforeHtmlAnythingElse();
        return .reprocess;
    }

    /// 13.2.6.4.3, the before head insertion mode.
    fn beforeHead(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .comment => |data| {
                hit(.before_head, "comment");
                try p.insertComment(data, null);
                return .handled;
            },
            .processing_instruction => |instruction| {
                hit(.before_head, "processing instruction");
                try p.insertProcessingInstruction(instruction, null);
                return .handled;
            },
            .doctype => {
                hit(.before_head, "DOCTYPE");
                try p.parseError();
                return .handled;
            },
            .start_tag => |tag| switch (tag.tag) {
                .html => {
                    hit(.before_head, "start html");
                    return p.inBody(token);
                },
                .head => {
                    hit(.before_head, "start head");
                    p.setHead(try p.insertTagElement(tag));
                    p.mode = .in_head;
                    return .handled;
                },
                else => {},
            },
            .end_tag => |tag| if (tag.is(&.{ .head, .body, .html, .br })) {
                hit(.before_head, "end head, body, html, or br");
            } else {
                hit(.before_head, "other end tag");
                try p.parseError();
                return .handled;
            },
            .end_of_file => {},
        }
        hit(.before_head, "else");
        try p.beforeHeadAnythingElse();
        return .reprocess;
    }

    /// 13.2.6.4.4, the in head insertion mode.
    fn inHead(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .comment => |data| {
                hit(.in_head, "comment");
                try p.insertComment(data, null);
                return .handled;
            },
            .processing_instruction => |instruction| {
                hit(.in_head, "processing instruction");
                try p.insertProcessingInstruction(instruction, null);
                return .handled;
            },
            .doctype => {
                hit(.in_head, "DOCTYPE");
                try p.parseError();
                return .handled;
            },
            .start_tag => |tag| switch (tag.tag) {
                .html => {
                    hit(.in_head, "start html");
                    return p.inBody(token);
                },
                .base, .basefont, .bgsound, .link => {
                    hit(.in_head, "start base, basefont, bgsound, or link");
                    _ = try p.insertTagElement(tag);
                    p.popCurrent();
                    tag.acknowledge();
                    return .handled;
                },
                .meta => {
                    hit(.in_head, "start meta");
                    _ = try p.insertTagElement(tag);
                    p.popCurrent();
                    tag.acknowledge();
                    // The encoding steps apply only while the confidence is tentative, which it never is here.
                    return .handled;
                },
                .title => {
                    hit(.in_head, "start title");
                    try p.parseTextElement(tag, .rcdata);
                    return .handled;
                },
                .noscript, .noframes, .style => if (tag.tag != .noscript or p.scripting != .disabled) {
                    hit(.in_head, "start noscript when scripting is not Disabled, noframes, or style");
                    try p.parseTextElement(tag, .rawtext);
                    return .handled;
                } else {
                    hit(.in_head, "start noscript when scripting is Disabled");
                    _ = try p.insertTagElement(tag);
                    p.mode = .in_head_noscript;
                    return .handled;
                },
                .script => {
                    hit(.in_head, "start script");
                    try p.insertScript(tag);
                    return .handled;
                },
                .template => {
                    hit(.in_head, "start template");
                    return .{ .outcome = p.unsupported(.template_start_tag, p.token_start.offset) };
                },
                .head => {
                    hit(.in_head, "start head or other end tag");
                    try p.parseError();
                    return .handled;
                },
                else => {},
            },
            .end_tag => |tag| switch (tag.tag) {
                .head => {
                    hit(.in_head, "end head");
                    p.popCurrent();
                    p.mode = .after_head;
                    return .handled;
                },
                .body, .html, .br => hit(.in_head, "end body, html, or br"),
                .template => {
                    hit(.in_head, "end template");
                    // The parser never puts a template element on the stack, so this is always the parse error.
                    std.debug.assert(!p.hasTemplate());
                    try p.parseError();
                    return .handled;
                },
                else => {
                    hit(.in_head, "start head or other end tag");
                    try p.parseError();
                    return .handled;
                },
            },
            .end_of_file => {},
        }
        hit(.in_head, "else");
        p.inHeadAnythingElse();
        return .reprocess;
    }

    /// The in head `script` start tag entry (146251 to 146309). The scripting mode is never Inert or Fragment, and the
    /// parser is never invoked through `document.write()`.
    fn insertScript(p: *Parser, tag: *const TagToken) Error!void {
        try p.scripts.ensureUnusedCapacity(p.gpa, 1);
        try p.stack.ensureUnusedCapacity(p.gpa, 1);
        const target = p.currentNode().node;
        const element = try p.createElementForToken(tag.name, tag.attributes, target);
        p.retain(element);
        p.scripts.putAssumeCapacityNoClobber(element, .{ .parser_document = p.document_node, .force_async = false, .already_started = false });
        try p.insertAtLocation(element, target);
        p.retain(element);
        p.stack.appendAssumeCapacity(.{ .node = element, .tag = .script });
        try p.switchTokenizer(.script_data);
        p.original_mode = p.mode;
        p.mode = .text;
    }

    /// 13.2.6.4.5, the in head noscript insertion mode.
    fn inHeadNoscript(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .doctype => {
                hit(.in_head_noscript, "DOCTYPE");
                try p.parseError();
                return .handled;
            },
            .comment, .processing_instruction => {
                hit(.in_head_noscript, "whitespace, comment, processing instruction, or start basefont, bgsound, link, meta, noframes, or style");
                return p.inHead(token);
            },
            .start_tag => |tag| switch (tag.tag) {
                .html => {
                    hit(.in_head_noscript, "start html");
                    return p.inBody(token);
                },
                .basefont, .bgsound, .link, .meta, .noframes, .style => {
                    hit(.in_head_noscript, "whitespace, comment, processing instruction, or start basefont, bgsound, link, meta, noframes, or style");
                    return p.inHead(token);
                },
                .head, .noscript => {
                    hit(.in_head_noscript, "start head or noscript, or other end tag");
                    try p.parseError();
                    return .handled;
                },
                else => {},
            },
            .end_tag => |tag| switch (tag.tag) {
                .noscript => {
                    hit(.in_head_noscript, "end noscript");
                    p.popCurrent();
                    p.mode = .in_head;
                    return .handled;
                },
                .br => hit(.in_head_noscript, "end br"),
                else => {
                    hit(.in_head_noscript, "start head or noscript, or other end tag");
                    try p.parseError();
                    return .handled;
                },
            },
            .end_of_file => {},
        }
        hit(.in_head_noscript, "else");
        try p.parseError();
        p.inHeadNoscriptAnythingElse();
        return .reprocess;
    }

    /// 13.2.6.4.6, the after head insertion mode.
    fn afterHead(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .comment => |data| {
                hit(.after_head, "comment");
                try p.insertComment(data, null);
                return .handled;
            },
            .processing_instruction => |instruction| {
                hit(.after_head, "processing instruction");
                try p.insertProcessingInstruction(instruction, null);
                return .handled;
            },
            .doctype => {
                hit(.after_head, "DOCTYPE");
                try p.parseError();
                return .handled;
            },
            .start_tag => |tag| switch (tag.tag) {
                .html => {
                    hit(.after_head, "start html");
                    return p.inBody(token);
                },
                .body => {
                    hit(.after_head, "start body");
                    _ = try p.insertTagElement(tag);
                    p.frameset_ok = false;
                    p.mode = .in_body;
                    return .handled;
                },
                .frameset => {
                    hit(.after_head, "start frameset");
                    _ = try p.insertTagElement(tag);
                    p.mode = .in_frameset;
                    return .handled;
                },
                .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title => {
                    hit(.after_head, "start base, basefont, bgsound, link, meta, noframes, script, style, template, or title");
                    try p.parseError();
                    // The head element pointer is never null here.
                    const head = p.head.?;
                    try p.pushElement(.{ .node = head, .tag = .head });
                    const flow = try p.inHead(token);
                    if (flow == .outcome) return flow;
                    // The head element might not be the current node.
                    p.removeFromStack(p.stackIndex(head).?);
                    return flow;
                },
                .head => {
                    hit(.after_head, "start head or other end tag");
                    try p.parseError();
                    return .handled;
                },
                else => {},
            },
            .end_tag => |tag| switch (tag.tag) {
                .template => {
                    hit(.after_head, "end template");
                    return p.inHead(token);
                },
                .body, .html, .br => hit(.after_head, "end body, html, or br"),
                else => {
                    hit(.after_head, "start head or other end tag");
                    try p.parseError();
                    return .handled;
                },
            },
            .end_of_file => {},
        }
        hit(.after_head, "else");
        try p.afterHeadAnythingElse();
        return .reprocess;
    }

    /// Adds each attribute of `tag` that `element` lacks, as the in body `html` and `body` start tag entries do.
    fn addMissingAttributes(p: *Parser, element: NodeHandle, tag: *const TagToken) Error!void {
        for (tag.attributes) |attribute| {
            const present = p.store.attribute(element, null, attribute.name) catch unreachable;
            if (present == null) p.store.setAttribute(element, null, attribute.name, attribute.value) catch |err| return storeError(err);
        }
    }

    /// 13.2.6.4.7, the in body insertion mode, for every token other than characters.
    fn inBody(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .comment => |data| {
                hit(.in_body, "comment");
                try p.insertComment(data, null);
            },
            .processing_instruction => |instruction| {
                hit(.in_body, "processing instruction");
                try p.insertProcessingInstruction(instruction, null);
            },
            .doctype => {
                hit(.in_body, "DOCTYPE");
                try p.parseError();
            },
            .start_tag => |tag| return p.inBodyStartTag(token, tag),
            .end_tag => |tag| return p.inBodyEndTag(token, tag),
            .end_of_file => {
                hit(.in_body, "EOF");
                // The stack of template insertion modes is always empty.
                if (p.hasUnclosableNode()) try p.parseError();
                return p.stopParsing();
            },
        }
        return .handled;
    }

    fn inBodyStartTag(p: *Parser, token: Token, tag: *TagToken) Error!Flow {
        switch (tag.tag) {
            .html => {
                hit(.in_body, "start html");
                try p.parseError();
                if (!p.hasTemplate()) try p.addMissingAttributes(p.stack.items[0].node, tag);
            },
            .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title => {
                hit(.in_body, "start base, basefont, bgsound, link, meta, noframes, script, style, template, or title, or end template");
                return p.inHead(token);
            },
            .body => {
                hit(.in_body, "start body");
                try p.parseError();
                const stack = p.stack.items;
                if (stack.len == 1 or stack[1].tag != .body or p.hasTemplate()) return .handled;
                p.frameset_ok = false;
                try p.addMissingAttributes(stack[1].node, tag);
            },
            .frameset => {
                hit(.in_body, "start frameset");
                try p.parseError();
                const stack = p.stack.items;
                if (stack.len == 1 or stack[1].tag != .body) return .handled;
                if (!p.frameset_ok) return .handled;
                const body = stack[1].node;
                if (p.parentOf(body)) |parent| p.store.removeChild(parent, body) catch unreachable;
                while (p.stack.items.len > 1) p.popCurrent();
                _ = try p.insertTagElement(tag);
                p.mode = .in_frameset;
            },
            .address, .article, .aside, .blockquote, .center, .details, .dialog, .dir, .div, .dl, .fieldset, .figcaption, .figure, .footer, .header, .hgroup, .main, .menu, .nav, .ol, .p, .search, .section, .summary, .ul => {
                hit(.in_body, "start address group");
                try p.closePInButtonScope();
                _ = try p.insertTagElement(tag);
            },
            .h1, .h2, .h3, .h4, .h5, .h6 => {
                hit(.in_body, "start h1 to h6");
                try p.closePInButtonScope();
                if (isHeading(p.currentNode().tag)) {
                    try p.parseError();
                    p.popCurrent();
                }
                _ = try p.insertTagElement(tag);
            },
            .pre, .listing => {
                hit(.in_body, "start pre or listing");
                try p.closePInButtonScope();
                _ = try p.insertTagElement(tag);
                p.ignore_line_feed = true;
                p.frameset_ok = false;
            },
            .form => {
                hit(.in_body, "start form");
                if (p.form != null and !p.hasTemplate()) {
                    try p.parseError();
                    return .handled;
                }
                try p.closePInButtonScope();
                const element = try p.insertTagElement(tag);
                if (!p.hasTemplate()) {
                    p.retain(element);
                    p.form = element;
                }
            },
            .li => {
                hit(.in_body, "start li");
                try p.startListItem(tag, &.{.li});
            },
            .dd, .dt => {
                hit(.in_body, "start dd or dt");
                try p.startListItem(tag, &.{ .dd, .dt });
            },
            .plaintext => {
                hit(.in_body, "start plaintext");
                try p.closePInButtonScope();
                _ = try p.insertTagElement(tag);
                try p.switchTokenizer(.plaintext);
            },
            .button => {
                hit(.in_body, "start button");
                if (p.hasInScope(.button, .default)) {
                    try p.parseError();
                    p.generateImpliedEndTags(null);
                    p.popUntilTag(.button);
                }
                try p.reconstructFormatting();
                _ = try p.insertTagElement(tag);
                p.frameset_ok = false;
            },
            .a => {
                hit(.in_body, "start a");
                if (p.lastFormattingAfterMarker(.a)) |index| {
                    try p.parseError();
                    const element = p.formatting.items[index].element.node;
                    if (try p.adoptionAgency(.a)) try p.anyOtherEndTag(tag);
                    if (p.formattingIndex(element)) |remaining| p.removeFormattingAt(remaining);
                    if (p.stackIndex(element)) |remaining| p.removeFromStack(remaining);
                }
                try p.reconstructFormatting();
                try p.pushFormatting(try p.insertTagElement(tag), tag);
            },
            .b, .big, .code, .em, .font, .i, .s, .small, .strike, .strong, .tt, .u => {
                hit(.in_body, "start b group");
                try p.reconstructFormatting();
                try p.pushFormatting(try p.insertTagElement(tag), tag);
            },
            .nobr => {
                hit(.in_body, "start nobr");
                try p.reconstructFormatting();
                if (p.hasInScope(.nobr, .default)) {
                    try p.parseError();
                    if (try p.adoptionAgency(.nobr)) try p.anyOtherEndTag(tag);
                    try p.reconstructFormatting();
                }
                try p.pushFormatting(try p.insertTagElement(tag), tag);
            },
            .applet, .marquee, .object => {
                hit(.in_body, "start applet, marquee, or object");
                try p.reconstructFormatting();
                _ = try p.insertTagElement(tag);
                try p.insertMarker();
                p.frameset_ok = false;
            },
            .table => {
                hit(.in_body, "start table");
                const quirks = (p.store.documentMode(p.document_node) catch unreachable) == .quirks;
                if (!quirks) try p.closePInButtonScope();
                _ = try p.insertTagElement(tag);
                p.frameset_ok = false;
                p.mode = .in_table;
            },
            .area, .br, .embed, .img, .keygen, .wbr => try p.startVoidFormatting(tag),
            .input => {
                hit(.in_body, "start input");
                // The fragment context element is always null.
                if (p.hasInScope(.select, .default)) {
                    try p.parseError();
                    p.popUntilTag(.select);
                }
                try p.reconstructFormatting();
                _ = try p.insertTagElement(tag);
                p.popCurrent();
                tag.acknowledge();
                const hidden = for (tag.attributes) |attribute| {
                    if (equalAscii(attribute.name.units, "type")) break equalIgnoringCase(attribute.value.units, "hidden");
                } else false;
                if (!hidden) p.frameset_ok = false;
            },
            .param, .source, .track => {
                hit(.in_body, "start param, source, or track");
                _ = try p.insertTagElement(tag);
                p.popCurrent();
                tag.acknowledge();
            },
            .hr => {
                hit(.in_body, "start hr");
                try p.closePInButtonScope();
                if (p.hasInScope(.select, .default)) {
                    p.generateImpliedEndTags(null);
                    if (p.hasInScope(.option, .default) or p.hasInScope(.optgroup, .default)) try p.parseError();
                }
                _ = try p.insertTagElement(tag);
                p.popCurrent();
                tag.acknowledge();
                p.frameset_ok = false;
            },
            .image => {
                hit(.in_body, "start image");
                try p.parseError();
                tag.name = ascii("img");
                tag.tag = .img;
                return .reprocess;
            },
            .textarea => {
                hit(.in_body, "start textarea");
                _ = try p.insertTagElement(tag);
                p.ignore_line_feed = true;
                try p.switchTokenizer(.rcdata);
                p.original_mode = p.mode;
                p.frameset_ok = false;
                p.mode = .text;
            },
            .xmp => {
                hit(.in_body, "start xmp");
                try p.closePInButtonScope();
                try p.reconstructFormatting();
                p.frameset_ok = false;
                try p.parseTextElement(tag, .rawtext);
            },
            .iframe => {
                hit(.in_body, "start iframe");
                p.frameset_ok = false;
                try p.parseTextElement(tag, .rawtext);
            },
            .noembed => {
                hit(.in_body, "start noembed, or noscript when scripting is not Disabled");
                try p.parseTextElement(tag, .rawtext);
            },
            .noscript => if (p.scripting != .disabled) {
                hit(.in_body, "start noembed, or noscript when scripting is not Disabled");
                try p.parseTextElement(tag, .rawtext);
            } else try p.anyOtherStartTag(tag),
            .select => {
                hit(.in_body, "start select");
                // The fragment context element is always null.
                if (p.hasInScope(.select, .default)) {
                    try p.parseError();
                    p.popUntilTag(.select);
                } else {
                    try p.reconstructFormatting();
                    _ = try p.insertTagElement(tag);
                    p.frameset_ok = false;
                }
            },
            .option => {
                hit(.in_body, "start option");
                if (p.hasInScope(.select, .default)) {
                    p.generateImpliedEndTags(.optgroup);
                    if (p.hasInScope(.option, .default)) try p.parseError();
                } else if (p.currentIs(.option)) {
                    p.popCurrent();
                }
                try p.reconstructFormatting();
                _ = try p.insertTagElement(tag);
            },
            .optgroup => {
                hit(.in_body, "start optgroup");
                if (p.hasInScope(.select, .default)) {
                    p.generateImpliedEndTags(null);
                    if (p.hasInScope(.option, .default) or p.hasInScope(.optgroup, .default)) try p.parseError();
                } else if (p.currentIs(.option)) {
                    p.popCurrent();
                }
                try p.reconstructFormatting();
                _ = try p.insertTagElement(tag);
            },
            .rb, .rtc => {
                hit(.in_body, "start rb or rtc");
                if (p.hasInScope(.ruby, .default)) p.generateImpliedEndTags(null);
                if (!p.currentIs(.ruby)) try p.parseError();
                _ = try p.insertTagElement(tag);
            },
            .rp, .rt => {
                hit(.in_body, "start rp or rt");
                if (p.hasInScope(.ruby, .default)) p.generateImpliedEndTags(.rtc);
                if (!p.currentIs(.rtc) and !p.currentIs(.ruby)) try p.parseError();
                _ = try p.insertTagElement(tag);
            },
            .math => {
                hit(.in_body, "start math");
                return .{ .outcome = p.unsupported(.foreign_start_tag, p.token_start.offset) };
            },
            .svg => {
                hit(.in_body, "start svg");
                return .{ .outcome = p.unsupported(.foreign_start_tag, p.token_start.offset) };
            },
            .caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr => {
                hit(.in_body, "start caption, col, colgroup, frame, head, tbody, td, tfoot, th, thead, or tr");
                try p.parseError();
            },
            else => try p.anyOtherStartTag(tag),
        }
        return .handled;
    }

    /// The in body entry for `area`, `br`, `embed`, `img`, `keygen`, and `wbr` start tags.
    fn startVoidFormatting(p: *Parser, tag: *TagToken) Error!void {
        hit(.in_body, "start area, br, embed, img, keygen, or wbr");
        try p.reconstructFormatting();
        _ = try p.insertTagElement(tag);
        p.popCurrent();
        tag.acknowledge();
        p.frameset_ok = false;
    }

    fn anyOtherStartTag(p: *Parser, tag: *const TagToken) Error!void {
        hit(.in_body, "other start tag");
        try p.reconstructFormatting();
        _ = try p.insertTagElement(tag);
    }

    /// The in body `li`, `dd`, and `dt` start tag entries (147038 to 147155). `closes` lists the elements that the
    /// token closes: `li` for `li`, and `dd` and `dt` for either of them.
    fn startListItem(p: *Parser, tag: *const TagToken, comptime closes: []const Tag) Error!void {
        p.frameset_ok = false;
        var index = p.stack.items.len;
        while (index > 0) {
            index -= 1;
            const node = p.stack.items[index].tag;
            if (std.mem.indexOfScalar(Tag, closes, node) != null) {
                p.generateImpliedEndTags(node);
                if (!p.currentIs(node)) try p.parseError();
                p.popUntilTag(node);
                break;
            }
            if (isSpecial(node) and node != .address and node != .div and node != .p) break;
        }
        try p.closePInButtonScope();
        _ = try p.insertTagElement(tag);
    }

    fn inBodyEndTag(p: *Parser, token: Token, tag: *TagToken) Error!Flow {
        switch (tag.tag) {
            .template => {
                hit(.in_body, "start base, basefont, bgsound, link, meta, noframes, script, style, template, or title, or end template");
                return p.inHead(token);
            },
            .body => {
                hit(.in_body, "end body");
                if (!p.hasInScope(.body, .default)) {
                    try p.parseError();
                    return .handled;
                }
                if (p.hasUnclosableNode()) try p.parseError();
                p.mode = .after_body;
            },
            .html => {
                hit(.in_body, "end html");
                if (!p.hasInScope(.body, .default)) {
                    try p.parseError();
                    return .handled;
                }
                if (p.hasUnclosableNode()) try p.parseError();
                p.mode = .after_body;
                return .reprocess;
            },
            .address, .article, .aside, .blockquote, .button, .center, .details, .dialog, .dir, .div, .dl, .fieldset, .figcaption, .figure, .footer, .header, .hgroup, .listing, .main, .menu, .nav, .ol, .pre, .search, .section, .select, .summary, .ul => {
                hit(.in_body, "end address group");
                try p.closeElementInScope(tag.tag, null);
            },
            .form => {
                hit(.in_body, "end form");
                // The parser is never parsing template contents.
                const node = p.form;
                p.form = null;
                defer if (node) |form| p.release(form);
                if (node == null or !p.hasNodeInScope(node.?, .default)) {
                    try p.parseError();
                    return .handled;
                }
                p.generateImpliedEndTags(null);
                if (!std.meta.eql(p.currentNode().node, node.?)) try p.parseError();
                p.removeFromStack(p.stackIndex(node.?).?);
            },
            .p => {
                hit(.in_body, "end p");
                if (!p.hasInScope(.p, .button)) {
                    try p.parseError();
                    _ = try p.insertImpliedElement(.p);
                }
                try p.closeP();
            },
            .li => {
                hit(.in_body, "end li");
                if (!p.hasInScope(.li, .list_item)) {
                    try p.parseError();
                    return .handled;
                }
                p.generateImpliedEndTags(.li);
                if (!p.currentIs(.li)) try p.parseError();
                p.popUntilTag(.li);
            },
            .dd, .dt => {
                hit(.in_body, "end dd or dt");
                try p.closeElementInScope(tag.tag, tag.tag);
            },
            .h1, .h2, .h3, .h4, .h5, .h6 => {
                hit(.in_body, "end h1 to h6");
                if (!p.hasHeadingInScope()) {
                    try p.parseError();
                    return .handled;
                }
                p.generateImpliedEndTags(null);
                if (!p.currentIs(tag.tag)) try p.parseError();
                while (true) {
                    const popped = p.currentNode().tag;
                    p.popCurrent();
                    if (isHeading(popped)) break;
                }
            },
            .sarcasm => {
                hit(.in_body, "end sarcasm");
                // Take a deep breath, then act as described in the any other end tag entry.
                try p.anyOtherEndTag(tag);
            },
            .a, .b, .big, .code, .em, .font, .i, .nobr, .s, .small, .strike, .strong, .tt, .u => {
                hit(.in_body, "end formatting group");
                if (try p.adoptionAgency(tag.tag)) try p.anyOtherEndTag(tag);
            },
            .applet, .marquee, .object => {
                hit(.in_body, "end applet, marquee, or object");
                if (!p.hasInScope(tag.tag, .default)) {
                    try p.parseError();
                    return .handled;
                }
                p.generateImpliedEndTags(null);
                if (!p.currentIs(tag.tag)) try p.parseError();
                p.popUntilTag(tag.tag);
                p.clearFormattingToMarker();
            },
            .br => {
                hit(.in_body, "end br");
                try p.parseError();
                // Act as a `br` start tag token with no attributes.
                var start_br: TagToken = .{ .name = ascii("br"), .tag = .br, .attributes = &.{}, .self_closing = false };
                try p.startVoidFormatting(&start_br);
            },
            else => try p.anyOtherEndTag(tag),
        }
        return .handled;
    }

    /// The in body end tag entries that close an element in scope: if no `tag` element is in scope, a parse error;
    /// otherwise generate implied end tags except `except`, check the current node, and pop until a `tag` element pops.
    fn closeElementInScope(p: *Parser, tag: Tag, except: ?Tag) Error!void {
        if (!p.hasInScope(tag, .default)) return p.parseError();
        p.generateImpliedEndTags(except);
        if (!p.currentIs(tag)) try p.parseError();
        p.popUntilTag(tag);
    }

    /// The in body any other end tag entry (147798 to 147829).
    fn anyOtherEndTag(p: *Parser, tag: *const TagToken) Error!void {
        hit(.in_body, "other end tag");
        var index = p.stack.items.len;
        while (index > 0) {
            index -= 1;
            const node = p.stack.items[index];
            if (p.isNamed(node, tag.tag, tag.name)) {
                p.generateImpliedEndTags(if (tag.tag == .other) null else tag.tag);
                if (index != p.stack.items.len - 1) try p.parseError();
                while (p.stack.items.len > index) p.popCurrent();
                return;
            }
            if (isSpecial(node.tag)) return p.parseError();
        }
    }

    /// The adoption agency algorithm (147849 to 148025) for a token whose tag name is `subject`, which is a formatting
    /// element name. Returns true when the caller must act as the any other end tag entry.
    fn adoptionAgency(p: *Parser, subject: Tag) Error!bool {
        const current = p.currentNode();
        if (current.tag == subject and p.formattingIndex(current.node) == null) {
            p.popCurrent();
            return false;
        }
        var outer_loop_counter: usize = 0;
        while (true) {
            if (outer_loop_counter >= 8) return false;
            outer_loop_counter += 1;
            const formatting_index = p.lastFormattingAfterMarker(subject) orelse return true;
            const formatting_element = p.formatting.items[formatting_index].element.node;
            const formatting_stack_index = p.stackIndex(formatting_element) orelse {
                try p.parseError();
                p.removeFormattingAt(formatting_index);
                return false;
            };
            if (!p.hasNodeInScope(formatting_element, .default)) {
                try p.parseError();
                return false;
            }
            if (formatting_stack_index != p.stack.items.len - 1) try p.parseError();
            const furthest_index = for (p.stack.items[formatting_stack_index + 1 ..], formatting_stack_index + 1..) |entry, index| {
                if (isSpecial(entry.tag)) break index;
            } else {
                while (p.stack.items.len > formatting_stack_index) p.popCurrent();
                p.removeFormattingAt(formatting_index);
                return false;
            };
            const furthest_block = p.stack.items[furthest_index].node;
            const common_ancestor = p.stack.items[formatting_stack_index - 1].node;
            var bookmark: Bookmark = .formatting_element;
            var node_index = furthest_index;
            var last_node = furthest_block;
            var inner_loop_counter: usize = 0;
            while (true) {
                inner_loop_counter += 1;
                // The element above node, which is at the same index even after node is removed.
                node_index -= 1;
                const node = p.stack.items[node_index].node;
                if (std.meta.eql(node, formatting_element)) break;
                var list_index = p.formattingIndex(node);
                if (inner_loop_counter > 3 and list_index != null) {
                    p.removeFormattingAt(list_index.?);
                    list_index = null;
                }
                const entry_index = list_index orelse {
                    p.removeFromStack(node_index);
                    continue;
                };
                const entry = &p.formatting.items[entry_index].element;
                const element = try p.createElementForToken(p.localName(node), entry.attributes.list, common_ancestor);
                p.retain(element);
                p.retain(element);
                p.release(entry.node);
                p.release(node);
                entry.node = element;
                p.stack.items[node_index].node = element;
                if (std.meta.eql(last_node, furthest_block)) bookmark = .{ .after = element };
                try p.append(element, last_node);
                last_node = element;
            }
            // The adjusted insertion location given (commonAncestor, null) is (commonAncestor, null).
            const target = common_ancestor;
            if (p.parentOf(last_node)) |parent| p.store.removeChild(parent, last_node) catch unreachable;
            if (p.parentOf(last_node) == null and !p.isInclusiveAncestor(last_node, target) and
                (p.kindOf(target) != .document or !p.hasElementChild(target)))
            {
                try p.append(target, last_node);
            }
            const formatting_entry_index = p.formattingIndex(formatting_element).?;
            const formatting_entry = p.formatting.items[formatting_entry_index].element;
            const new_element = try p.createElementForToken(p.localName(formatting_element), formatting_entry.attributes.list, furthest_block);
            while (p.store.firstChild(furthest_block) catch unreachable) |child| try p.append(new_element, child);
            try p.append(furthest_block, new_element);
            // Replace the formatting element in the list, at the bookmark, with the new element.
            p.retain(new_element);
            switch (bookmark) {
                .formatting_element => p.formatting.items[formatting_entry_index].element.node = new_element,
                .after => |previous| {
                    _ = p.formatting.orderedRemove(formatting_entry_index);
                    const position = p.formattingIndex(previous).? + 1;
                    p.formatting.insertAssumeCapacity(position, .{ .element = .{
                        .node = new_element,
                        .tag = formatting_entry.tag,
                        .attributes = formatting_entry.attributes,
                    } });
                },
            }
            p.release(formatting_element);
            // Replace the formatting element in the stack with the new element, immediately below the furthest block.
            p.removeFromStack(p.stackIndex(formatting_element).?);
            const below = p.stackIndex(furthest_block).? + 1;
            p.retain(new_element);
            p.stack.insertAssumeCapacity(below, .{ .node = new_element, .tag = formatting_entry.tag });
        }
    }

    /// 13.2.6.4.8, the text insertion mode, for every token other than characters.
    fn text(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .end_of_file => {
                hit(.text, "EOF");
                try p.parseError();
                const current = p.currentNode();
                if (current.tag == .script) {
                    if (p.scripts.getPtr(current.node)) |state| state.already_started = true;
                }
                p.popCurrent();
                p.mode = p.original_mode;
                return .reprocess;
            },
            .end_tag => |tag| if (tag.tag == .script) {
                hit(.text, "end script");
                const script = p.currentNode().node;
                p.popCurrent();
                p.mode = p.original_mode;
                // The tokenizer has consumed exactly the end tag's end, so the next run continues after it.
                return .{ .outcome = .{ .script = .{ .element = script, .offset = p.token_end.offset } } };
            } else {
                hit(.text, "other end tag");
                p.popCurrent();
                p.mode = p.original_mode;
                return .handled;
            },
            // The tokenizer is in a text state, so it emits only characters, end tags, and the end-of-file token.
            .doctype, .start_tag, .comment, .processing_instruction => unreachable,
        }
    }

    /// 13.2.6.4.17, the after body insertion mode.
    fn afterBody(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .comment => |data| {
                hit(.after_body, "comment");
                try p.insertComment(data, p.stack.items[0].node);
                return .handled;
            },
            .processing_instruction => |instruction| {
                hit(.after_body, "processing instruction");
                try p.insertProcessingInstruction(instruction, p.stack.items[0].node);
                return .handled;
            },
            .doctype => {
                hit(.after_body, "DOCTYPE");
                try p.parseError();
                return .handled;
            },
            .start_tag => |tag| if (tag.tag == .html) {
                hit(.after_body, "start html");
                return p.inBody(token);
            },
            .end_tag => |tag| if (tag.tag == .html) {
                hit(.after_body, "end html");
                // The fragment context element is always null.
                p.mode = .after_after_body;
                return .handled;
            },
            .end_of_file => {
                hit(.after_body, "EOF");
                return p.stopParsing();
            },
        }
        hit(.after_body, "else");
        try p.parseError();
        p.mode = .in_body;
        return .reprocess;
    }

    /// 13.2.6.4.20, the after after body insertion mode.
    fn afterAfterBody(p: *Parser, token: Token) Error!Flow {
        switch (token) {
            .comment => |data| {
                hit(.after_after_body, "comment");
                try p.insertComment(data, p.document_node);
                return .handled;
            },
            .processing_instruction => |instruction| {
                hit(.after_after_body, "processing instruction");
                try p.insertProcessingInstruction(instruction, p.document_node);
                return .handled;
            },
            .doctype => {
                hit(.after_after_body, "DOCTYPE, whitespace, or start html");
                return p.inBody(token);
            },
            .start_tag => |tag| if (tag.tag == .html) {
                hit(.after_after_body, "DOCTYPE, whitespace, or start html");
                return p.inBody(token);
            },
            .end_of_file => {
                hit(.after_after_body, "EOF");
                return p.stopParsing();
            },
            .end_tag => {},
        }
        hit(.after_after_body, "else");
        try p.parseError();
        p.mode = .in_body;
        return .reprocess;
    }
};
