//! The FP-0082 script parser over UTF-16 code units.
//!
//! `parseScript` parses source text with the Script goal (16.1) over the frozen subset of the
//! FP-0082 contract. A `syntax-error` outcome asserts that ParseText(source, Script) under ECMA-262
//! with Annex B returns a list of errors. Wherever the full grammar admits a production outside the
//! subset, or the parser cannot decide whether a construct is valid, the outcome is `unsupported`.
//!
//! The outcome is the first diagnostic in detection order. Token-level and grammar diagnostics and
//! unsupported productions are detected at their token, in source order. Early errors that need a
//! complete production are detected when it completes. A Use Strict Directive in a function body
//! applies the strict checks to earlier directives, the function's name, and its parameters when the
//! directive statement completes. `arguments_object` is detected when the function body completes.
//!
//! The grammar procedures do not recurse on the native stack. Each one keeps its state in a frame
//! of a heap stack and resumes when a nested procedure returns, so native stack use does not grow
//! with the depth of the source (contract amendment 1). Every step into a child node first checks
//! the node depth against `Options.max_depth`, and the frames count against `max_memory_bytes`.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const number = @import("number.zig");
const web_string = @import("../web_string.zig");
const Allocator = std.mem.Allocator;
const Token = lexer.Token;
const Tag = lexer.Tag;
const Expression = ast.Expression;
const Statement = ast.Statement;
const Name = ast.Name;
const eqlAscii = lexer.eqlAscii;

pub const Options = struct {
    max_depth: u32 = 1024,
    max_memory_bytes: usize = 256 * 1024 * 1024,
    max_source_units: u32 = std.math.maxInt(u32),
};

pub const UnsupportedCode = enum {
    lexical_declaration,
    block_function_declaration,
    using_declaration,
    array_literal,
    arguments_object,
    for_in,
    for_of,
    spread,
    object_spread,
    destructuring_binding,
    destructuring_assignment,
    default_parameter,
    rest_parameter,
    method_definition,
    class,
    super,
    new_target,
    arrow_function,
    template,
    optional_chain,
    coalesce,
    logical_assignment,
    generator,
    async_function,
    for_await,
    import,
    regular_expression,
    bigint_literal,
    non_ascii_identifier,
    with,
};

pub const SyntaxErrorCode = enum {
    unexpected_token,
    unexpected_end,
    invalid_character,
    unterminated_string,
    unterminated_comment,
    invalid_escape,
    invalid_numeric_literal,
    strict_octal,
    strict_octal_escape,
    reserved_word,
    strict_reserved_word,
    strict_eval_arguments,
    invalid_assignment_target,
    strict_delete_identifier,
    strict_with,
    function_declaration_position,
    duplicate_label,
    undefined_break_target,
    undefined_continue_target,
    break_outside,
    continue_outside,
    return_outside_function,
    duplicate_parameter,
    duplicate_proto,
    cover_initialized_name,
    unary_before_exponent,
    private_identifier,
    throw_line_terminator,
};

pub const LimitCode = enum { depth, memory, source_length };

/// The unsupported code table: each code's ECMA-262 sections and the plan task that owns it.
const unsupported_table = [_]struct { UnsupportedCode, []const u8, []const u8 }{
    .{ .lexical_declaration, "14.3.1", "FP-0086" },
    .{ .block_function_declaration, "14.2,14.12,B.3.1,B.3.2,B.3.3", "FP-0086" },
    .{ .using_declaration, "14.3.1", "FP-0097" },
    .{ .array_literal, "13.2.4", "FP-0087" },
    .{ .arguments_object, "10.2.11,10.4.4", "FP-0087" },
    .{ .for_in, "14.7.5,B.3.5", "FP-0087" },
    .{ .for_of, "14.7.5", "FP-0088" },
    .{ .spread, "13.3.8", "FP-0088" },
    .{ .object_spread, "13.2.5", "FP-0088" },
    .{ .destructuring_binding, "14.3.3", "FP-0088" },
    .{ .destructuring_assignment, "13.15.5", "FP-0088" },
    .{ .default_parameter, "15.1", "FP-0088" },
    .{ .rest_parameter, "15.1", "FP-0088" },
    .{ .method_definition, "15.4", "FP-0089" },
    .{ .class, "15.7", "FP-0089" },
    .{ .super, "13.3.7", "FP-0089" },
    .{ .new_target, "13.3.12", "FP-0089" },
    .{ .arrow_function, "15.3", "FP-0090" },
    .{ .template, "12.9.6,13.2.8,13.3.11", "FP-0090" },
    .{ .optional_chain, "13.3.9", "FP-0090" },
    .{ .coalesce, "13.13", "FP-0090" },
    .{ .logical_assignment, "13.15", "FP-0090" },
    .{ .generator, "15.5,15.6", "FP-0091" },
    .{ .async_function, "15.8,15.9", "FP-0091" },
    .{ .for_await, "14.7.5", "FP-0091" },
    .{ .import, "16.2.2,13.3.10,13.3.12", "FP-0092" },
    .{ .regular_expression, "12.9.5,13.2.7", "FP-0093" },
    .{ .bigint_literal, "12.9.3", "FP-0094" },
    .{ .non_ascii_identifier, "12.7.1", "FP-0095" },
    .{ .with, "14.11", "FP-0096" },
};

/// The syntax-error code table: each code's ECMA-262 sections.
const syntax_error_table = [_]struct { SyntaxErrorCode, []const u8 }{
    .{ .unexpected_token, "5.1.4,12.10" },
    .{ .unexpected_end, "5.1.4,12.10" },
    .{ .invalid_character, "12.6" },
    .{ .unterminated_string, "12.9.4" },
    .{ .unterminated_comment, "12.4" },
    .{ .invalid_escape, "12.9.4,12.7.1.1" },
    .{ .invalid_numeric_literal, "12.9.3" },
    .{ .strict_octal, "12.9.3.1" },
    .{ .strict_octal_escape, "12.9.4.1" },
    .{ .reserved_word, "13.1.1,12.7.2" },
    .{ .strict_reserved_word, "13.1.1" },
    .{ .strict_eval_arguments, "13.1.1,8.6.4,15.2.1" },
    .{ .invalid_assignment_target, "13.15.1,13.4.1,8.6.4" },
    .{ .strict_delete_identifier, "13.5.1.1" },
    .{ .strict_with, "14.11.1" },
    .{ .function_declaration_position, "14.6.1,14.7.2.1,14.7.3.1,14.7.4.1,14.13.1" },
    .{ .duplicate_label, "8.3.1,15.2.1,16.1.1" },
    .{ .undefined_break_target, "8.3.2,15.2.1,16.1.1" },
    .{ .undefined_continue_target, "8.3.3,15.2.1,16.1.1" },
    .{ .break_outside, "14.9.1" },
    .{ .continue_outside, "14.8.1" },
    .{ .return_outside_function, "14.10,16.1" },
    .{ .duplicate_parameter, "15.1.1,15.2.1" },
    .{ .duplicate_proto, "13.2.5.1" },
    .{ .cover_initialized_name, "13.2.5.1" },
    .{ .unary_before_exponent, "13.6" },
    .{ .private_identifier, "16.1.1" },
    .{ .throw_line_terminator, "14.14,12.10" },
};

comptime {
    // Each table lists every code once, in the order of its enum.
    std.debug.assert(unsupported_table.len == std.enums.values(UnsupportedCode).len);
    for (unsupported_table, 0..) |row, index| std.debug.assert(@backingInt(row[0]) == index);
    std.debug.assert(syntax_error_table.len == std.enums.values(SyntaxErrorCode).len);
    for (syntax_error_table, 0..) |row, index| std.debug.assert(@backingInt(row[0]) == index);
}

pub const Diagnostic = union(enum) {
    syntax_error: struct { code: SyntaxErrorCode, offset: u32 },
    unsupported: struct { code: UnsupportedCode, offset: u32 },
    limit: struct { code: LimitCode, offset: u32 },
};

pub const Parse = struct {
    arena: std.heap.ArenaAllocator,
    outcome: union(enum) { script: *const ast.Script, diagnostic: Diagnostic },
    /// The number of levels of the script's tree, which is the number of frames that `writeOutcome` needs.
    height: u32 = 0,

    pub fn deinit(parse: *Parse) void {
        parse.arena.deinit();
        parse.* = undefined;
    }
};

pub const WriteError = std.Io.Writer.Error || Allocator.Error;

/// Writes the outcome as one line without a terminator. A script is written with a heap stack of
/// one frame per tree level, so a tree of any depth uses a constant amount of native stack; the
/// stack comes from the allocator that `parseScript` received and is freed before returning.
pub fn writeOutcome(parse: *const Parse, writer: *std.Io.Writer) WriteError!void {
    switch (parse.outcome) {
        .script => |tree| {
            const gpa = parse.arena.child_allocator;
            const stack = try gpa.alloc(ast.WriteFrame, parse.height);
            defer gpa.free(stack);
            try ast.writeScript(tree, stack, writer);
        },
        .diagnostic => |diagnostic| try writeDiagnostic(diagnostic, writer),
    }
}

pub fn writeDiagnostic(diagnostic: Diagnostic, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (diagnostic) {
        .syntax_error => |d| try writer.print("syntax-error {s} @{d}", .{ @tagName(d.code), d.offset }),
        .unsupported => |d| try writer.print("unsupported {s} @{d}", .{ @tagName(d.code), d.offset }),
        .limit => |d| try writer.print("limit {s} @{d}", .{ @tagName(d.code), d.offset }),
    }
}

/// Writes one line per code: the unsupported table, the syntax-error table, and the limit codes.
pub fn writeCodeTable(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (unsupported_table) |row| try writer.print("unsupported|{s}|{s}|{s}\n", .{ @tagName(row[0]), row[1], row[2] });
    for (syntax_error_table) |row| try writer.print("syntax-error|{s}|{s}\n", .{ @tagName(row[0]), row[1] });
    for (std.enums.values(LimitCode)) |code| try writer.print("limit|{s}\n", .{@tagName(code)});
}

/// Parses `source` with the Script goal. `error.OutOfMemory` means that `gpa` failed; exceeding
/// `options.max_memory_bytes` instead gives the outcome `limit memory`.
pub fn parseScript(gpa: Allocator, source: []const u16, options: Options) error{OutOfMemory}!Parse {
    var parse: Parse = .{ .arena = .init(gpa), .outcome = undefined };
    errdefer parse.arena.deinit();
    if (source.len > options.max_source_units) {
        parse.outcome = .{ .diagnostic = .{ .limit = .{ .code = .source_length, .offset = 0 } } };
        return parse;
    }
    var limiter: Limiter = .{ .child = gpa, .limit = options.max_memory_bytes };
    // The arena allocates through the limiter while the parser runs; the limiter passes every
    // request through to `gpa`, so `gpa` frees the arena after the limiter is gone.
    parse.arena.child_allocator = limiter.allocator();
    errdefer parse.arena.child_allocator = gpa;
    var parser: Parser = .{
        .arena = parse.arena.allocator(),
        .gpa = limiter.allocator(),
        .options = options,
        .source = source,
        .lexer = undefined,
        .tok = .{ .tag = .eof, .start = 0, .end = 0 },
    };
    parser.lexer = .{ .source = source, .arena = parser.arena, .scratch = &parser.scratch, .scratch_allocator = parser.gpa };
    defer parser.deinit();
    const outcome: @FieldType(Parse, "outcome") = if (parser.parseProgram()) |tree| .{ .script = tree } else |err| switch (err) {
        error.Diagnostic => .{ .diagnostic = parser.diagnostic },
        error.OutOfMemory => if (limiter.exceeded)
            .{ .diagnostic = .{ .limit = .{ .code = .memory, .offset = parser.tok.start } } }
        else
            return error.OutOfMemory,
    };
    parse.height = parser.tree_height;
    parse.arena.child_allocator = gpa;
    parse.outcome = outcome;
    return parse;
}

/// Passes allocations through to `child` while the outstanding bytes stay within `limit`.
const Limiter = struct {
    child: Allocator,
    limit: usize,
    used: usize = 0,
    /// The limiter refused an allocation.
    exceeded: bool = false,

    fn allocator(limiter: *Limiter) Allocator {
        return .{ .ptr = limiter, .vtable = &vtable };
    }

    const vtable: Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    fn fits(limiter: *const Limiter, bytes: usize) bool {
        return bytes <= limiter.limit - limiter.used;
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
        const limiter: *Limiter = @ptrCast(@alignCast(context));
        if (!limiter.fits(len)) {
            limiter.exceeded = true;
            return null;
        }
        const memory = limiter.child.rawAlloc(len, alignment, return_address) orelse return null;
        limiter.used += len;
        return memory;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
        const limiter: *Limiter = @ptrCast(@alignCast(context));
        if (new_len > memory.len and !limiter.fits(new_len - memory.len)) return false;
        if (!limiter.child.rawResize(memory, alignment, new_len, return_address)) return false;
        limiter.used = limiter.used - memory.len + new_len;
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const limiter: *Limiter = @ptrCast(@alignCast(context));
        if (new_len > memory.len and !limiter.fits(new_len - memory.len)) return null;
        const result = limiter.child.rawRemap(memory, alignment, new_len, return_address) orelse return null;
        limiter.used = limiter.used - memory.len + new_len;
        return result;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
        const limiter: *Limiter = @ptrCast(@alignCast(context));
        limiter.child.rawFree(memory, alignment, return_address);
        limiter.used -= memory.len;
    }
};

const Error = error{ OutOfMemory, Diagnostic };

/// The statement position that decides what a `function` token begins.
const Context = enum {
    /// A StatementListItem of a Script or a FunctionBody.
    list,
    /// A StatementListItem of a Block or a case or default clause.
    block,
    /// The Statement of an `if` or `else` clause.
    if_clause,
    /// The Statement of an iteration statement.
    loop_body,
    /// A LabelledItem whose label chain starts at a StatementListItem.
    label_in_list,
    /// A LabelledItem whose label chain is the Statement of an `if` clause or an iteration statement.
    label_in_statement,
};

const Flags = struct {
    /// The `[~In]` grammar parameter.
    no_in: bool = false,
    /// Leave a cover-grammar error of an ObjectLiteral pending for the caller, which may reinterpret
    /// the literal as a pattern.
    propagate: bool = false,
};

/// The state of a Script or a function body, with the function name and parameters that a Use
/// Strict Directive checks retroactively.
const Scope = struct {
    id: u32,
    strict: bool,
    /// The body is a FunctionBody, not a Script.
    function: bool,
    name: ?Name = null,
    name_offset: u32 = 0,
    params: []const Name = &.{},
    param_offsets: []const u32 = &.{},
    /// Iteration statements, and iteration and switch statements, that enclose the parser in this body.
    iterations: u32 = 0,
    breakables: u32 = 0,
    label_base: usize,
    names_base: usize,
    functions_base: usize,
    /// The first IdentifierReference `arguments` of a function body, not counting nested functions.
    arguments: ?u32 = null,
    /// The backslash of the first legacy octal escape in a directive of the prologue so far.
    directive_octal: ?u32 = null,
};

const Label = struct { name: Name, loop: bool };

const NameKey = struct { scope: u32, name: Name };

const NameContext = struct {
    pub fn hash(_: NameContext, key: NameKey) u64 {
        var hasher = std.hash.Wyhash.init(key.scope);
        hasher.update(std.mem.sliceAsBytes(key.name));
        return hasher.final();
    }
    pub fn eql(_: NameContext, a: NameKey, b: NameKey) bool {
        return a.scope == b.scope and std.mem.eql(u16, a.name, b.name);
    }
};

const NameSet = std.HashMapUnmanaged(NameKey, void, NameContext, std.hash_map.default_max_load_percentage);

/// The parameter names of one function, for the duplicate-parameter check.
const ParamContext = struct {
    pub fn hash(_: ParamContext, name: Name) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(name));
    }
    pub fn eql(_: ParamContext, a: Name, b: Name) bool {
        if (builtin.is_test) Parser.duplicate_comparisons += 1;
        return std.mem.eql(u16, a, b);
    }
};

const ParamSet = std.HashMapUnmanaged(Name, void, ParamContext, std.hash_map.default_max_load_percentage);

const FunctionKind = enum { declaration, expression };

/// A grammar procedure's position. Each procedure starts in its first state; a state that needs a
/// nested production pushes the nested procedure's frame and resumes in a later state when that
/// frame returns its result.
const State = enum {
    body_next,
    body_after_statement,
    list_next,
    list_after_statement,
    statement,
    block_after_list,
    variable_after_declarators,
    declarators_next,
    declarators_after_init,
    if_after_test,
    if_after_consequent,
    if_after_alternate,
    do_after_body,
    do_after_test,
    while_after_test,
    while_after_body,
    for_after_var,
    for_after_init,
    for_after_test,
    for_after_update,
    for_after_body,
    return_after_value,
    throw_after_value,
    switch_after_discriminant,
    switch_clause,
    switch_after_test,
    switch_statements,
    switch_after_statement,
    try_after_block,
    try_after_catch,
    try_after_finally,
    labelled_after_body,
    expression_statement_after,
    function_statement_after,
    function_start,
    function_after_body,
    expression_start,
    expression_after_first,
    expression_after_element,
    assign_start,
    assign_after_left,
    assign_after_consequent,
    assign_after_alternate,
    assign_after_value,
    binary_start,
    binary_after_left,
    binary_after_right,
    exponent_start,
    exponent_after_left,
    exponent_after_right,
    unary_start,
    unary_after_operand,
    prefix_after_operand,
    unary_after_member,
    member_start,
    member_after_base,
    member_after_index,
    member_after_arguments,
    new_start,
    new_after_callee,
    new_after_arguments,
    arguments_start,
    arguments_after_element,
    primary_start,
    primary_after_function,
    paren_start,
    paren_after_element,
    object_start,
    object_next,
    object_after_computed_key,
    object_after_computed_value,
    object_after_value,
    object_after_cover_value,
};

/// The locals of each grammar procedure.
const Locals = union(enum) {
    body: struct { base: u32, end: Tag, prologue: bool = true, candidate: bool = false, string_start: u32 = 0, string_end: u32 = 0, string_octal: ?u32 = null },
    list: struct { base: u32 },
    statement: struct { context: Context },
    block: struct { start: u32 },
    declarators: struct { base: u32, no_in: bool, name: Name = &.{} },
    if_statement: struct { start: u32, test_expression: *const Expression = undefined, consequent: *const Statement = undefined },
    loop: struct { start: u32, chain: ?usize, body: *const Statement = undefined, test_expression: *const Expression = undefined },
    for_statement: struct {
        start: u32,
        chain: ?usize,
        outer: ?Diagnostic = null,
        init: ?ast.ForInit = null,
        init_height: u32 = 0,
        test_expression: ?*const Expression = null,
        update: ?*const Expression = null,
    },
    value: struct { start: u32 },
    switch_statement: struct {
        start: u32,
        discriminant: *const Expression = undefined,
        base: u32 = 0,
        statements_base: u32 = 0,
        test_expression: ?*const Expression = null,
        has_default: bool = false,
        height: u32 = 0,
    },
    try_statement: struct { start: u32, block: []const *const Statement = &.{}, param: ?Name = null, handler: ?ast.Catch = null, height: u32 = 0 },
    labelled: struct { start: u32, name: Name, index: u32, duplicate: bool },
    function: struct { start: u32, kind: FunctionKind, index: u32 = 0 },
    expression: struct { flags: Flags, base: u32 = 0, height: u32 = 0 },
    assign: struct { flags: Flags, outer: ?Diagnostic = null, left: *const Expression = undefined, consequent: *const Expression = undefined, operator: ast.AssignmentOperator = .assign },
    binary: struct { min: u8, no_in: bool, left: *const Expression = undefined, operator: Operator = undefined },
    exponent: struct { left: *const Expression = undefined },
    unary: struct { start: u32 = 0, operator: ast.UnaryOperator = undefined, update: ast.UpdateOperator = undefined },
    member: struct { calls: bool, base: *const Expression = undefined, current: *const Expression = undefined, outer: ?Diagnostic = null, async_head: bool = false },
    new_expression: struct { start: u32 = 0, callee: *const Expression = undefined },
    arguments: struct { propagate: bool, base: u32 = 0 },
    primary: struct { start: u32 },
    paren: struct { start: u32 = 0, outer: ?Diagnostic = null, base: u32 = 0, height: u32 = 0 },
    object: struct { start: u32 = 0, base: u32 = 0, proto: bool = false, name: Name = &.{}, key_start: u32 = 0, key: *const Expression = undefined },
};

const Frame = struct { state: State, locals: Locals };

const Parser = struct {
    /// The tree's allocator.
    arena: Allocator,
    /// The allocator of the frames and the scratch lists below.
    gpa: Allocator,
    options: Options,
    source: []const u16,
    lexer: lexer.Lexer,
    scratch: std.ArrayList(u16) = .empty,
    tok: Token,
    peeked: ?Token = null,
    depth: u32 = 1,
    diagnostic: Diagnostic = undefined,
    /// The first cover-grammar error of an ObjectLiteral that may still be reinterpreted as a pattern.
    pending: ?Diagnostic = null,
    function_count: u32 = 0,
    scope_count: u32 = 0,
    /// The index in `labels` of the first label of the label chain that directly labels the statement being parsed.
    label_chain: ?usize = null,
    /// The grammar procedures in progress, innermost last. They hold the nesting state, so the
    /// parser's native stack does not grow with the depth of the source.
    frames: std.ArrayList(Frame) = .empty,
    scopes: std.ArrayList(Scope) = .empty,
    // The result of the procedure that returned last.
    expression_result: *const Expression = undefined,
    statement_result: *const Statement = undefined,
    function_result: *const ast.Function = undefined,
    statements_result: []const *const Statement = &.{},
    expressions_result: []const *const Expression = &.{},
    declarators_result: []const ast.Declarator = &.{},
    /// The height of the finished script's tree.
    tree_height: u32 = 0,
    expressions: std.ArrayList(*const Expression) = .empty,
    statements: std.ArrayList(*const Statement) = .empty,
    properties: std.ArrayList(ast.Property) = .empty,
    declarators: std.ArrayList(ast.Declarator) = .empty,
    cases: std.ArrayList(ast.Case) = .empty,
    params: std.ArrayList(Name) = .empty,
    param_offsets: std.ArrayList(u32) = .empty,
    var_names: std.ArrayList(Name) = .empty,
    seen: NameSet = .empty,
    declarations: std.ArrayList(*const ast.Function) = .empty,
    labels: std.ArrayList(Label) = .empty,
    function_names: NameSet = .empty,
    initialized: std.ArrayList(*const ast.Function) = .empty,
    params_seen: ParamSet = .empty,

    /// The name comparisons of the duplicate-parameter check on this thread. Only test builds
    /// compile it, because only `ParamContext.eql` under `builtin.is_test` refers to it.
    threadlocal var duplicate_comparisons: u64 = 0;

    fn deinit(p: *Parser) void {
        p.scratch.deinit(p.gpa);
        p.frames.deinit(p.gpa);
        p.scopes.deinit(p.gpa);
        p.expressions.deinit(p.gpa);
        p.statements.deinit(p.gpa);
        p.properties.deinit(p.gpa);
        p.declarators.deinit(p.gpa);
        p.cases.deinit(p.gpa);
        p.params.deinit(p.gpa);
        p.param_offsets.deinit(p.gpa);
        p.var_names.deinit(p.gpa);
        p.seen.deinit(p.gpa);
        p.declarations.deinit(p.gpa);
        p.labels.deinit(p.gpa);
        p.function_names.deinit(p.gpa);
        p.initialized.deinit(p.gpa);
        p.params_seen.deinit(p.gpa);
    }

    fn scope(p: *Parser) *Scope {
        return &p.scopes.items[p.scopes.items.len - 1];
    }

    // Diagnostics.

    fn fail(p: *Parser, diagnostic: Diagnostic) error{Diagnostic} {
        p.diagnostic = diagnostic;
        return error.Diagnostic;
    }

    fn syntax(p: *Parser, code: SyntaxErrorCode, offset: u32) error{Diagnostic} {
        return p.fail(.{ .syntax_error = .{ .code = code, .offset = offset } });
    }

    fn unsupported(p: *Parser, code: UnsupportedCode, offset: u32) error{Diagnostic} {
        return p.fail(.{ .unsupported = .{ .code = code, .offset = offset } });
    }

    /// No production continues with the current token.
    fn unexpected(p: *Parser) error{Diagnostic} {
        if (p.tok.tag == .eof) return p.syntax(.unexpected_end, @intCast(p.source.len));
        return p.syntax(.unexpected_token, p.tok.start);
    }

    fn limitDepth(p: *Parser) error{Diagnostic} {
        return p.fail(.{ .limit = .{ .code = .depth, .offset = p.tok.start } });
    }

    // Tokens.

    /// Reports the current token when it is invalid or begins a production that is always unsupported.
    fn checkCurrent(p: *Parser) error{Diagnostic}!void {
        switch (p.tok.tag) {
            .invalid => return p.fail(p.tok.problem),
            .template => return p.unsupported(.template, p.tok.start),
            .question_dot => return p.unsupported(.optional_chain, p.tok.start),
            .question_question => return p.unsupported(.coalesce, p.tok.start),
            .ampersand_ampersand_equal, .pipe_pipe_equal, .question_question_equal => return p.unsupported(.logical_assignment, p.tok.start),
            else => {},
        }
    }

    fn advance(p: *Parser) Error!void {
        if (p.peeked) |token| {
            p.tok = token;
            p.peeked = null;
        } else {
            p.tok = try p.lexer.next();
        }
        try p.checkCurrent();
    }

    /// The token after the current one. It is reported only when it becomes current.
    fn peek(p: *Parser) Error!*const Token {
        if (p.peeked == null) p.peeked = try p.lexer.next();
        return &p.peeked.?;
    }

    fn expect(p: *Parser, tag: Tag) Error!void {
        if (p.tok.tag != tag) return p.unexpected();
        try p.advance();
    }

    /// Consumes a semicolon or inserts one by the rules of 12.10.
    fn semicolon(p: *Parser) Error!void {
        switch (p.tok.tag) {
            .semicolon => try p.advance(),
            .r_brace, .eof => {},
            else => if (!p.tok.newline_before) return p.unexpected(),
        }
    }

    fn isUnescaped(p: *const Parser, text: []const u8) bool {
        return p.tok.tag == .identifier and !p.tok.escaped and eqlAscii(p.tok.units, text);
    }

    // Depth.

    /// Moves to the depth of a child node.
    fn descend(p: *Parser) error{Diagnostic}!void {
        p.depth += 1;
        if (p.depth > p.options.max_depth) return p.limitDepth();
    }

    fn ascend(p: *Parser) void {
        p.depth -= 1;
    }

    /// Checks a node of `height` that sits at the current depth or deeper.
    fn checkHeight(p: *Parser, height: u32) error{Diagnostic}!void {
        if (p.depth + height - 1 > p.options.max_depth) return p.limitDepth();
    }

    fn newExpression(p: *Parser, start: u32, height: u32, data: Expression.Data) Error!*const Expression {
        try p.checkHeight(height);
        const expression = try p.arena.create(Expression);
        expression.* = .{ .start = start, .height = height, .data = data };
        return expression;
    }

    fn newStatement(p: *Parser, start: u32, height: u32, data: Statement.Data) Error!*const Statement {
        try p.checkHeight(height);
        const statement = try p.arena.create(Statement);
        statement.* = .{ .start = start, .height = height, .data = data };
        return statement;
    }

    // Procedures.

    /// Starts a nested procedure. The caller has already set its own resume state and must not
    /// touch its frame again, because the push may move the frames.
    fn call(p: *Parser, state: State, locals: Locals) Error!void {
        try p.frames.append(p.gpa, .{ .state = state, .locals = locals });
    }

    fn callStatement(p: *Parser, context: Context) Error!void {
        return p.call(.statement, .{ .statement = .{ .context = context } });
    }

    fn callExpression(p: *Parser, flags: Flags) Error!void {
        return p.call(.expression_start, .{ .expression = .{ .flags = flags } });
    }

    fn callAssign(p: *Parser, flags: Flags) Error!void {
        return p.call(.assign_start, .{ .assign = .{ .flags = flags } });
    }

    /// Parses `{ StatementList }` at the depth of the statements.
    fn callList(p: *Parser) Error!void {
        try p.expect(.l_brace);
        return p.call(.list_next, .{ .list = .{ .base = @intCast(p.statements.items.len) } });
    }

    fn returnExpression(p: *Parser, expression: *const Expression) void {
        p.expression_result = expression;
        p.frames.items.len -= 1;
    }

    fn returnStatement(p: *Parser, statement: *const Statement) void {
        p.statement_result = statement;
        p.frames.items.len -= 1;
    }

    /// Runs procedures until the frames above `floor` have returned.
    fn run(p: *Parser, floor: usize) Error!void {
        while (p.frames.items.len > floor) {
            const frame = &p.frames.items[p.frames.items.len - 1];
            switch (frame.state) {
                .body_next => try p.bodyNext(frame),
                .body_after_statement => try p.bodyAfterStatement(frame),
                .list_next => try p.listNext(frame),
                .list_after_statement => {
                    try p.statements.append(p.gpa, p.statement_result);
                    frame.state = .list_next;
                },
                .statement => try p.statementStart(frame),
                .block_after_list => {
                    p.ascend();
                    const statements = p.statements_result;
                    p.returnStatement(try p.newStatement(frame.locals.block.start, 1 + maxHeight(statements), .{ .block = statements }));
                },
                .variable_after_declarators => {
                    const declarators = p.declarators_result;
                    try p.semicolon();
                    p.returnStatement(try p.newStatement(frame.locals.value.start, declaratorsHeight(declarators), .{ .variable = declarators }));
                },
                .declarators_next => try p.declaratorsNext(frame),
                .declarators_after_init => {
                    p.ascend();
                    p.ascend();
                    try p.declarators.append(p.gpa, .{ .name = frame.locals.declarators.name, .init = p.expression_result });
                    try p.declaratorsAfter(frame);
                },
                .if_after_test => {
                    frame.locals.if_statement.test_expression = p.expression_result;
                    try p.expect(.r_paren);
                    frame.state = .if_after_consequent;
                    try p.callStatement(.if_clause);
                },
                .if_after_consequent => {
                    frame.locals.if_statement.consequent = p.statement_result;
                    if (p.tok.tag == .kw_else) {
                        try p.advance();
                        frame.state = .if_after_alternate;
                        try p.callStatement(.if_clause);
                    } else try p.finishIf(frame, null);
                },
                .if_after_alternate => try p.finishIf(frame, p.statement_result),
                .do_after_body => {
                    p.endLoop();
                    frame.locals.loop.body = p.statement_result;
                    try p.expect(.kw_while);
                    try p.expect(.l_paren);
                    frame.state = .do_after_test;
                    try p.callExpression(.{});
                },
                .do_after_test => {
                    const l = &frame.locals.loop;
                    const test_expression = p.expression_result;
                    try p.expect(.r_paren);
                    p.ascend();
                    // 12.10.1, rule 1, third condition: a semicolon is inserted after the `)` of a do-while statement when needed.
                    if (p.tok.tag == .semicolon) try p.advance();
                    p.returnStatement(try p.newStatement(l.start, 1 + @max(l.body.height, test_expression.height), .{ .do_while = .{ .body = l.body, .test_expression = test_expression } }));
                },
                .while_after_test => {
                    frame.locals.loop.test_expression = p.expression_result;
                    try p.expect(.r_paren);
                    p.beginLoop(frame.locals.loop.chain);
                    frame.state = .while_after_body;
                    try p.callStatement(.loop_body);
                },
                .while_after_body => {
                    const l = &frame.locals.loop;
                    p.endLoop();
                    p.ascend();
                    const body = p.statement_result;
                    p.returnStatement(try p.newStatement(l.start, 1 + @max(l.test_expression.height, body.height), .{ .while_statement = .{ .test_expression = l.test_expression, .body = body } }));
                },
                .for_after_var => {
                    const l = &frame.locals.for_statement;
                    try p.checkForInOf();
                    l.init = .{ .variable = p.declarators_result };
                    l.init_height = declaratorsHeight(p.declarators_result);
                    try p.forAfterInit(frame);
                },
                .for_after_init => {
                    const l = &frame.locals.for_statement;
                    try p.checkForInOf();
                    // Only a for-in or for-of head reinterprets an ObjectLiteral as a pattern.
                    if (p.pending) |pending| return p.fail(pending);
                    p.pending = l.outer;
                    l.init = .{ .expression = p.expression_result };
                    l.init_height = p.expression_result.height;
                    try p.forAfterInit(frame);
                },
                .for_after_test => {
                    frame.locals.for_statement.test_expression = p.expression_result;
                    try p.forAfterTest(frame);
                },
                .for_after_update => {
                    frame.locals.for_statement.update = p.expression_result;
                    try p.forBody(frame);
                },
                .for_after_body => {
                    const l = &frame.locals.for_statement;
                    p.endLoop();
                    p.ascend();
                    const body = p.statement_result;
                    const height = 1 + @max(l.init_height, optionalHeight(l.test_expression), optionalHeight(l.update), body.height);
                    p.returnStatement(try p.newStatement(l.start, height, .{ .for_statement = .{ .init = l.init, .test_expression = l.test_expression, .update = l.update, .body = body } }));
                },
                .return_after_value => {
                    p.ascend();
                    const value = p.expression_result;
                    try p.semicolon();
                    p.returnStatement(try p.newStatement(frame.locals.value.start, 1 + value.height, .{ .return_statement = value }));
                },
                .throw_after_value => {
                    p.ascend();
                    const value = p.expression_result;
                    try p.semicolon();
                    p.returnStatement(try p.newStatement(frame.locals.value.start, 1 + value.height, .{ .throw_statement = value }));
                },
                .switch_after_discriminant => {
                    const l = &frame.locals.switch_statement;
                    l.discriminant = p.expression_result;
                    try p.expect(.r_paren);
                    try p.expect(.l_brace);
                    p.scope().breakables += 1;
                    l.base = @intCast(p.cases.items.len);
                    l.height = 1 + l.discriminant.height;
                    frame.state = .switch_clause;
                },
                .switch_clause => try p.switchClause(frame),
                .switch_after_test => {
                    p.ascend();
                    frame.locals.switch_statement.test_expression = p.expression_result;
                    try p.switchColon(frame);
                },
                .switch_statements => try p.switchStatements(frame),
                .switch_after_statement => {
                    try p.statements.append(p.gpa, p.statement_result);
                    frame.state = .switch_statements;
                },
                .try_after_block => try p.tryAfterBlock(frame),
                .try_after_catch => {
                    const l = &frame.locals.try_statement;
                    p.ascend();
                    p.ascend();
                    const body = p.statements_result;
                    l.height = @max(l.height, 3 + maxHeight(body));
                    l.handler = .{ .param = l.param, .body = body };
                    try p.tryFinally(frame);
                },
                .try_after_finally => {
                    p.ascend();
                    p.ascend();
                    const body = p.statements_result;
                    frame.locals.try_statement.height = @max(frame.locals.try_statement.height, 3 + maxHeight(body));
                    try p.finishTry(frame, body);
                },
                .labelled_after_body => {
                    const l = &frame.locals.labelled;
                    p.ascend();
                    p.labels.shrinkRetainingCapacity(l.index);
                    // ContainsDuplicateLabels (8.3.1) is detected when the labelled statement completes.
                    if (l.duplicate) return p.syntax(.duplicate_label, l.start);
                    const body = p.statement_result;
                    p.returnStatement(try p.newStatement(l.start, 1 + body.height, .{ .labelled = .{ .label = l.name, .body = body } }));
                },
                .expression_statement_after => {
                    p.ascend();
                    const expression = p.expression_result;
                    try p.semicolon();
                    p.returnStatement(try p.newStatement(frame.locals.value.start, 1 + expression.height, .{ .expression = expression }));
                },
                .function_statement_after => {
                    const function = p.function_result;
                    p.returnStatement(try p.newStatement(frame.locals.value.start, function.height, .{ .function_declaration = function }));
                },
                .function_start => try p.functionStart(frame),
                .function_after_body => try p.functionAfterBody(frame),
                .expression_start => {
                    frame.state = .expression_after_first;
                    try p.callAssign(frame.locals.expression.flags);
                },
                .expression_after_first => {
                    const l = &frame.locals.expression;
                    const first = p.expression_result;
                    if (p.tok.tag != .comma) {
                        p.returnExpression(first);
                        continue;
                    }
                    l.base = @intCast(p.expressions.items.len);
                    l.height = first.height;
                    try p.expressions.append(p.gpa, first);
                    try p.advance();
                    frame.state = .expression_after_element;
                    try p.callAssign(l.flags);
                },
                .expression_after_element => {
                    const l = &frame.locals.expression;
                    const element = p.expression_result;
                    l.height = @max(l.height, element.height);
                    try p.expressions.append(p.gpa, element);
                    if (p.tok.tag == .comma) {
                        try p.advance();
                        try p.callAssign(l.flags);
                        continue;
                    }
                    const elements = try p.arena.dupe(*const Expression, p.expressions.items[l.base..]);
                    p.expressions.shrinkRetainingCapacity(l.base);
                    p.returnExpression(try p.newExpression(elements[0].start, 1 + l.height, .{ .sequence = elements }));
                },
                .assign_start => {
                    const l = &frame.locals.assign;
                    l.outer = p.pending;
                    p.pending = null;
                    frame.state = .assign_after_left;
                    try p.call(.binary_start, .{ .binary = .{ .min = 0, .no_in = l.flags.no_in } });
                },
                .assign_after_left => try p.assignAfterLeft(frame),
                .assign_after_consequent => {
                    const l = &frame.locals.assign;
                    l.consequent = p.expression_result;
                    try p.expect(.colon);
                    frame.state = .assign_after_alternate;
                    try p.callAssign(.{ .no_in = l.flags.no_in });
                },
                .assign_after_alternate => {
                    const l = &frame.locals.assign;
                    p.ascend();
                    const alternate = p.expression_result;
                    const height = 1 + @max(l.left.height, l.consequent.height, alternate.height);
                    try p.finishAssign(frame, try p.newExpression(l.left.start, height, .{ .conditional = .{ .test_expression = l.left, .consequent = l.consequent, .alternate = alternate } }));
                },
                .assign_after_value => {
                    const l = &frame.locals.assign;
                    p.ascend();
                    const value = p.expression_result;
                    // The assignment is complete, so a cover-grammar error inside the target is final.
                    if (p.pending) |pending| return p.fail(pending);
                    try p.checkTarget(l.left);
                    try p.finishAssign(frame, try p.newExpression(l.left.start, 1 + @max(l.left.height, value.height), .{ .assign = .{ .operator = l.operator, .target = l.left, .value = value } }));
                },
                .binary_start => {
                    frame.state = .binary_after_left;
                    try p.call(.exponent_start, .{ .exponent = .{} });
                },
                .binary_after_left => {
                    frame.locals.binary.left = p.expression_result;
                    try p.binaryNext(frame);
                },
                .binary_after_right => {
                    const l = &frame.locals.binary;
                    p.ascend();
                    const right = p.expression_result;
                    const height = 1 + @max(l.left.height, right.height);
                    l.left = try p.newExpression(l.left.start, height, switch (l.operator) {
                        .logical => |logical| .{ .logical = .{ .operator = logical, .left = l.left, .right = right } },
                        .binary => |binary| .{ .binary = .{ .operator = binary, .left = l.left, .right = right } },
                    });
                    try p.binaryNext(frame);
                },
                .exponent_start => {
                    frame.state = .exponent_after_left;
                    try p.call(.unary_start, .{ .unary = .{} });
                },
                .exponent_after_left => {
                    const left = p.expression_result;
                    if (p.tok.tag != .star_star) {
                        p.returnExpression(left);
                        continue;
                    }
                    // ExponentiationExpression (13.6): the left operand of `**` is an UpdateExpression.
                    if (left.data == .unary) return p.syntax(.unary_before_exponent, p.tok.start);
                    frame.locals.exponent.left = left;
                    try p.advance();
                    try p.descend();
                    frame.state = .exponent_after_right;
                    try p.call(.exponent_start, .{ .exponent = .{} });
                },
                .exponent_after_right => {
                    const left = frame.locals.exponent.left;
                    p.ascend();
                    const right = p.expression_result;
                    p.returnExpression(try p.newExpression(left.start, 1 + @max(left.height, right.height), .{ .binary = .{ .operator = .exponent, .left = left, .right = right } }));
                },
                .unary_start => try p.unaryStart(frame),
                .unary_after_operand => {
                    const l = &frame.locals.unary;
                    p.ascend();
                    const operand = p.expression_result;
                    if (l.operator == .delete and p.scope().strict and isIdentifierInParentheses(operand)) return p.syntax(.strict_delete_identifier, l.start);
                    p.returnExpression(try p.newExpression(l.start, 1 + operand.height, .{ .unary = .{ .operator = l.operator, .operand = operand } }));
                },
                .prefix_after_operand => {
                    const l = &frame.locals.unary;
                    p.ascend();
                    const operand = p.expression_result;
                    try p.checkTarget(operand);
                    p.returnExpression(try p.newExpression(l.start, 1 + operand.height, .{ .prefix = .{ .operator = l.update, .operand = operand } }));
                },
                .unary_after_member => {
                    const expression = p.expression_result;
                    // 12.10: no line terminator may precede a postfix `++` or `--`.
                    if ((p.tok.tag == .plus_plus or p.tok.tag == .minus_minus) and !p.tok.newline_before) {
                        const update: ast.UpdateOperator = if (p.tok.tag == .plus_plus) .increment else .decrement;
                        try p.checkTarget(expression);
                        try p.advance();
                        p.returnExpression(try p.newExpression(expression.start, 1 + expression.height, .{ .postfix = .{ .operator = update, .operand = expression } }));
                    } else p.returnExpression(expression);
                },
                .member_start => {
                    frame.state = .member_after_base;
                    if (p.tok.tag == .kw_new) {
                        try p.call(.new_start, .{ .new_expression = .{} });
                    } else {
                        try p.call(.primary_start, .{ .primary = .{ .start = p.tok.start } });
                    }
                },
                .member_after_base => {
                    frame.locals.member.base = p.expression_result;
                    frame.locals.member.current = p.expression_result;
                    try p.memberNext(frame);
                },
                .member_after_index => {
                    const l = &frame.locals.member;
                    p.ascend();
                    const index = p.expression_result;
                    try p.expect(.r_bracket);
                    l.current = try p.newExpression(l.current.start, 1 + @max(l.current.height, index.height), .{ .index = .{ .object = l.current, .index = index } });
                    try p.memberNext(frame);
                },
                .member_after_arguments => {
                    const l = &frame.locals.member;
                    p.ascend();
                    const arguments = p.expressions_result;
                    if (l.async_head) {
                        if (p.tok.tag == .arrow) return p.unsupported(.async_function, l.current.start);
                        if (p.pending) |pending| return p.fail(pending);
                        p.pending = l.outer;
                    }
                    l.current = try p.newExpression(l.current.start, 1 + @max(l.current.height, maxExpressionHeight(arguments)), .{ .call = .{ .callee = l.current, .arguments = arguments } });
                    try p.memberNext(frame);
                },
                .new_start => {
                    const l = &frame.locals.new_expression;
                    l.start = p.tok.start;
                    try p.advance();
                    if (p.tok.tag == .dot) return p.unsupported(.new_target, l.start);
                    try p.descend();
                    frame.state = .new_after_callee;
                    try p.call(.member_start, .{ .member = .{ .calls = false } });
                },
                .new_after_callee => {
                    frame.locals.new_expression.callee = p.expression_result;
                    if (p.tok.tag == .l_paren) {
                        frame.state = .new_after_arguments;
                        try p.call(.arguments_start, .{ .arguments = .{ .propagate = false } });
                    } else try p.finishNew(frame, &.{});
                },
                .new_after_arguments => try p.finishNew(frame, p.expressions_result),
                .arguments_start => {
                    try p.advance();
                    frame.locals.arguments.base = @intCast(p.expressions.items.len);
                    try p.argumentsNext(frame);
                },
                .arguments_after_element => {
                    try p.expressions.append(p.gpa, p.expression_result);
                    if (p.tok.tag == .comma) {
                        try p.advance();
                    } else if (p.tok.tag != .r_paren) {
                        return p.unexpected();
                    }
                    try p.argumentsNext(frame);
                },
                .primary_start => try p.primaryStart(frame),
                .primary_after_function => {
                    const function = p.function_result;
                    p.returnExpression(try p.newExpression(frame.locals.primary.start, function.height, .{ .function = function }));
                },
                .paren_start => try p.parenStart(frame),
                .paren_after_element => try p.parenAfterElement(frame),
                .object_start => {
                    const l = &frame.locals.object;
                    l.start = p.tok.start;
                    try p.advance();
                    try p.descend();
                    l.base = @intCast(p.properties.items.len);
                    frame.state = .object_next;
                },
                .object_next => try p.objectNext(frame),
                .object_after_computed_key => {
                    const l = &frame.locals.object;
                    p.ascend();
                    p.ascend();
                    l.key = p.expression_result;
                    try p.expect(.r_bracket);
                    if (p.tok.tag == .l_paren) return p.unsupported(.method_definition, p.tok.start);
                    try p.expect(.colon);
                    try p.descend();
                    frame.state = .object_after_computed_value;
                    try p.callAssign(.{ .propagate = true });
                },
                .object_after_computed_value => {
                    p.ascend();
                    try p.properties.append(p.gpa, .{ .computed = .{ .key = frame.locals.object.key, .value = p.expression_result } });
                    try p.objectAfterProperty(frame);
                },
                .object_after_value => {
                    const l = &frame.locals.object;
                    p.ascend();
                    try p.appendProperty(l.name, l.key_start, p.expression_result, &l.proto);
                    try p.objectAfterProperty(frame);
                },
                .object_after_cover_value => {
                    p.ascend();
                    try p.properties.append(p.gpa, .{ .shorthand = frame.locals.object.name });
                    try p.objectAfterProperty(frame);
                },
            }
        }
    }

    // Identifiers.

    /// Checks the current token as an IdentifierReference or a LabelIdentifier (13.1.1).
    fn checkReference(p: *Parser) error{Diagnostic}!void {
        if (p.tok.tag != .identifier) {
            if (p.tok.tag.isKeyword()) return p.syntax(.reserved_word, p.tok.start);
            return p.unexpected();
        }
        if (p.tok.escaped_reserved) return p.syntax(.reserved_word, p.tok.start);
        if (p.scope().strict and lexer.isStrictReserved(p.tok.units)) return p.syntax(.strict_reserved_word, p.tok.start);
    }

    /// Checks the current token as a BindingIdentifier (13.1.1).
    fn checkBinding(p: *Parser) error{Diagnostic}!void {
        try p.checkReference();
        if (p.scope().strict and isEvalOrArguments(p.tok.units)) return p.syntax(.strict_eval_arguments, p.tok.start);
    }

    /// Adds `name` to the VarDeclaredNames of the current body.
    fn declareVar(p: *Parser, name: Name) Error!void {
        const entry = try p.seen.getOrPut(p.gpa, .{ .scope = p.scope().id, .name = name });
        if (!entry.found_existing) try p.var_names.append(p.gpa, name);
    }

    fn findLabel(p: *Parser, name: Name) ?*Label {
        var index = p.labels.items.len;
        while (index > p.scope().label_base) {
            index -= 1;
            if (std.mem.eql(u16, p.labels.items[index].name, name)) return &p.labels.items[index];
        }
        return null;
    }

    /// Marks the labels that directly label an iteration statement as continue targets, and enters its body.
    fn beginLoop(p: *Parser, chain: ?usize) void {
        if (chain) |first| {
            for (p.labels.items[first..]) |*label| label.loop = true;
        }
        p.scope().iterations += 1;
        p.scope().breakables += 1;
    }

    fn endLoop(p: *Parser) void {
        p.scope().iterations -= 1;
        p.scope().breakables -= 1;
    }

    /// Records the first IdentifierReference `arguments` of a function body.
    fn noteReference(p: *Parser, name: Name, offset: u32) void {
        const current = p.scope();
        if (current.function and current.arguments == null and eqlAscii(name, "arguments")) current.arguments = offset;
    }

    // Bodies.

    fn parseProgram(p: *Parser) Error!*const ast.Script {
        try p.scopes.append(p.gpa, .{ .id = 0, .strict = false, .function = false, .label_base = 0, .names_base = 0, .functions_base = 0 });
        p.scope_count = 1;
        p.tok = try p.lexer.next();
        try p.checkCurrent();
        p.depth = 2;
        try p.call(.body_next, .{ .body = .{ .base = 0, .end = .eof } });
        try p.run(0);
        const statements = p.statements_result;
        p.depth = 1;
        const height = 1 + maxHeight(statements);
        try p.checkHeight(height);
        const tree = try p.arena.create(ast.Script);
        tree.* = .{
            .strict = p.scope().strict,
            .var_declared_names = try p.finishNames(p.scope()),
            .functions_to_initialize = try p.functionsToInitialize(p.scope()),
            .statements = statements,
        };
        p.tree_height = height;
        return tree;
    }

    /// One StatementListItem of a Script or a FunctionBody, with its directive prologue.
    fn bodyNext(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.body;
        if (p.tok.tag == l.end) {
            p.statements_result = try p.arena.dupe(*const Statement, p.statements.items[l.base..]);
            p.statements.shrinkRetainingCapacity(l.base);
            p.frames.items.len -= 1;
            return;
        }
        if (p.tok.tag == .eof) return p.unexpected();
        l.candidate = l.prologue and p.tok.tag == .string;
        l.string_start = p.tok.start;
        l.string_end = p.tok.end;
        l.string_octal = p.tok.legacy_octal;
        frame.state = .body_after_statement;
        try p.callStatement(.list);
    }

    fn bodyAfterStatement(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.body;
        const statement = p.statement_result;
        try p.statements.append(p.gpa, statement);
        frame.state = .body_next;
        if (!l.prologue) return;
        // 11.2.1: a directive is an ExpressionStatement that consists entirely of a StringLiteral.
        const directive = l.candidate and statement.data == .expression and
            statement.data.expression.data == .string and statement.data.expression.start == l.string_start;
        if (!directive) {
            l.prologue = false;
        } else if (l.string_end - l.string_start == 12 and eqlAscii(p.source[l.string_start + 1 .. l.string_end - 1], "use strict")) {
            if (!p.scope().strict) try p.becomeStrict();
        } else if (l.string_octal) |offset| {
            if (p.scope().directive_octal == null) p.scope().directive_octal = offset;
        }
    }

    /// Applies a Use Strict Directive: the body is strict from here on, and the earlier directives,
    /// the function's name, and its parameters are checked as strict code. The first error in source
    /// order is reported.
    fn becomeStrict(p: *Parser) Error!void {
        const current = p.scope();
        current.strict = true;
        var first: ?Diagnostic = null;
        const consider = struct {
            fn call(best: *?Diagnostic, code: SyntaxErrorCode, offset: u32) void {
                if (best.* == null or offset < best.*.?.syntax_error.offset) best.* = .{ .syntax_error = .{ .code = code, .offset = offset } };
            }
        }.call;
        if (current.directive_octal) |offset| consider(&first, .strict_octal_escape, offset);
        if (current.name) |name| {
            if (strictBindingProblem(name)) |code| consider(&first, code, current.name_offset);
        }
        for (current.params, current.param_offsets) |param, offset| {
            if (strictBindingProblem(param)) |code| consider(&first, code, offset);
        }
        if (try p.duplicateParameter(current.params, current.param_offsets)) |offset| consider(&first, .duplicate_parameter, offset);
        if (first) |diagnostic| return p.fail(diagnostic);
    }

    /// The offset of the first parameter that repeats an earlier name. Each parameter takes one
    /// lookup in a hashed set, so the check is linear in the number of parameters; the set is
    /// emptied by removing its names, so a later check does not pay for an earlier one's capacity.
    fn duplicateParameter(p: *Parser, params: []const Name, offsets: []const u32) Allocator.Error!?u32 {
        try p.params_seen.ensureTotalCapacity(p.gpa, @intCast(params.len));
        var inserted: usize = 0;
        defer for (params[0..inserted]) |param| {
            _ = p.params_seen.remove(param);
        };
        for (params, offsets) |param, offset| {
            if (p.params_seen.getOrPutAssumeCapacity(param).found_existing) return offset;
            inserted += 1;
        }
        return null;
    }

    /// Copies the VarDeclaredNames of `body` to the tree and forgets them.
    fn finishNames(p: *Parser, body: *const Scope) Error![]const Name {
        const names = p.var_names.items[body.names_base..];
        const copy = try p.arena.dupe(Name, names);
        for (names) |name| _ = p.seen.remove(.{ .scope = body.id, .name = name });
        p.var_names.shrinkRetainingCapacity(body.names_base);
        return copy;
    }

    /// The functionsToInitialize list of 16.1.7 and 10.2.11: the top-level FunctionDeclarations of
    /// `body` in reverse order, keeping the last declaration of each name, listed in source order.
    fn functionsToInitialize(p: *Parser, body: *const Scope) Error![]const *const ast.Function {
        const declarations = p.declarations.items[body.functions_base..];
        p.function_names.clearRetainingCapacity();
        p.initialized.clearRetainingCapacity();
        var index = declarations.len;
        while (index > 0) {
            index -= 1;
            const function = declarations[index];
            const entry = try p.function_names.getOrPut(p.gpa, .{ .scope = 0, .name = function.name.? });
            if (!entry.found_existing) try p.initialized.append(p.gpa, function);
        }
        std.mem.reverse(*const ast.Function, p.initialized.items);
        p.declarations.shrinkRetainingCapacity(body.functions_base);
        return p.arena.dupe(*const ast.Function, p.initialized.items);
    }

    fn declaresFunction(p: *const Parser, body: *const Scope, name: []const u8) bool {
        for (p.declarations.items[body.functions_base..]) |function| {
            if (eqlAscii(function.name.?, name)) return true;
        }
        return false;
    }

    fn listNext(p: *Parser, frame: *Frame) Error!void {
        const base = frame.locals.list.base;
        if (p.tok.tag == .r_brace) {
            p.statements_result = try p.arena.dupe(*const Statement, p.statements.items[base..]);
            p.statements.shrinkRetainingCapacity(base);
            try p.advance();
            p.frames.items.len -= 1;
            return;
        }
        if (p.tok.tag == .eof) return p.unexpected();
        frame.state = .list_after_statement;
        try p.callStatement(.block);
    }

    // Statements.

    fn statementStart(p: *Parser, frame: *Frame) Error!void {
        const context = frame.locals.statement.context;
        // Only a labelled statement continues the label chain to its item.
        const chain = p.label_chain;
        p.label_chain = null;
        const start = p.tok.start;
        switch (p.tok.tag) {
            .l_brace => {
                try p.descend();
                frame.* = .{ .state = .block_after_list, .locals = .{ .block = .{ .start = start } } };
                try p.callList();
            },
            .kw_var => {
                frame.* = .{ .state = .variable_after_declarators, .locals = .{ .value = .{ .start = start } } };
                try p.callDeclarators(false);
            },
            .semicolon => {
                try p.advance();
                p.returnStatement(try p.newStatement(start, 1, .empty));
            },
            .kw_if => {
                try p.advance();
                try p.expect(.l_paren);
                try p.descend();
                frame.* = .{ .state = .if_after_test, .locals = .{ .if_statement = .{ .start = start } } };
                try p.callExpression(.{});
            },
            .kw_do => {
                try p.advance();
                try p.descend();
                p.beginLoop(chain);
                frame.* = .{ .state = .do_after_body, .locals = .{ .loop = .{ .start = start, .chain = chain } } };
                try p.callStatement(.loop_body);
            },
            .kw_while => {
                try p.advance();
                try p.expect(.l_paren);
                try p.descend();
                frame.* = .{ .state = .while_after_test, .locals = .{ .loop = .{ .start = start, .chain = chain } } };
                try p.callExpression(.{});
            },
            .kw_for => try p.forStart(frame, chain),
            .kw_continue => p.returnStatement(try p.parseJump(false)),
            .kw_break => p.returnStatement(try p.parseJump(true)),
            .kw_return => {
                if (!p.scope().function) return p.syntax(.return_outside_function, start);
                try p.advance();
                // 12.10: a line terminator after `return` ends the statement.
                const has_value = switch (p.tok.tag) {
                    .semicolon, .r_brace, .eof => false,
                    else => !p.tok.newline_before,
                };
                if (has_value) {
                    try p.descend();
                    frame.* = .{ .state = .return_after_value, .locals = .{ .value = .{ .start = start } } };
                    try p.callExpression(.{});
                } else {
                    try p.semicolon();
                    p.returnStatement(try p.newStatement(start, 1, .{ .return_statement = null }));
                }
            },
            .kw_with => return if (p.scope().strict) p.syntax(.strict_with, start) else p.unsupported(.with, start),
            .kw_switch => {
                try p.advance();
                try p.expect(.l_paren);
                try p.descend();
                frame.* = .{ .state = .switch_after_discriminant, .locals = .{ .switch_statement = .{ .start = start } } };
                try p.callExpression(.{});
            },
            .kw_throw => {
                try p.advance();
                if (p.tok.newline_before) return p.syntax(.throw_line_terminator, start);
                try p.descend();
                frame.* = .{ .state = .throw_after_value, .locals = .{ .value = .{ .start = start } } };
                try p.callExpression(.{});
            },
            .kw_try => {
                try p.advance();
                // `(try (block s...) (catch e (block s...)) (finally (block s...)))`.
                try p.descend();
                try p.descend();
                frame.* = .{ .state = .try_after_block, .locals = .{ .try_statement = .{ .start = start } } };
                try p.callList();
            },
            .kw_debugger => {
                try p.advance();
                try p.semicolon();
                p.returnStatement(try p.newStatement(start, 1, .debugger));
            },
            .kw_function => switch (context) {
                .list => {
                    frame.* = .{ .state = .function_statement_after, .locals = .{ .value = .{ .start = start } } };
                    try p.call(.function_start, .{ .function = .{ .start = start, .kind = .declaration } });
                },
                .block => return p.unsupported(.block_function_declaration, start),
                .if_clause, .label_in_list => return if (p.scope().strict)
                    p.syntax(.function_declaration_position, start)
                else
                    p.unsupported(.block_function_declaration, start),
                .loop_body, .label_in_statement => return p.syntax(.function_declaration_position, start),
            },
            .kw_class => return p.unsupported(.class, start),
            .kw_const => return p.unsupported(.lexical_declaration, start),
            .kw_import => return p.unsupported(.import, start),
            .identifier => {
                if (p.isUnescaped("let")) {
                    const next = try p.peek();
                    if (next.tag == .l_bracket or next.tag == .l_brace or next.tag == .identifier) return p.unsupported(.lexical_declaration, start);
                } else if (p.isUnescaped("async")) {
                    const next = try p.peek();
                    if (!next.newline_before and (next.tag == .kw_function or next.tag == .identifier)) return p.unsupported(.async_function, start);
                } else if (p.isUnescaped("using")) {
                    const next = try p.peek();
                    if (!next.newline_before and next.tag == .identifier) return p.unsupported(.using_declaration, start);
                }
                if ((try p.peek()).tag == .colon) {
                    try p.labelledStart(frame, context, chain);
                } else {
                    try p.expressionStatementStart(frame);
                }
            },
            else => try p.expressionStatementStart(frame),
        }
    }

    fn expressionStatementStart(p: *Parser, frame: *Frame) Error!void {
        const start = p.tok.start;
        try p.descend();
        frame.* = .{ .state = .expression_statement_after, .locals = .{ .value = .{ .start = start } } };
        try p.callExpression(.{});
    }

    fn labelledStart(p: *Parser, frame: *Frame, context: Context, chain: ?usize) Error!void {
        const start = p.tok.start;
        try p.checkReference();
        const name = p.tok.units;
        const duplicate = p.findLabel(name) != null;
        try p.advance();
        try p.advance();
        const index = p.labels.items.len;
        try p.labels.append(p.gpa, .{ .name = name, .loop = false });
        p.label_chain = chain orelse index;
        try p.descend();
        frame.* = .{ .state = .labelled_after_body, .locals = .{ .labelled = .{ .start = start, .name = name, .index = @intCast(index), .duplicate = duplicate } } };
        try p.callStatement(switch (context) {
            .list, .block, .label_in_list => .label_in_list,
            .if_clause, .loop_body, .label_in_statement => .label_in_statement,
        });
    }

    /// Parses `var` and its declarations at the depth of the `(var ...)` group.
    fn callDeclarators(p: *Parser, no_in: bool) Error!void {
        try p.advance();
        return p.call(.declarators_next, .{ .declarators = .{ .base = @intCast(p.declarators.items.len), .no_in = no_in } });
    }

    fn declaratorsNext(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.declarators;
        if (p.tok.tag == .l_bracket or p.tok.tag == .l_brace) return p.unsupported(.destructuring_binding, p.tok.start);
        try p.checkBinding();
        const name = p.tok.units;
        try p.declareVar(name);
        try p.advance();
        if (p.tok.tag == .equal) {
            try p.advance();
            try p.descend();
            try p.descend();
            l.name = name;
            frame.state = .declarators_after_init;
            return p.callAssign(.{ .no_in = l.no_in });
        }
        try p.declarators.append(p.gpa, .{ .name = name, .init = null });
        try p.declaratorsAfter(frame);
    }

    fn declaratorsAfter(p: *Parser, frame: *Frame) Error!void {
        const base = frame.locals.declarators.base;
        if (p.tok.tag == .comma) {
            try p.advance();
            frame.state = .declarators_next;
            return;
        }
        p.declarators_result = try p.arena.dupe(ast.Declarator, p.declarators.items[base..]);
        p.declarators.shrinkRetainingCapacity(base);
        p.frames.items.len -= 1;
    }

    fn finishIf(p: *Parser, frame: *Frame, alternate: ?*const Statement) Error!void {
        const l = &frame.locals.if_statement;
        p.ascend();
        const height = 1 + @max(l.test_expression.height, l.consequent.height, if (alternate) |s| s.height else 0);
        p.returnStatement(try p.newStatement(l.start, height, .{ .if_statement = .{ .test_expression = l.test_expression, .consequent = l.consequent, .alternate = alternate } }));
    }

    /// Reports `in` or `of` after the first part of a `for` head.
    fn checkForInOf(p: *Parser) error{Diagnostic}!void {
        if (p.tok.tag == .kw_in) return p.unsupported(.for_in, p.tok.start);
        if (p.isUnescaped("of")) return p.unsupported(.for_of, p.tok.start);
    }

    fn forStart(p: *Parser, frame: *Frame, chain: ?usize) Error!void {
        const start = p.tok.start;
        try p.advance();
        if (p.isUnescaped("await")) return p.unsupported(.for_await, p.tok.start);
        try p.expect(.l_paren);
        try p.descend();
        frame.* = .{ .state = .for_after_init, .locals = .{ .for_statement = .{ .start = start, .chain = chain } } };
        switch (p.tok.tag) {
            .semicolon => try p.forAfterInit(frame),
            .kw_var => {
                frame.state = .for_after_var;
                try p.callDeclarators(true);
            },
            .kw_const => return p.unsupported(.lexical_declaration, p.tok.start),
            else => {
                if (p.isUnescaped("let")) return p.unsupported(.lexical_declaration, p.tok.start);
                if (p.isUnescaped("using")) {
                    const next = try p.peek();
                    if (!next.newline_before and next.tag == .identifier) return p.unsupported(.using_declaration, p.tok.start);
                }
                frame.locals.for_statement.outer = p.pending;
                p.pending = null;
                try p.callExpression(.{ .no_in = true, .propagate = true });
            },
        }
    }

    fn forAfterInit(p: *Parser, frame: *Frame) Error!void {
        try p.expect(.semicolon);
        if (p.tok.tag != .semicolon) {
            frame.state = .for_after_test;
            return p.callExpression(.{});
        }
        try p.forAfterTest(frame);
    }

    fn forAfterTest(p: *Parser, frame: *Frame) Error!void {
        try p.expect(.semicolon);
        if (p.tok.tag != .r_paren) {
            frame.state = .for_after_update;
            return p.callExpression(.{});
        }
        try p.forBody(frame);
    }

    fn forBody(p: *Parser, frame: *Frame) Error!void {
        try p.expect(.r_paren);
        p.beginLoop(frame.locals.for_statement.chain);
        frame.state = .for_after_body;
        try p.callStatement(.loop_body);
    }

    fn parseJump(p: *Parser, is_break: bool) Error!*const Statement {
        const start = p.tok.start;
        try p.advance();
        var label: ?Name = null;
        var label_offset: u32 = 0;
        // 12.10: no line terminator may precede the label.
        if (p.tok.tag == .identifier and !p.tok.newline_before) {
            try p.checkReference();
            label = p.tok.units;
            label_offset = p.tok.start;
            try p.advance();
        }
        try p.semicolon();
        if (label) |name| {
            const target = p.findLabel(name);
            if (is_break and target == null) return p.syntax(.undefined_break_target, label_offset);
            if (!is_break and (target == null or !target.?.loop)) return p.syntax(.undefined_continue_target, label_offset);
        } else if (is_break and p.scope().breakables == 0) {
            return p.syntax(.break_outside, start);
        } else if (!is_break and p.scope().iterations == 0) {
            return p.syntax(.continue_outside, start);
        }
        return p.newStatement(start, 1, if (is_break) .{ .break_statement = label } else .{ .continue_statement = label });
    }

    fn switchClause(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.switch_statement;
        switch (p.tok.tag) {
            .r_brace => {
                p.scope().breakables -= 1;
                const cases = try p.arena.dupe(ast.Case, p.cases.items[l.base..]);
                p.cases.shrinkRetainingCapacity(l.base);
                try p.advance();
                p.ascend();
                p.returnStatement(try p.newStatement(l.start, l.height, .{ .switch_statement = .{ .discriminant = l.discriminant, .cases = cases } }));
            },
            .kw_case => {
                try p.advance();
                try p.descend();
                frame.state = .switch_after_test;
                try p.callExpression(.{});
            },
            .kw_default => {
                if (l.has_default) return p.unexpected();
                l.has_default = true;
                l.test_expression = null;
                try p.advance();
                try p.switchColon(frame);
            },
            else => return p.unexpected(),
        }
    }

    fn switchColon(p: *Parser, frame: *Frame) Error!void {
        try p.expect(.colon);
        try p.descend();
        frame.locals.switch_statement.statements_base = @intCast(p.statements.items.len);
        frame.state = .switch_statements;
    }

    fn switchStatements(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.switch_statement;
        switch (p.tok.tag) {
            .kw_case, .kw_default, .r_brace => {
                p.ascend();
                const body = try p.arena.dupe(*const Statement, p.statements.items[l.statements_base..]);
                p.statements.shrinkRetainingCapacity(l.statements_base);
                l.height = @max(l.height, 2 + @max(optionalHeight(l.test_expression), maxHeight(body)));
                try p.cases.append(p.gpa, .{ .test_expression = l.test_expression, .body = body });
                frame.state = .switch_clause;
            },
            .eof => return p.unexpected(),
            else => {
                frame.state = .switch_after_statement;
                try p.callStatement(.block);
            },
        }
    }

    fn tryAfterBlock(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.try_statement;
        p.ascend();
        l.block = p.statements_result;
        l.height = 2 + maxHeight(l.block);
        if (p.tok.tag != .kw_catch) return p.tryFinally(frame);
        try p.advance();
        if (p.tok.tag == .l_paren) {
            try p.advance();
            if (p.tok.tag == .l_bracket or p.tok.tag == .l_brace) return p.unsupported(.destructuring_binding, p.tok.start);
            try p.checkBinding();
            l.param = p.tok.units;
            try p.advance();
            try p.expect(.r_paren);
        }
        try p.descend();
        try p.descend();
        frame.state = .try_after_catch;
        try p.callList();
    }

    fn tryFinally(p: *Parser, frame: *Frame) Error!void {
        if (p.tok.tag != .kw_finally) return p.finishTry(frame, null);
        try p.advance();
        try p.descend();
        try p.descend();
        frame.state = .try_after_finally;
        try p.callList();
    }

    fn finishTry(p: *Parser, frame: *Frame, finalizer: ?[]const *const Statement) Error!void {
        const l = &frame.locals.try_statement;
        if (l.handler == null and finalizer == null) return p.unexpected();
        p.ascend();
        p.returnStatement(try p.newStatement(l.start, l.height, .{ .try_statement = .{ .block = l.block, .handler = l.handler, .finalizer = finalizer } }));
    }

    // Functions.

    fn functionStart(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.function;
        try p.advance();
        if (p.tok.tag == .star) return p.unsupported(.generator, p.tok.start);
        var name: ?Name = null;
        var name_offset: u32 = 0;
        if (l.kind == .declaration or p.tok.tag != .l_paren) {
            // The enclosing code's strictness applies now; the function's own Use Strict Directive applies later.
            try p.checkBinding();
            name = p.tok.units;
            name_offset = p.tok.start;
            try p.advance();
        }
        if (l.kind == .declaration) {
            p.function_count += 1;
            l.index = p.function_count;
            try p.declareVar(name.?);
        }
        const enclosing = p.scope();
        try p.scopes.append(p.gpa, .{
            .id = p.scope_count,
            .strict = enclosing.strict,
            .function = true,
            .name = name,
            .name_offset = name_offset,
            .label_base = p.labels.items.len,
            .names_base = p.var_names.items.len,
            .functions_base = p.declarations.items.len,
        });
        p.scope_count += 1;
        try p.parseParams();
        if (p.tok.tag != .l_brace) return p.unexpected();
        try p.advance();
        try p.descend();
        frame.state = .function_after_body;
        try p.call(.body_next, .{ .body = .{ .base = @intCast(p.statements.items.len), .end = .r_brace } });
    }

    /// Parses `( FormalParameters )` of BindingIdentifiers into the current scope.
    fn parseParams(p: *Parser) Error!void {
        try p.expect(.l_paren);
        const base = p.params.items.len;
        defer p.params.shrinkRetainingCapacity(base);
        defer p.param_offsets.shrinkRetainingCapacity(base);
        while (p.tok.tag != .r_paren) {
            switch (p.tok.tag) {
                .l_bracket, .l_brace => return p.unsupported(.destructuring_binding, p.tok.start),
                .ellipsis => return p.unsupported(.rest_parameter, p.tok.start),
                else => {},
            }
            try p.checkBinding();
            try p.params.append(p.gpa, p.tok.units);
            try p.param_offsets.append(p.gpa, p.tok.start);
            try p.advance();
            if (p.tok.tag == .equal) return p.unsupported(.default_parameter, p.tok.start);
            if (p.tok.tag == .comma) {
                try p.advance();
            } else if (p.tok.tag != .r_paren) {
                return p.unexpected();
            }
        }
        const current = p.scope();
        current.params = try p.arena.dupe(Name, p.params.items[base..]);
        current.param_offsets = try p.arena.dupe(u32, p.param_offsets.items[base..]);
        // 15.2.1: strict FormalParameters have no duplicate names, detected when the list completes.
        if (current.strict) {
            if (try p.duplicateParameter(current.params, current.param_offsets)) |offset| return p.syntax(.duplicate_parameter, offset);
        }
        try p.advance();
    }

    fn functionAfterBody(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.function;
        p.ascend();
        const statements = p.statements_result;
        const body = p.scope();
        if (body.arguments) |offset| {
            if (!containsName(body.params, "arguments") and !p.declaresFunction(body, "arguments")) return p.unsupported(.arguments_object, offset);
        }
        const function = try p.arena.create(ast.Function);
        function.* = .{
            .index = l.index,
            .name = body.name,
            .params = body.params,
            .strict = body.strict,
            .var_declared_names = try p.finishNames(body),
            .functions_to_initialize = try p.functionsToInitialize(body),
            .statements = statements,
            .source_start = l.start,
            .source_end = p.tok.end,
            .height = 1 + maxHeight(statements),
        };
        p.scopes.items.len -= 1;
        try p.checkHeight(function.height);
        if (l.kind == .declaration) try p.declarations.append(p.gpa, function);
        try p.advance();
        p.function_result = function;
        p.frames.items.len -= 1;
    }

    // Expressions.

    fn assignAfterLeft(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.assign;
        const left = p.expression_result;
        switch (p.tok.tag) {
            .question => {
                l.left = left;
                try p.advance();
                try p.descend();
                frame.state = .assign_after_consequent;
                try p.callAssign(.{});
            },
            // A `=>` after `left`: an arrow function, or an async arrow function after a call of `async`.
            .arrow => {
                if (left.data == .call and p.isAsyncReference(left.data.call.callee)) return p.unsupported(.async_function, left.start);
                return p.unsupported(.arrow_function, p.tok.start);
            },
            else => {
                const operator = assignmentOperator(p.tok.tag) orelse return p.finishAssign(frame, left);
                // 13.15.1: an ObjectLiteral before `=` is reparsed as an ObjectAssignmentPattern.
                if (operator == .assign and left.data == .object) return p.unsupported(.destructuring_assignment, p.tok.start);
                l.left = left;
                l.operator = operator;
                try p.advance();
                try p.descend();
                frame.state = .assign_after_value;
                try p.callAssign(.{ .no_in = l.flags.no_in });
            },
        }
    }

    /// Returns an AssignmentExpression and settles its pending cover-grammar error.
    fn finishAssign(p: *Parser, frame: *Frame, expression: *const Expression) Error!void {
        const l = &frame.locals.assign;
        if (p.pending) |pending| {
            if (!l.flags.propagate) return p.fail(pending);
            if (l.outer != null) p.pending = l.outer;
        } else {
            p.pending = l.outer;
        }
        p.returnExpression(expression);
    }

    /// Whether `expression` is the IdentifierReference `async` written without escapes.
    fn isAsyncReference(p: *const Parser, expression: *const Expression) bool {
        if (expression.data != .identifier or !eqlAscii(expression.data.identifier, "async")) return false;
        return expression.start + 5 <= p.source.len and eqlAscii(p.source[expression.start..][0..5], "async");
    }

    /// Checks the AssignmentTargetType (8.6.4) of an assignment or update target: `simple`, or
    /// `web-compat` for a call in non-strict code (B.3.9).
    fn checkTarget(p: *Parser, target: *const Expression) error{Diagnostic}!void {
        var inner = target;
        while (inner.data == .paren) inner = inner.data.paren;
        switch (inner.data) {
            .identifier => |name| if (p.scope().strict and isEvalOrArguments(name)) return p.syntax(.strict_eval_arguments, inner.start),
            .member, .index => {},
            .call => if (p.scope().strict) return p.syntax(.invalid_assignment_target, target.start),
            else => return p.syntax(.invalid_assignment_target, target.start),
        }
    }

    /// Binary and logical operators by precedence climbing, above ExponentiationExpression.
    fn binaryNext(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.binary;
        const operator = binaryOperator(p.tok.tag, l.no_in) orelse return p.returnExpression(l.left);
        const precedence = operator.precedence();
        if (precedence < l.min) return p.returnExpression(l.left);
        l.operator = operator;
        try p.advance();
        try p.descend();
        frame.state = .binary_after_right;
        try p.call(.binary_start, .{ .binary = .{ .min = precedence + 1, .no_in = l.no_in } });
    }

    fn unaryStart(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.unary;
        l.start = p.tok.start;
        const operator: ?ast.UnaryOperator = switch (p.tok.tag) {
            .kw_delete => .delete,
            .kw_void => .void,
            .kw_typeof => .typeof,
            .plus => .plus,
            .minus => .minus,
            .tilde => .bitwise_not,
            .bang => .logical_not,
            else => null,
        };
        if (operator) |unary| {
            l.operator = unary;
            try p.advance();
            try p.descend();
            frame.state = .unary_after_operand;
            return p.call(.unary_start, .{ .unary = .{} });
        }
        if (p.tok.tag == .plus_plus or p.tok.tag == .minus_minus) {
            l.update = if (p.tok.tag == .plus_plus) .increment else .decrement;
            try p.advance();
            try p.descend();
            frame.state = .prefix_after_operand;
            return p.call(.unary_start, .{ .unary = .{} });
        }
        frame.state = .unary_after_member;
        try p.call(.member_start, .{ .member = .{ .calls = true } });
    }

    /// Parses `.name`, `[expression]`, and, when calls are allowed, Arguments after the current expression.
    fn memberNext(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.member;
        while (true) {
            switch (p.tok.tag) {
                .dot => {
                    try p.advance();
                    const name = try p.identifierName();
                    try p.advance();
                    l.current = try p.newExpression(l.current.start, 1 + l.current.height, .{ .member = .{ .object = l.current, .name = name } });
                },
                .l_bracket => {
                    try p.advance();
                    try p.descend();
                    frame.state = .member_after_index;
                    return p.callExpression(.{});
                },
                .l_paren => {
                    if (!l.calls) break;
                    // After a call of `async`, the arguments may be the parameters of an async arrow
                    // function, so their cover-grammar errors wait for the `=>`.
                    l.async_head = l.current == l.base and p.isAsyncReference(l.base);
                    l.outer = p.pending;
                    if (l.async_head) p.pending = null;
                    try p.descend();
                    frame.state = .member_after_arguments;
                    return p.call(.arguments_start, .{ .arguments = .{ .propagate = l.async_head } });
                },
                else => break,
            }
        }
        p.returnExpression(l.current);
    }

    /// The IdentifierName of the current token, which may be a ReservedWord.
    fn identifierName(p: *Parser) error{Diagnostic}!Name {
        if (p.tok.tag == .identifier) return p.tok.units;
        if (p.tok.tag.isKeyword()) return p.source[p.tok.start..p.tok.end];
        return p.unexpected();
    }

    fn finishNew(p: *Parser, frame: *Frame, arguments: []const *const Expression) Error!void {
        const l = &frame.locals.new_expression;
        p.ascend();
        p.returnExpression(try p.newExpression(l.start, 1 + @max(l.callee.height, maxExpressionHeight(arguments)), .{ .new = .{ .callee = l.callee, .arguments = arguments } }));
    }

    fn argumentsNext(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.arguments;
        if (p.tok.tag == .r_paren) {
            p.expressions_result = try p.arena.dupe(*const Expression, p.expressions.items[l.base..]);
            p.expressions.shrinkRetainingCapacity(l.base);
            try p.advance();
            p.frames.items.len -= 1;
            return;
        }
        if (p.tok.tag == .ellipsis) return p.unsupported(.spread, p.tok.start);
        frame.state = .arguments_after_element;
        try p.callAssign(.{ .propagate = l.propagate });
    }

    fn primaryStart(p: *Parser, frame: *Frame) Error!void {
        const start = p.tok.start;
        const leaf: Expression.Data = switch (p.tok.tag) {
            .identifier => return p.returnExpression(try p.parseIdentifierReference()),
            .l_paren => {
                frame.* = .{ .state = .paren_start, .locals = .{ .paren = .{} } };
                return;
            },
            .l_brace => {
                frame.* = .{ .state = .object_start, .locals = .{ .object = .{} } };
                return;
            },
            .kw_new => {
                frame.* = .{ .state = .new_start, .locals = .{ .new_expression = .{} } };
                return;
            },
            .kw_function => {
                frame.state = .primary_after_function;
                return p.call(.function_start, .{ .function = .{ .start = start, .kind = .expression } });
            },
            .kw_this => .this,
            .kw_null => .null_literal,
            .kw_true => .true_literal,
            .kw_false => .false_literal,
            .number => number: {
                if (p.tok.legacy_octal != null and p.scope().strict) return p.syntax(.strict_octal, start);
                break :number .{ .number = p.tok.value };
            },
            .string => string: {
                if (p.scope().strict) if (p.tok.legacy_octal) |offset| return p.syntax(.strict_octal_escape, offset);
                break :string .{ .string = p.tok.units };
            },
            .bigint => return p.unsupported(.bigint_literal, start),
            .l_bracket => return p.unsupported(.array_literal, start),
            .kw_class => return p.unsupported(.class, start),
            .kw_super => return p.unsupported(.super, start),
            .kw_import => return p.unsupported(.import, start),
            .slash, .slash_equal => return p.unsupported(.regular_expression, start),
            else => return p.unexpected(),
        };
        try p.advance();
        p.returnExpression(try p.newExpression(start, 1, leaf));
    }

    fn parseIdentifierReference(p: *Parser) Error!*const Expression {
        const start = p.tok.start;
        if (p.isUnescaped("async")) {
            const next = try p.peek();
            if (!next.newline_before and (next.tag == .kw_function or next.tag == .identifier)) return p.unsupported(.async_function, start);
        }
        try p.checkReference();
        const name = p.tok.units;
        p.noteReference(name, start);
        try p.advance();
        return p.newExpression(start, 1, .{ .identifier = name });
    }

    /// CoverParenthesizedExpressionAndArrowParameterList (13.2.9). Forms that only arrow
    /// parameters allow wait for the token after `)`.
    fn parenStart(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.paren;
        l.start = p.tok.start;
        try p.advance();
        if (p.tok.tag == .r_paren) return p.arrowParametersOnly();
        l.outer = p.pending;
        p.pending = null;
        try p.descend();
        l.base = @intCast(p.expressions.items.len);
        try p.parenElement(frame);
    }

    fn parenElement(p: *Parser, frame: *Frame) Error!void {
        if (p.tok.tag == .ellipsis) return p.unsupported(.arrow_function, p.tok.start);
        frame.state = .paren_after_element;
        try p.callAssign(.{ .propagate = true });
    }

    fn parenAfterElement(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.paren;
        const element = p.expression_result;
        l.height = @max(l.height, element.height);
        try p.expressions.append(p.gpa, element);
        if (p.tok.tag == .comma) {
            try p.advance();
            // A trailing comma ends only arrow parameters.
            if (p.tok.tag == .r_paren) return p.arrowParametersOnly();
            return p.parenElement(frame);
        }
        if (p.tok.tag != .r_paren) return p.unexpected();
        const elements = p.expressions.items[l.base..];
        const inner = if (elements.len == 1)
            elements[0]
        else
            try p.newExpression(elements[0].start, 1 + l.height, .{ .sequence = try p.arena.dupe(*const Expression, elements) });
        p.expressions.shrinkRetainingCapacity(l.base);
        p.ascend();
        try p.advance();
        if (p.tok.tag == .arrow) return p.unsupported(.arrow_function, p.tok.start);
        if (p.pending) |pending| return p.fail(pending);
        p.pending = l.outer;
        p.returnExpression(try p.newExpression(l.start, 1 + inner.height, .{ .paren = inner }));
    }

    /// At the `)` of `( )` or `( Expression , )`, which the full grammar continues only with `=>`
    /// (13.2): the error is at the next token, or at the end of the input.
    fn arrowParametersOnly(p: *Parser) Error!void {
        try p.advance();
        if (p.tok.tag == .arrow) return p.unsupported(.arrow_function, p.tok.start);
        return p.unexpected();
    }

    /// One PropertyDefinition, at the depth of the property group, or the end of the ObjectLiteral.
    fn objectNext(p: *Parser, frame: *Frame) Error!void {
        const l = &frame.locals.object;
        const start = p.tok.start;
        switch (p.tok.tag) {
            .r_brace => {
                p.ascend();
                const properties = try p.arena.dupe(ast.Property, p.properties.items[l.base..]);
                p.properties.shrinkRetainingCapacity(l.base);
                var height: u32 = 0;
                for (properties) |property| height = @max(height, property.height());
                const object = try p.newExpression(l.start, 1 + height, .{ .object = properties });
                try p.advance();
                return p.returnExpression(object);
            },
            .ellipsis => return p.unsupported(.object_spread, start),
            .star => return p.unsupported(.method_definition, start),
            .bigint => return p.unsupported(.bigint_literal, start),
            .l_bracket => {
                try p.advance();
                // `(property (computed key) value)`: the key sits two levels below the property group.
                try p.descend();
                try p.descend();
                frame.state = .object_after_computed_key;
                return p.callAssign(.{});
            },
            .string, .number => {
                const key = try p.literalKey();
                if (p.tok.tag == .l_paren) return p.unsupported(.method_definition, p.tok.start);
                try p.expect(.colon);
                return p.objectValue(frame, key, start);
            },
            .identifier => {
                // `get`, `set`, or `async` followed by a property name begins a MethodDefinition.
                if (!p.tok.escaped and (eqlAscii(p.tok.units, "get") or eqlAscii(p.tok.units, "set") or eqlAscii(p.tok.units, "async"))) {
                    const next = try p.peek();
                    const begins_name = switch (next.tag) {
                        .identifier, .string, .number, .bigint, .l_bracket => true,
                        .star => eqlAscii(p.tok.units, "async"),
                        else => next.tag.isKeyword(),
                    };
                    if (begins_name) return p.unsupported(.method_definition, start);
                }
            },
            else => if (!p.tok.tag.isKeyword()) return p.unexpected(),
        }
        const name = try p.identifierName();
        switch ((try p.peek()).tag) {
            .colon => {
                try p.advance();
                try p.advance();
                try p.objectValue(frame, name, start);
            },
            .l_paren => return p.unsupported(.method_definition, p.peeked.?.start),
            .equal => {
                // CoverInitializedName (13.2.5.1) is valid only in a pattern.
                try p.checkReference();
                if (p.pending == null) p.pending = .{ .syntax_error = .{ .code = .cover_initialized_name, .offset = start } };
                try p.advance();
                try p.advance();
                l.name = name;
                try p.descend();
                frame.state = .object_after_cover_value;
                try p.callAssign(.{});
            },
            .comma, .r_brace => {
                try p.checkReference();
                p.noteReference(name, start);
                try p.advance();
                try p.properties.append(p.gpa, .{ .shorthand = name });
                try p.objectAfterProperty(frame);
            },
            else => {
                try p.advance();
                return p.unexpected();
            },
        }
    }

    /// Parses the value of `PropertyName : AssignmentExpression`, one level below the property group.
    fn objectValue(p: *Parser, frame: *Frame, key: []const u16, start: u32) Error!void {
        frame.locals.object.name = key;
        frame.locals.object.key_start = start;
        try p.descend();
        frame.state = .object_after_value;
        try p.callAssign(.{ .propagate = true });
    }

    fn objectAfterProperty(p: *Parser, frame: *Frame) Error!void {
        if (p.tok.tag == .comma) {
            try p.advance();
        } else if (p.tok.tag != .r_brace) {
            return p.unexpected();
        }
        frame.state = .object_next;
    }

    /// The PropName of a StringLiteral or NumericLiteral key, which becomes consumed.
    fn literalKey(p: *Parser) Error![]const u16 {
        if (p.tok.tag == .string) {
            if (p.scope().strict) if (p.tok.legacy_octal) |offset| return p.syntax(.strict_octal_escape, offset);
            const units = p.tok.units;
            try p.advance();
            return units;
        }
        if (p.tok.legacy_octal != null and p.scope().strict) return p.syntax(.strict_octal, p.tok.start);
        var buffer: [number.max_string_units]u16 = undefined;
        const key = try p.arena.dupe(u16, number.toString(p.tok.value, &buffer));
        try p.advance();
        return key;
    }

    fn appendProperty(p: *Parser, key: []const u16, start: u32, value: *const Expression, proto: *bool) Error!void {
        if (!eqlAscii(key, "__proto__")) return p.properties.append(p.gpa, .{ .property = .{ .key = key, .value = value } });
        // 13.2.5.1: two `__proto__: value` definitions are an error unless the literal is a pattern.
        if (proto.*) {
            if (p.pending == null) p.pending = .{ .syntax_error = .{ .code = .duplicate_proto, .offset = start } };
        } else {
            proto.* = true;
        }
        return p.properties.append(p.gpa, .{ .proto = value });
    }
};

const Operator = union(enum) {
    binary: ast.BinaryOperator,
    logical: ast.LogicalOperator,

    fn precedence(operator: Operator) u8 {
        return switch (operator) {
            .logical => |logical| switch (logical) {
                .@"or" => 1,
                .@"and" => 2,
            },
            .binary => |binary| switch (binary) {
                .bitwise_or => 3,
                .bitwise_xor => 4,
                .bitwise_and => 5,
                .equal, .not_equal, .strict_equal, .strict_not_equal => 6,
                .less, .greater, .less_equal, .greater_equal, .instanceof, .in => 7,
                .shift_left, .shift_right, .shift_right_unsigned => 8,
                .add, .subtract => 9,
                .multiply, .divide, .remainder => 10,
                .exponent => 11,
            },
        };
    }
};

fn binaryOperator(tag: Tag, no_in: bool) ?Operator {
    return switch (tag) {
        .pipe_pipe => .{ .logical = .@"or" },
        .ampersand_ampersand => .{ .logical = .@"and" },
        .pipe => .{ .binary = .bitwise_or },
        .caret => .{ .binary = .bitwise_xor },
        .ampersand => .{ .binary = .bitwise_and },
        .equal_equal => .{ .binary = .equal },
        .bang_equal => .{ .binary = .not_equal },
        .equal_equal_equal => .{ .binary = .strict_equal },
        .bang_equal_equal => .{ .binary = .strict_not_equal },
        .less => .{ .binary = .less },
        .greater => .{ .binary = .greater },
        .less_equal => .{ .binary = .less_equal },
        .greater_equal => .{ .binary = .greater_equal },
        .kw_instanceof => .{ .binary = .instanceof },
        .kw_in => if (no_in) null else .{ .binary = .in },
        .shift_left => .{ .binary = .shift_left },
        .shift_right => .{ .binary = .shift_right },
        .shift_right_unsigned => .{ .binary = .shift_right_unsigned },
        .plus => .{ .binary = .add },
        .minus => .{ .binary = .subtract },
        .star => .{ .binary = .multiply },
        .slash => .{ .binary = .divide },
        .percent => .{ .binary = .remainder },
        else => null,
    };
}

fn assignmentOperator(tag: Tag) ?ast.AssignmentOperator {
    return switch (tag) {
        .equal => .assign,
        .star_equal => .multiply,
        .slash_equal => .divide,
        .percent_equal => .remainder,
        .plus_equal => .add,
        .minus_equal => .subtract,
        .shift_left_equal => .shift_left,
        .shift_right_equal => .shift_right,
        .shift_right_unsigned_equal => .shift_right_unsigned,
        .ampersand_equal => .bitwise_and,
        .caret_equal => .bitwise_xor,
        .pipe_equal => .bitwise_or,
        .star_star_equal => .exponent,
        else => null,
    };
}

fn isEvalOrArguments(name: Name) bool {
    return eqlAscii(name, "eval") or eqlAscii(name, "arguments");
}

/// The early error of a BindingIdentifier `name` in strict code, if any.
fn strictBindingProblem(name: Name) ?SyntaxErrorCode {
    if (lexer.isStrictReserved(name)) return .strict_reserved_word;
    if (isEvalOrArguments(name)) return .strict_eval_arguments;
    return null;
}

fn containsName(names: []const Name, name: []const u8) bool {
    for (names) |candidate| {
        if (eqlAscii(candidate, name)) return true;
    }
    return false;
}

fn isIdentifierInParentheses(expression: *const Expression) bool {
    var inner = expression;
    while (inner.data == .paren) inner = inner.data.paren;
    return inner.data == .identifier;
}

fn maxHeight(statements: []const *const Statement) u32 {
    var height: u32 = 0;
    for (statements) |statement| height = @max(height, statement.height);
    return height;
}

fn maxExpressionHeight(expressions: []const *const Expression) u32 {
    var height: u32 = 0;
    for (expressions) |expression| height = @max(height, expression.height);
    return height;
}

fn optionalHeight(expression: ?*const Expression) u32 {
    return if (expression) |e| e.height else 0;
}

/// The height of a `(var (name init)...)` group.
fn declaratorsHeight(declarators: []const ast.Declarator) u32 {
    var height: u32 = 1;
    for (declarators) |declarator| height = @max(height, if (declarator.init) |init| 1 + init.height else 1);
    return 1 + height;
}

// Tests.

/// The dump of a script from its strictness, names, functions, and statements.
fn script(comptime strictness: []const u8, comptime names: []const u8, comptime functions: []const u8, comptime statements: []const u8) []const u8 {
    return "(script " ++ strictness ++ " (var-declared-names" ++ (if (names.len == 0) "" else " " ++ names) ++
        ") (functions-to-initialize" ++ (if (functions.len == 0) "" else " " ++ functions) ++ ")" ++
        (if (statements.len == 0) "" else " " ++ statements) ++ ")";
}

const Case = struct { name: []const u8, source: []const u8, expected: []const u8 };

const t_cases = [_]Case{
    .{ .name = "T1", .source = "", .expected = script("sloppy", "", "", "") },
    .{ .name = "T2", .source = "\"use strict\";", .expected = script("strict", "", "", "(expression (string \"use strict\"))") },
    .{ .name = "T3", .source =
    \\"use\x20strict"; var let;
    , .expected = script("sloppy", "let", "", "(expression (string \"use strict\")) (var (let))") },
    .{ .name = "T4", .source = "\"a\"; \"use strict\";", .expected = script("strict", "", "", "(expression (string \"a\")) (expression (string \"use strict\"))") },
    .{ .name = "T5", .source = "\"use strict\"\n+1; var let;", .expected = script("sloppy", "let", "", "(expression (binary + (string \"use strict\") (number 1))) (var (let))") },
    .{ .name = "T6", .source = "(\"use strict\"); var let;", .expected = script("sloppy", "let", "", "(expression (paren (string \"use strict\"))) (var (let))") },
    .{ .name = "T7", .source = "var a, b = 1; var a;", .expected = script("sloppy", "a b", "", "(var (a) (b (number 1))) (var (a))") },
    .{ .name = "T8", .source = "function f() {} function g() {} function f() {}", .expected = script("sloppy", "f g", "g#2 f#3", "(function-declaration #1 f (params) sloppy (var-declared-names) (functions-to-initialize)) (function-declaration #2 g (params) sloppy (var-declared-names) (functions-to-initialize)) (function-declaration #3 f (params) sloppy (var-declared-names) (functions-to-initialize))") },
    .{ .name = "T9", .source = "function f(a, b) { var c = a; function g() {} return c + b; }", .expected = script("sloppy", "f", "f#1", "(function-declaration #1 f (params a b) sloppy (var-declared-names c g) (functions-to-initialize g#2) (var (c (identifier a))) (function-declaration #2 g (params) sloppy (var-declared-names) (functions-to-initialize)) (return (binary + (identifier c) (identifier b))))") },
    .{ .name = "T10", .source = "function f() { \"use strict\"; return this; }", .expected = script("sloppy", "f", "f#1", "(function-declaration #1 f (params) strict (var-declared-names) (functions-to-initialize) (expression (string \"use strict\")) (return (this)))") },
    .{ .name = "T11", .source = "if (a) { var x; } while (b) var y; for (var z;;) {} try { var p } catch (q) { var r } finally { var s } l: var t; switch (u) { case 1: var v; default: var w; }", .expected = script("sloppy", "x y z p r s t v w", "", "(if (identifier a) (block (var (x)))) (while (identifier b) (var (y))) (for (var (z)) - - (block)) (try (block (var (p))) (catch q (block (var (r)))) (finally (block (var (s))))) (labelled l (var (t))) (switch (identifier u) (case (number 1) (var (v))) (default (var (w))))") },
    .{ .name = "T12", .source = "a + b * c - d; a = b = c; a || b && c; a ? b : c ? d : e;", .expected = script("sloppy", "", "", "(expression (binary - (binary + (identifier a) (binary * (identifier b) (identifier c))) (identifier d))) (expression (assign = (identifier a) (assign = (identifier b) (identifier c)))) (expression (logical || (identifier a) (logical && (identifier b) (identifier c)))) (expression (conditional (identifier a) (identifier b) (conditional (identifier c) (identifier d) (identifier e))))") },
    .{ .name = "T13", .source = "2 ** 3 ** 2; (-2) ** 2; ++a ** 2; a ** -b;", .expected = script("sloppy", "", "", "(expression (binary ** (number 2) (binary ** (number 3) (number 2)))) (expression (binary ** (paren (unary - (number 2))) (number 2))) (expression (binary ** (prefix ++ (identifier a)) (number 2))) (expression (binary ** (identifier a) (unary - (identifier b))))") },
    .{ .name = "T14", .source = "a < b == c > d; a & b | c ^ d; a << b + c >>> d; a instanceof b in c;", .expected = script("sloppy", "", "", "(expression (binary == (binary < (identifier a) (identifier b)) (binary > (identifier c) (identifier d)))) (expression (binary | (binary & (identifier a) (identifier b)) (binary ^ (identifier c) (identifier d)))) (expression (binary >>> (binary << (identifier a) (binary + (identifier b) (identifier c))) (identifier d))) (expression (binary in (binary instanceof (identifier a) (identifier b)) (identifier c)))") },
    .{ .name = "T15", .source = "typeof void delete a.b; - -a; ~!a; a+++b; a, b, c;", .expected = script("sloppy", "", "", "(expression (unary typeof (unary void (unary delete (member (identifier a) \"b\"))))) (expression (unary - (unary - (identifier a)))) (expression (unary ~ (unary ! (identifier a)))) (expression (binary + (postfix ++ (identifier a)) (identifier b))) (expression (sequence (identifier a) (identifier b) (identifier c)))") },
    .{ .name = "T16", .source = "new a.b(c).d(e)[f]; new new a()(); new a; new a().b; new (a()); new a()();", .expected = script("sloppy", "", "", "(expression (index (call (member (new (member (identifier a) \"b\") (identifier c)) \"d\") (identifier e)) (identifier f))) (expression (new (new (identifier a)))) (expression (new (identifier a))) (expression (member (new (identifier a)) \"b\")) (expression (new (paren (call (identifier a))))) (expression (call (new (identifier a))))") },
    .{ .name = "T17", .source =
    \\a.if.class[0](1, 2,); a.\u0069f; 5..a; a ? .5 : 1;
    , .expected = script("sloppy", "", "", "(expression (call (index (member (member (identifier a) \"if\") \"class\") (number 0)) (number 1) (number 2))) (expression (member (identifier a) \"if\")) (expression (member (number 5) \"a\")) (expression (conditional (identifier a) (number 0.5) (number 1)))") },
    .{ .name = "T18", .source =
    \\({a: 1, "b": 2, 3: 3, 0x10: 4, 1.50: 5, [k]: 6, c, __proto__: null, if: 7, \u0069f: 8,});
    , .expected = script("sloppy", "", "", "(expression (paren (object (property \"a\" (number 1)) (property \"b\" (number 2)) (property \"3\" (number 3)) (property \"16\" (number 4)) (property \"1.5\" (number 5)) (property (computed (identifier k)) (number 6)) (shorthand c) (proto (null)) (property \"if\" (number 7)) (property \"if\" (number 8)))))") },
    .{ .name = "T19", .source = "({\"__proto__\": a, [\"__proto__\"]: b, __proto__, get: 1, set: 2, async: 3, get});", .expected = script("sloppy", "", "", "(expression (paren (object (proto (identifier a)) (property (computed (string \"__proto__\")) (identifier b)) (shorthand __proto__) (property \"get\" (number 1)) (property \"set\" (number 2)) (property \"async\" (number 3)) (shorthand get))))") },
    .{ .name = "T20", .source = "(function () {}); (function g(a,) { \"use strict\"; }); x = function () { return 1; };", .expected = script("sloppy", "", "", "(expression (paren (function-expression - (params) sloppy (var-declared-names) (functions-to-initialize)))) (expression (paren (function-expression g (params a) strict (var-declared-names) (functions-to-initialize) (expression (string \"use strict\"))))) (expression (assign = (identifier x) (function-expression - (params) sloppy (var-declared-names) (functions-to-initialize) (return (number 1)))))") },
    .{ .name = "T21", .source =
    \\"\0\b\f\n\r\t\v\x41\u0042\u{43}\u{1F600}\uD800\'\"\\a\
    \\b";
    , .expected = script("sloppy", "", "",
        \\(expression (string "\u0000\u0008\u000C\u000A\u000D\u0009\u000BABC\uD83D\uDE00\uD800'\"\\ab"))
    ) },
    .{ .name = "T22", .source =
    \\"\101\08\8\9\400";
    , .expected = script("sloppy", "", "",
        \\(expression (string "A\u0000889 0"))
    ) },
    .{ .name = "T23", .source = "\"a\u{2028}b\"; \"a\\\u{2028}b\"; \"\\u{0000000000041}\";", .expected = script("sloppy", "", "",
        \\(expression (string "a\u2028b")) (expression (string "ab")) (expression (string "A"))
    ) },
    .{ .name = "T24", .source = "0; 1.5; .5; 5.; 1e3; 1E-3; 0x1F; 0o17; 0b101; 010; 08; 09.5; 1_000; 0x1_F; 1e1_0; 9007199254740993; 1e400; 0.1; 0.0000001;", .expected = script("sloppy", "", "", "(expression (number 0)) (expression (number 1.5)) (expression (number 0.5)) (expression (number 5)) (expression (number 1000)) (expression (number 0.001)) (expression (number 31)) (expression (number 15)) (expression (number 5)) (expression (number 8)) (expression (number 8)) (expression (number 9.5)) (expression (number 1000)) (expression (number 31)) (expression (number 10000000000)) (expression (number 9007199254740992)) (expression (number Infinity)) (expression (number 0.1)) (expression (number 1e-7))") },
    .{ .name = "T25", .source =
    \\var \u0061b\u{63};
    , .expected = script("sloppy", "abc", "", "(var (abc))") },
    .{ .name = "T26", .source = "/* a */ a /* b\n */ b // c\n<!-- d\n--> e\n c", .expected = script("sloppy", "", "", "(expression (identifier a)) (expression (identifier b)) (expression (identifier c))") },
    .{ .name = "T27", .source = "x = 1 <!-- y", .expected = script("sloppy", "", "", "(expression (assign = (identifier x) (number 1)))") },
    .{ .name = "T28", .source = "a /* x */ --> b", .expected = script("sloppy", "", "", "(expression (binary > (postfix -- (identifier a)) (identifier b)))") },
    .{ .name = "T29 first", .source = "--> b", .expected = script("sloppy", "", "", "") },
    .{ .name = "T29 second", .source = "  --> b", .expected = script("sloppy", "", "", "") },
    .{ .name = "T29 third", .source = "/* */ --> b", .expected = script("sloppy", "", "", "") },
    .{ .name = "T29 fourth", .source = "a /*\n*/ --> b", .expected = script("sloppy", "", "", "(expression (identifier a))") },
    .{ .name = "T30", .source = "#!anything\nx", .expected = script("sloppy", "", "", "(expression (identifier x))") },
    .{ .name = "T31 white space", .source = "a\t\x0B\x0C \u{00A0}\u{FEFF}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}= 1", .expected = script("sloppy", "", "", "(expression (assign = (identifier a) (number 1)))") },
    .{ .name = "T31 LS", .source = "a\u{2028}b", .expected = script("sloppy", "", "", "(expression (identifier a)) (expression (identifier b))") },
    .{ .name = "T31 PS", .source = "a\u{2029}b", .expected = script("sloppy", "", "", "(expression (identifier a)) (expression (identifier b))") },
    .{ .name = "T31 CR LF", .source = "a\r\nb", .expected = script("sloppy", "", "", "(expression (identifier a)) (expression (identifier b))") },
    .{ .name = "T31 CR", .source = "a\rb", .expected = script("sloppy", "", "", "(expression (identifier a)) (expression (identifier b))") },
    // Amendment 1 of the contract corrects this row: the argument list of `a⏎(b)` holds `b` itself.
    .{ .name = "T32 call", .source = "a\n(b)", .expected = script("sloppy", "", "", "(expression (call (identifier a) (identifier b)))") },
    .{ .name = "T32 update", .source = "x\n++y", .expected = script("sloppy", "", "", "(expression (identifier x)) (expression (prefix ++ (identifier y)))") },
    .{ .name = "T32 do-while", .source = "do ; while (0) x", .expected = script("sloppy", "", "", "(do-while (empty) (number 0)) (expression (identifier x))") },
    .{ .name = "T32 comment", .source = "var a = 1 /*\n*/ b = 2", .expected = script("sloppy", "a", "", "(var (a (number 1))) (expression (assign = (identifier b) (number 2)))") },
    .{ .name = "T32 division", .source = "a\n/b/g", .expected = script("sloppy", "", "", "(expression (binary / (binary / (identifier a) (identifier b)) (identifier g)))") },
    .{ .name = "T32 break", .source = "l: while (1) { break\nl }", .expected = script("sloppy", "", "", "(labelled l (while (number 1) (block (break) (expression (identifier l)))))") },
    .{ .name = "T32 block", .source = "{ 1\n2 } 3", .expected = script("sloppy", "", "", "(block (expression (number 1)) (expression (number 2))) (expression (number 3))") },
    .{ .name = "T32 return", .source = "function f() { return\n1 }", .expected = script("sloppy", "f", "f#1", "(function-declaration #1 f (params) sloppy (var-declared-names) (functions-to-initialize) (return) (expression (number 1)))") },
    .{ .name = "T33", .source = "if (a) if (b) c; else d; l1: l2: for (;;) { continue l1; } a: { b: { break a; } } switch (x) { case 1: a; case 2: default: b; case 3: } try { a } catch (e) { var e = 1; } finally { b } try {} catch {} try {} finally {} throw a; debugger; ;", .expected = script("sloppy", "e", "", "(if (identifier a) (if (identifier b) (expression (identifier c)) (expression (identifier d)))) (labelled l1 (labelled l2 (for - - - (block (continue l1))))) (labelled a (block (labelled b (block (break a))))) (switch (identifier x) (case (number 1) (expression (identifier a))) (case (number 2)) (default (expression (identifier b))) (case (number 3))) (try (block (expression (identifier a))) (catch e (block (var (e (number 1))))) (finally (block (expression (identifier b))))) (try (block) (catch - (block))) (try (block) (finally (block))) (throw (identifier a)) (debugger) (empty)") },
    .{ .name = "T34", .source = "do x++; while (x < 3) for (var i = 0, j; i < 1; i++) continue; for (i = 0; ; ) break; while (a) {}", .expected = script("sloppy", "i j", "", "(do-while (expression (postfix ++ (identifier x))) (binary < (identifier x) (number 3))) (for (var (i (number 0)) (j)) (binary < (identifier i) (number 1)) (postfix ++ (identifier i)) (continue)) (for (assign = (identifier i) (number 0)) - - (break)) (while (identifier a) (block))") },
    .{ .name = "T35", .source = "f() = 1; f() += 1; f()++; --f(); eval = 1; arguments = 2; delete (x); (a) = 1; ((a.b)) = 2;", .expected = script("sloppy", "", "", "(expression (assign = (call (identifier f)) (number 1))) (expression (assign += (call (identifier f)) (number 1))) (expression (postfix ++ (call (identifier f)))) (expression (prefix -- (call (identifier f)))) (expression (assign = (identifier eval) (number 1))) (expression (assign = (identifier arguments) (number 2))) (expression (unary delete (paren (identifier x)))) (expression (assign = (paren (identifier a)) (number 1))) (expression (assign = (paren (paren (member (identifier a) \"b\"))) (number 2)))") },
    .{ .name = "T36", .source =
    \\var yield, await, let, static, async, of, get, set; let = 1; let(1); yield = 1; await = 2; let: 1; l\u0065t = 1; async
    \\function f() {}
    , .expected = script("sloppy", "yield await let static async of get set f", "f#1", "(var (yield) (await) (let) (static) (async) (of) (get) (set)) (expression (assign = (identifier let) (number 1))) (expression (call (identifier let) (number 1))) (expression (assign = (identifier yield) (number 1))) (expression (assign = (identifier await) (number 2))) (labelled let (expression (number 1))) (expression (assign = (identifier let) (number 1))) (expression (identifier async)) (function-declaration #1 f (params) sloppy (var-declared-names) (functions-to-initialize))") },
    .{ .name = "T37", .source = "function f(arguments) { return arguments; } function g() { function arguments() {} return arguments; } arguments;", .expected = script("sloppy", "f g", "f#1 g#2", "(function-declaration #1 f (params arguments) sloppy (var-declared-names) (functions-to-initialize) (return (identifier arguments))) (function-declaration #2 g (params) sloppy (var-declared-names arguments) (functions-to-initialize arguments#3) (function-declaration #3 arguments (params) sloppy (var-declared-names) (functions-to-initialize)) (return (identifier arguments))) (expression (identifier arguments))") },
    .{ .name = "T38", .source = "a: while (1) { (function () { a: ; }); break a; }", .expected = script("sloppy", "", "", "(labelled a (while (number 1) (block (expression (paren (function-expression - (params) sloppy (var-declared-names) (functions-to-initialize) (labelled a (empty))))) (break a))))") },
    .{ .name = "T39", .source = "\"use strict\"; var a = function () {}; function f() {}", .expected = script("strict", "a f", "f#1", "(expression (string \"use strict\")) (var (a (function-expression - (params) strict (var-declared-names) (functions-to-initialize)))) (function-declaration #1 f (params) strict (var-declared-names) (functions-to-initialize))") },
    .{ .name = "T40", .source = "try {} catch (e) { var e; }", .expected = script("sloppy", "e", "", "(try (block) (catch e (block (var (e)))))") },
    .{ .name = "T41", .source = "debugger; ;", .expected = script("sloppy", "", "", "(debugger) (empty)") },
};

const e_cases = [_]Case{
    .{ .name = "E1", .source = "var 1;", .expected = "syntax-error unexpected_token @4" },
    .{ .name = "E2", .source = "a b", .expected = "syntax-error unexpected_token @2" },
    .{ .name = "E3", .source = "if (a", .expected = "syntax-error unexpected_end @5" },
    .{ .name = "E4", .source = "a @ b", .expected = "syntax-error invalid_character @2" },
    .{ .name = "E5", .source = "a \x01 b", .expected = "syntax-error invalid_character @2" },
    .{ .name = "E6", .source = "a \\ b", .expected = "syntax-error invalid_character @2" },
    .{ .name = "E7", .source = "\"abc", .expected = "syntax-error unterminated_string @0" },
    .{ .name = "E8", .source = "\"a\nb\"", .expected = "syntax-error unterminated_string @0" },
    .{ .name = "E9", .source = "\"a\rb\"", .expected = "syntax-error unterminated_string @0" },
    .{ .name = "E10", .source = "/* a", .expected = "syntax-error unterminated_comment @0" },
    .{ .name = "E11", .source =
    \\"\x4"
    , .expected = "syntax-error invalid_escape @1" },
    .{ .name = "E12", .source =
    \\"\u12"
    , .expected = "syntax-error invalid_escape @1" },
    .{ .name = "E13", .source =
    \\"\u{110000}"
    , .expected = "syntax-error invalid_escape @1" },
    .{ .name = "E14", .source =
    \\"\u{}"
    , .expected = "syntax-error invalid_escape @1" },
    .{ .name = "E15", .source =
    \\\u0030abc
    , .expected = "syntax-error invalid_escape @0" },
    .{ .name = "E16", .source =
    \\a\u002Db
    , .expected = "syntax-error invalid_escape @1" },
    .{ .name = "E17 3in []", .source = "3in []", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 0x", .source = "0x", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 0b12", .source = "0b12", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1__0", .source = "1__0", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1_", .source = "1_", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 0_1", .source = "0_1", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 08_1", .source = "08_1", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1e", .source = "1e", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1e_1", .source = "1e_1", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 0x_1", .source = "0x_1", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1.a", .source = "1.a", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1._5", .source = "1._5", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1_.5", .source = "1_.5", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 1.5n", .source = "1.5n", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 01n", .source = "01n", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E17 0x1g", .source = "0x1g", .expected = "syntax-error invalid_numeric_literal @0" },
    .{ .name = "E18", .source = "07.5", .expected = "syntax-error unexpected_token @2" },
    .{ .name = "E19", .source = "\"use strict\"; 010;", .expected = "syntax-error strict_octal @14" },
    .{ .name = "E20", .source = "\"use strict\"; 08;", .expected = "syntax-error strict_octal @14" },
    .{ .name = "E21", .source = "\"use strict\"; 09.5", .expected = "syntax-error strict_octal @14" },
    .{ .name = "E22", .source = "function f(a) { \"use strict\"; 010 }", .expected = "syntax-error strict_octal @30" },
    .{ .name = "E23", .source =
    \\"use strict"; "\08";
    , .expected = "syntax-error strict_octal_escape @15" },
    .{ .name = "E24", .source =
    \\"use strict"; "\8";
    , .expected = "syntax-error strict_octal_escape @15" },
    .{ .name = "E25", .source =
    \\function f() { "\07"; "use strict"; }
    , .expected = "syntax-error strict_octal_escape @16" },
    .{ .name = "E26", .source =
    \\"\07"; "use strict";
    , .expected = "syntax-error strict_octal_escape @1" },
    .{ .name = "E27", .source = "var if;", .expected = "syntax-error reserved_word @4" },
    .{ .name = "E28", .source = "var enum;", .expected = "syntax-error reserved_word @4" },
    .{ .name = "E29", .source =
    \\var v\u0061r;
    , .expected = "syntax-error reserved_word @4" },
    .{ .name = "E30", .source =
    \\\u0074his
    , .expected = "syntax-error reserved_word @0" },
    .{ .name = "E31", .source = "({if})", .expected = "syntax-error reserved_word @2" },
    .{ .name = "E32", .source =
    \\({\u0069f})
    , .expected = "syntax-error reserved_word @2" },
    .{ .name = "E33", .source = "\"use strict\"; var let;", .expected = "syntax-error strict_reserved_word @18" },
    .{ .name = "E34", .source = "\"use strict\"; var yield;", .expected = "syntax-error strict_reserved_word @18" },
    .{ .name = "E35", .source = "\"use strict\"; implements = 1;", .expected = "syntax-error strict_reserved_word @14" },
    .{ .name = "E36", .source =
    \\"use strict"; l\u0065t = 1;
    , .expected = "syntax-error strict_reserved_word @14" },
    .{ .name = "E37", .source = "\"use strict\"; let: 1", .expected = "syntax-error strict_reserved_word @14" },
    .{ .name = "E38", .source = "function yield() { \"use strict\"; }", .expected = "syntax-error strict_reserved_word @9" },
    .{ .name = "E39", .source = "\"use strict\"; var eval;", .expected = "syntax-error strict_eval_arguments @18" },
    .{ .name = "E40", .source = "\"use strict\"; arguments = 1;", .expected = "syntax-error strict_eval_arguments @14" },
    .{ .name = "E41", .source = "\"use strict\"; eval++;", .expected = "syntax-error strict_eval_arguments @14" },
    .{ .name = "E42", .source = "\"use strict\"; function arguments() {}", .expected = "syntax-error strict_eval_arguments @23" },
    .{ .name = "E43", .source = "function eval() { \"use strict\"; }", .expected = "syntax-error strict_eval_arguments @9" },
    .{ .name = "E44", .source = "\"use strict\"; try {} catch (eval) {}", .expected = "syntax-error strict_eval_arguments @28" },
    .{ .name = "E45", .source = "\"use strict\"; function f(eval) {}", .expected = "syntax-error strict_eval_arguments @25" },
    .{ .name = "E46", .source = "1 = 2", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "E47", .source = "a + 1 = 2", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "E48", .source = "this = 1", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "E49", .source = "(a, b) = 1", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "E50", .source = "++1", .expected = "syntax-error invalid_assignment_target @2" },
    .{ .name = "E51", .source = "1++", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "E52", .source = "new f() = 1", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "E53", .source = "typeof a = 1", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "E54", .source = "\"use strict\"; f() = 1;", .expected = "syntax-error invalid_assignment_target @14" },
    .{ .name = "E55", .source = "\"use strict\"; f()++;", .expected = "syntax-error invalid_assignment_target @14" },
    .{ .name = "E56", .source = "\"use strict\"; f() += 1;", .expected = "syntax-error invalid_assignment_target @14" },
    .{ .name = "E57", .source = "\"use strict\"; delete x;", .expected = "syntax-error strict_delete_identifier @14" },
    .{ .name = "E58", .source = "\"use strict\"; delete (x);", .expected = "syntax-error strict_delete_identifier @14" },
    .{ .name = "E59", .source = "\"use strict\"; delete ((x));", .expected = "syntax-error strict_delete_identifier @14" },
    .{ .name = "E60", .source = "function f() { \"use strict\"; delete x; }", .expected = "syntax-error strict_delete_identifier @29" },
    .{ .name = "E61", .source = "\"use strict\"; with (a) {}", .expected = "syntax-error strict_with @14" },
    .{ .name = "E62", .source = "\"use strict\"; if (a) function f() {}", .expected = "syntax-error function_declaration_position @21" },
    .{ .name = "E63", .source = "\"use strict\"; l: function f() {}", .expected = "syntax-error function_declaration_position @17" },
    .{ .name = "E64", .source = "while (a) function f() {}", .expected = "syntax-error function_declaration_position @10" },
    .{ .name = "E65", .source = "while (0) l: function f() {}", .expected = "syntax-error function_declaration_position @13" },
    .{ .name = "E66", .source = "do function f() {} while (0)", .expected = "syntax-error function_declaration_position @3" },
    .{ .name = "E67", .source = "if (a) l: function f() {}", .expected = "syntax-error function_declaration_position @10" },
    .{ .name = "E68", .source = "a: a: ;", .expected = "syntax-error duplicate_label @3" },
    .{ .name = "E69", .source = "a: { a: ; }", .expected = "syntax-error duplicate_label @5" },
    .{ .name = "E70", .source = "a: { break b; }", .expected = "syntax-error undefined_break_target @11" },
    .{ .name = "E71", .source = "break a;", .expected = "syntax-error undefined_break_target @6" },
    .{ .name = "E72", .source = "a: { while (1) { continue a; } }", .expected = "syntax-error undefined_continue_target @26" },
    .{ .name = "E73", .source = "a: while (1) { continue b; }", .expected = "syntax-error undefined_continue_target @24" },
    .{ .name = "E74", .source = "break;", .expected = "syntax-error break_outside @0" },
    .{ .name = "E75", .source = "while (1) { (function () { break; }); }", .expected = "syntax-error break_outside @27" },
    .{ .name = "E76", .source = "continue;", .expected = "syntax-error continue_outside @0" },
    .{ .name = "E77", .source = "switch (1) { case 1: continue; }", .expected = "syntax-error continue_outside @21" },
    .{ .name = "E78", .source = "return;", .expected = "syntax-error return_outside_function @0" },
    .{ .name = "E79", .source = "\"use strict\"; function f(a, a) {}", .expected = "syntax-error duplicate_parameter @28" },
    .{ .name = "E80", .source = "function f(a, a) { \"use strict\"; }", .expected = "syntax-error duplicate_parameter @14" },
    .{ .name = "E81", .source = "({__proto__: 1, __proto__: 2})", .expected = "syntax-error duplicate_proto @16" },
    .{ .name = "E82", .source = "({__proto__: 1, \"__proto__\": 2})", .expected = "syntax-error duplicate_proto @16" },
    .{ .name = "E83", .source = "({a = 1})", .expected = "syntax-error cover_initialized_name @2" },
    .{ .name = "E84", .source = "-a ** 2", .expected = "syntax-error unary_before_exponent @3" },
    .{ .name = "E85", .source = "typeof a ** 2", .expected = "syntax-error unary_before_exponent @9" },
    .{ .name = "E86", .source = "!a ** 2", .expected = "syntax-error unary_before_exponent @3" },
    .{ .name = "E87", .source = "#x", .expected = "syntax-error private_identifier @0" },
    .{ .name = "E88", .source = "a.#x", .expected = "syntax-error private_identifier @2" },
    .{ .name = "E89", .source = " #!x", .expected = "syntax-error invalid_character @1" },
    .{ .name = "E90", .source = "throw\n1", .expected = "syntax-error throw_line_terminator @0" },
    .{ .name = "E91", .source = "{ 1 2 } 3", .expected = "syntax-error unexpected_token @4" },
    .{ .name = "E92", .source = "for (a; b\n) c", .expected = "syntax-error unexpected_token @10" },
    .{ .name = "E93", .source = "if (a)\nelse b", .expected = "syntax-error unexpected_token @7" },
    .{ .name = "E94", .source = "a\n++", .expected = "syntax-error unexpected_end @4" },
    .{ .name = "E95", .source = "function () {}", .expected = "syntax-error unexpected_token @9" },
    // Revision 1: `( )` and `( Expression , )` continue only with `=>` (13.2), so the error is at the next token.
    .{ .name = "E96", .source = "()", .expected = "syntax-error unexpected_end @2" },
    .{ .name = "E96a", .source = "() + 1", .expected = "syntax-error unexpected_token @3" },
    .{ .name = "E96b", .source = "(a,)", .expected = "syntax-error unexpected_end @4" },
    .{ .name = "E96c", .source = "(a,) + 1", .expected = "syntax-error unexpected_token @5" },
    .{ .name = "E97", .source = "function f(,) {}", .expected = "syntax-error unexpected_token @11" },
    .{ .name = "E98", .source = "try {}", .expected = "syntax-error unexpected_end @6" },
    .{ .name = "E99", .source = "switch (a) { default: default: }", .expected = "syntax-error unexpected_token @22" },
    // The keyword is built by concatenation, so that FP-0011 case 20 does not find it in this file.
    .{ .name = "E100", .source = "ex" ++ "port var a;", .expected = "syntax-error unexpected_token @0" },
    .{ .name = "E101", .source = "x = 1; --> y", .expected = "syntax-error unexpected_token @9" },
    .{ .name = "E102", .source = "@dec class A {}", .expected = "syntax-error invalid_character @0" },
};

const u_cases = [_]Case{
    .{ .name = "U1", .source = "let x;", .expected = "unsupported lexical_declaration @0" },
    .{ .name = "U2", .source = "const x = 1;", .expected = "unsupported lexical_declaration @0" },
    .{ .name = "U3", .source = "let [a] = b;", .expected = "unsupported lexical_declaration @0" },
    .{ .name = "U4", .source = "let\nx", .expected = "unsupported lexical_declaration @0" },
    .{ .name = "U5", .source = "for (let i;;) {}", .expected = "unsupported lexical_declaration @5" },
    .{ .name = "U6", .source = "if (a) { let x; }", .expected = "unsupported lexical_declaration @9" },
    .{ .name = "U7", .source = "using x = y;", .expected = "unsupported using_declaration @0" },
    .{ .name = "U8", .source = "class A {}", .expected = "unsupported class @0" },
    .{ .name = "U9", .source = "(class {})", .expected = "unsupported class @1" },
    .{ .name = "U10", .source = "function* g() {}", .expected = "unsupported generator @8" },
    .{ .name = "U11", .source = "(function* () {})", .expected = "unsupported generator @9" },
    .{ .name = "U12", .source = "async function f() {}", .expected = "unsupported async_function @0" },
    .{ .name = "U13", .source = "async x => x", .expected = "unsupported async_function @0" },
    .{ .name = "U14", .source = "async (x) => x", .expected = "unsupported async_function @0" },
    .{ .name = "U15", .source = "(async function () {})", .expected = "unsupported async_function @1" },
    .{ .name = "U16", .source = "x => x", .expected = "unsupported arrow_function @2" },
    .{ .name = "U17", .source = "(a, b) => a", .expected = "unsupported arrow_function @7" },
    .{ .name = "U18", .source = "() => 1", .expected = "unsupported arrow_function @3" },
    .{ .name = "U19", .source = "(a, ...b) => 1", .expected = "unsupported arrow_function @4" },
    .{ .name = "U20", .source = "`a`", .expected = "unsupported template @0" },
    .{ .name = "U21", .source = "f`a`", .expected = "unsupported template @1" },
    .{ .name = "U22", .source = "/a/", .expected = "unsupported regular_expression @0" },
    .{ .name = "U23", .source = "a = /b/g", .expected = "unsupported regular_expression @4" },
    .{ .name = "U24", .source = "if (a) /x/.test(b)", .expected = "unsupported regular_expression @7" },
    .{ .name = "U25", .source = "[1]", .expected = "unsupported array_literal @0" },
    .{ .name = "U26", .source = "a = []", .expected = "unsupported array_literal @4" },
    .{ .name = "U27", .source = "1n", .expected = "unsupported bigint_literal @0" },
    .{ .name = "U28", .source = "0x1Fn", .expected = "unsupported bigint_literal @0" },
    .{ .name = "U29", .source = "f(...a)", .expected = "unsupported spread @2" },
    .{ .name = "U30", .source = "new F(...a)", .expected = "unsupported spread @6" },
    .{ .name = "U31", .source = "({a() {}})", .expected = "unsupported method_definition @3" },
    .{ .name = "U32 get", .source = "({get a() {}})", .expected = "unsupported method_definition @2" },
    .{ .name = "U32 set", .source = "({set a(v) {}})", .expected = "unsupported method_definition @2" },
    .{ .name = "U32 generator", .source = "({*g() {}})", .expected = "unsupported method_definition @2" },
    .{ .name = "U32 async", .source = "({async f() {}})", .expected = "unsupported method_definition @2" },
    .{ .name = "U33", .source = "({...a})", .expected = "unsupported object_spread @2" },
    .{ .name = "U34", .source = "var {a} = b;", .expected = "unsupported destructuring_binding @4" },
    .{ .name = "U35", .source = "var [a] = b;", .expected = "unsupported destructuring_binding @4" },
    .{ .name = "U36", .source = "function f({a}) {}", .expected = "unsupported destructuring_binding @11" },
    .{ .name = "U37", .source = "try {} catch ([e]) {}", .expected = "unsupported destructuring_binding @14" },
    .{ .name = "U38", .source = "({a} = b)", .expected = "unsupported destructuring_assignment @5" },
    .{ .name = "U39", .source = "({a = 1} = b)", .expected = "unsupported destructuring_assignment @9" },
    .{ .name = "U40", .source = "function f(a = 1) {}", .expected = "unsupported default_parameter @13" },
    .{ .name = "U41", .source = "function f(...a) {}", .expected = "unsupported rest_parameter @11" },
    .{ .name = "U42 member", .source = "a?.b", .expected = "unsupported optional_chain @1" },
    .{ .name = "U42 index", .source = "a?.[0]", .expected = "unsupported optional_chain @1" },
    .{ .name = "U42 call", .source = "a?.()", .expected = "unsupported optional_chain @1" },
    .{ .name = "U43", .source = "a ?? b", .expected = "unsupported coalesce @2" },
    .{ .name = "U44 and", .source = "a &&= b", .expected = "unsupported logical_assignment @2" },
    .{ .name = "U44 coalesce", .source = "a ??= b", .expected = "unsupported logical_assignment @2" },
    .{ .name = "U44 or", .source = "a ||= b", .expected = "unsupported logical_assignment @2" },
    .{ .name = "U45", .source = "function f() { new.target }", .expected = "unsupported new_target @15" },
    .{ .name = "U46", .source = "super.x", .expected = "unsupported super @0" },
    .{ .name = "U47 declaration", .source = "import x from \"y\"", .expected = "unsupported import @0" },
    .{ .name = "U47 call", .source = "import(\"y\")", .expected = "unsupported import @0" },
    .{ .name = "U47 meta", .source = "import.meta", .expected = "unsupported import @0" },
    .{ .name = "U48 expression", .source = "for (a in b) {}", .expected = "unsupported for_in @7" },
    .{ .name = "U48 var", .source = "for (var a in b) {}", .expected = "unsupported for_in @11" },
    .{ .name = "U48 initializer", .source = "for (var a = 1 in b) {}", .expected = "unsupported for_in @15" },
    .{ .name = "U49 expression", .source = "for (a of b) {}", .expected = "unsupported for_of @7" },
    .{ .name = "U49 var", .source = "for (var a of b) {}", .expected = "unsupported for_of @11" },
    .{ .name = "U50", .source = "for await (x of y) {}", .expected = "unsupported for_await @4" },
    .{ .name = "U51", .source = "with (a) {}", .expected = "unsupported with @0" },
    .{ .name = "U52 block", .source = "{ function f() {} }", .expected = "unsupported block_function_declaration @2" },
    .{ .name = "U52 if", .source = "if (a) function f() {}", .expected = "unsupported block_function_declaration @7" },
    .{ .name = "U52 label", .source = "l: function f() {}", .expected = "unsupported block_function_declaration @3" },
    .{ .name = "U52 case", .source = "switch (a) { case 1: function f() {} }", .expected = "unsupported block_function_declaration @21" },
    .{ .name = "U52 strict block", .source = "\"use strict\"; { function f() {} }", .expected = "unsupported block_function_declaration @16" },
    .{ .name = "U53 raw", .source = "var \u{00E9};", .expected = "unsupported non_ascii_identifier @4" },
    .{ .name = "U53 escape", .source =
    \\var \u00e9;
    , .expected = "unsupported non_ascii_identifier @4" },
    .{ .name = "U53 joiner", .source =
    \\var a\u200C;
    , .expected = "unsupported non_ascii_identifier @5" },
    .{ .name = "U53 separator", .source = "var\u{180E}a;", .expected = "unsupported non_ascii_identifier @3" },
    .{ .name = "U54 reference", .source = "function f() { return arguments; }", .expected = "unsupported arguments_object @22" },
    .{ .name = "U54 var", .source = "function f() { var arguments; return arguments; }", .expected = "unsupported arguments_object @37" },
    .{ .name = "U54 nested", .source = "function f() { return function () { return arguments; }; }", .expected = "unsupported arguments_object @43" },
};

const detection_cases = [_]Case{
    .{ .name = "class after an assignment error", .source = "1 = 2; class A {}", .expected = "syntax-error invalid_assignment_target @0" },
    .{ .name = "assignment error after class", .source = "class A {}; 1 = 2", .expected = "unsupported class @0" },
    .{ .name = "assignment error before the end of the body", .source = "function f() { return arguments; 1 = 2; }", .expected = "syntax-error invalid_assignment_target @33" },
    .{ .name = "default parameter before the strict duplicate", .source = "function f(a = 1, a) { \"use strict\"; }", .expected = "unsupported default_parameter @13" },
};

/// Decodes `text` as UTF-8, parses it with `options`, and returns the outcome line.
fn outcomeOf(gpa: Allocator, text: []const u8, options: Options) ![]u8 {
    var source = try web_string.WebString.fromUtf8(gpa, text);
    defer source.deinit(gpa);
    return outcomeOfUnits(gpa, source.units, options);
}

fn outcomeOfUnits(gpa: Allocator, units: []const u16, options: Options) ![]u8 {
    var parse = try parseScript(gpa, units, options);
    defer parse.deinit();
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try writeOutcome(&parse, &out.writer);
    return out.toOwnedSlice();
}

fn caseNamed(name: []const u8) Case {
    for (t_cases) |case| {
        if (std.mem.eql(u8, case.name, name)) return case;
    }
    unreachable;
}

fn expectCases(cases: []const Case) !void {
    var failures: usize = 0;
    for (cases) |case| {
        const actual = try outcomeOf(testing.allocator, case.source, .{});
        defer testing.allocator.free(actual);
        if (!std.mem.eql(u8, case.expected, actual)) {
            std.debug.print("case {s}\nexpected: {s}\nactual:   {s}\n", .{ case.name, case.expected, actual });
            failures += 1;
        }
    }
    if (failures != 0) return error.TestExpectedEqual;
}

test "FP-0082 case 1: writeCodeTable writes the frozen code tables" {
    const expected =
        \\unsupported|lexical_declaration|14.3.1|FP-0086
        \\unsupported|block_function_declaration|14.2,14.12,B.3.1,B.3.2,B.3.3|FP-0086
        \\unsupported|using_declaration|14.3.1|FP-0097
        \\unsupported|array_literal|13.2.4|FP-0087
        \\unsupported|arguments_object|10.2.11,10.4.4|FP-0087
        \\unsupported|for_in|14.7.5,B.3.5|FP-0087
        \\unsupported|for_of|14.7.5|FP-0088
        \\unsupported|spread|13.3.8|FP-0088
        \\unsupported|object_spread|13.2.5|FP-0088
        \\unsupported|destructuring_binding|14.3.3|FP-0088
        \\unsupported|destructuring_assignment|13.15.5|FP-0088
        \\unsupported|default_parameter|15.1|FP-0088
        \\unsupported|rest_parameter|15.1|FP-0088
        \\unsupported|method_definition|15.4|FP-0089
        \\unsupported|class|15.7|FP-0089
        \\unsupported|super|13.3.7|FP-0089
        \\unsupported|new_target|13.3.12|FP-0089
        \\unsupported|arrow_function|15.3|FP-0090
        \\unsupported|template|12.9.6,13.2.8,13.3.11|FP-0090
        \\unsupported|optional_chain|13.3.9|FP-0090
        \\unsupported|coalesce|13.13|FP-0090
        \\unsupported|logical_assignment|13.15|FP-0090
        \\unsupported|generator|15.5,15.6|FP-0091
        \\unsupported|async_function|15.8,15.9|FP-0091
        \\unsupported|for_await|14.7.5|FP-0091
        \\unsupported|import|16.2.2,13.3.10,13.3.12|FP-0092
        \\unsupported|regular_expression|12.9.5,13.2.7|FP-0093
        \\unsupported|bigint_literal|12.9.3|FP-0094
        \\unsupported|non_ascii_identifier|12.7.1|FP-0095
        \\unsupported|with|14.11|FP-0096
        \\syntax-error|unexpected_token|5.1.4,12.10
        \\syntax-error|unexpected_end|5.1.4,12.10
        \\syntax-error|invalid_character|12.6
        \\syntax-error|unterminated_string|12.9.4
        \\syntax-error|unterminated_comment|12.4
        \\syntax-error|invalid_escape|12.9.4,12.7.1.1
        \\syntax-error|invalid_numeric_literal|12.9.3
        \\syntax-error|strict_octal|12.9.3.1
        \\syntax-error|strict_octal_escape|12.9.4.1
        \\syntax-error|reserved_word|13.1.1,12.7.2
        \\syntax-error|strict_reserved_word|13.1.1
        \\syntax-error|strict_eval_arguments|13.1.1,8.6.4,15.2.1
        \\syntax-error|invalid_assignment_target|13.15.1,13.4.1,8.6.4
        \\syntax-error|strict_delete_identifier|13.5.1.1
        \\syntax-error|strict_with|14.11.1
        \\syntax-error|function_declaration_position|14.6.1,14.7.2.1,14.7.3.1,14.7.4.1,14.13.1
        \\syntax-error|duplicate_label|8.3.1,15.2.1,16.1.1
        \\syntax-error|undefined_break_target|8.3.2,15.2.1,16.1.1
        \\syntax-error|undefined_continue_target|8.3.3,15.2.1,16.1.1
        \\syntax-error|break_outside|14.9.1
        \\syntax-error|continue_outside|14.8.1
        \\syntax-error|return_outside_function|14.10,16.1
        \\syntax-error|duplicate_parameter|15.1.1,15.2.1
        \\syntax-error|duplicate_proto|13.2.5.1
        \\syntax-error|cover_initialized_name|13.2.5.1
        \\syntax-error|unary_before_exponent|13.6
        \\syntax-error|private_identifier|16.1.1
        \\syntax-error|throw_line_terminator|14.14,12.10
        \\limit|depth
        \\limit|memory
        \\limit|source_length
        \\
    ;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeCodeTable(&out.writer);
    try testing.expectEqualStrings(expected, out.written());
}

test "FP-0082 case 2: each source produces exactly its syntax-tree dump" {
    try expectCases(&t_cases);
}

test "FP-0082 case 3: function nodes record their source ranges" {
    const gpa = testing.allocator;
    {
        const text = caseNamed("T20").source;
        var source = try web_string.WebString.fromUtf8(gpa, text);
        defer source.deinit(gpa);
        var parse = try parseScript(gpa, source.units, .{});
        defer parse.deinit();
        const tree = parse.outcome.script;
        const function = tree.statements[2].data.expression.data.assign.value.data.function;
        var range = try web_string.WebString.fromCodeUnits(gpa, source.units[function.source_start..function.source_end]);
        defer range.deinit(gpa);
        const utf8 = try range.toUtf8Alloc(gpa);
        defer gpa.free(utf8);
        try testing.expectEqualStrings("function () { return 1; }", utf8);
    }
    {
        const text = caseNamed("T9").source;
        var source = try web_string.WebString.fromUtf8(gpa, text);
        defer source.deinit(gpa);
        var parse = try parseScript(gpa, source.units, .{});
        defer parse.deinit();
        const function = parse.outcome.script.statements[0].data.function_declaration;
        try testing.expectEqual(@as(u32, 0), function.source_start);
        try testing.expectEqual(@as(u32, @intCast(source.units.len)), function.source_end);
    }
}

test "FP-0082 case 4: Number::toString of 100,000 random Numbers parses back to the same bits and text" {
    const gpa = testing.allocator;
    var prng: std.Random.DefaultPrng = .init(0x4650303132000001);
    const random = prng.random();
    var count: usize = 0;
    while (count < 100_000) {
        const bits = random.int(u64) & 0x7FFF_FFFF_FFFF_FFFF;
        const x: f64 = @bitCast(bits);
        if (!std.math.isFinite(x) or x == 0) continue;
        count += 1;
        var buffer: [number.max_string_units]u16 = undefined;
        const text = number.toString(x, &buffer);
        var parse = try parseScript(gpa, text, .{});
        defer parse.deinit();
        const statement = parse.outcome.script.statements[0];
        const value = statement.data.expression.data.number;
        try testing.expectEqual(bits, @as(u64, @bitCast(value)));
        var out: std.Io.Writer.Allocating = .init(gpa);
        defer out.deinit();
        try writeOutcome(&parse, &out.writer);
        var expected: std.Io.Writer.Allocating = .init(gpa);
        defer expected.deinit();
        try expected.writer.writeAll("(script sloppy (var-declared-names) (functions-to-initialize) (expression (number ");
        for (text) |unit| try expected.writer.writeByte(@intCast(unit));
        try expected.writer.writeAll(")))");
        try testing.expectEqualStrings(expected.written(), out.written());
    }
}

test "FP-0082 case 5: one string of the 65,536 escapes \\u0000 through \\uFFFF produces every code unit in order" {
    const gpa = testing.allocator;
    var source: std.ArrayList(u16) = .empty;
    defer source.deinit(gpa);
    try source.append(gpa, '"');
    var hex: [6]u8 = undefined;
    for (0..0x10000) |unit| {
        const escape = try std.fmt.bufPrint(&hex, "\\u{X:0>4}", .{unit});
        for (escape) |byte| try source.append(gpa, byte);
    }
    try source.append(gpa, '"');
    var parse = try parseScript(gpa, source.items, .{});
    defer parse.deinit();
    const units = parse.outcome.script.statements[0].data.expression.data.string;
    try testing.expectEqual(@as(usize, 0x10000), units.len);
    for (units, 0..) |unit, index| try testing.expectEqual(@as(u16, @intCast(index)), unit);
}

test "FP-0082 case 6: each source produces exactly its syntax error" {
    try expectCases(&e_cases);
}

test "FP-0082 case 7: each source produces exactly its unsupported outcome" {
    try expectCases(&u_cases);
}

test "FP-0082 case 8: the outcome is the first diagnostic in detection order" {
    try expectCases(&detection_cases);
}

/// The dump that the strict prefix gives a script whose sloppy dump is `dump`.
fn strictDump(gpa: Allocator, dump: []const u8) ![]u8 {
    const group = "(functions-to-initialize";
    const at = std.mem.indexOf(u8, dump, group).? + group.len;
    const close = std.mem.indexOfScalarPos(u8, dump, at, ')').? + 1;
    const head = dump["(script sloppy".len..close];
    std.debug.assert(std.mem.startsWith(u8, dump, "(script sloppy") or std.mem.startsWith(u8, dump, "(script strict"));
    const joined = try std.mem.concat(gpa, u8, &.{ "(script strict", head, " (expression (string \"use strict\"))", dump[close..] });
    defer gpa.free(joined);
    return std.mem.replaceOwned(u8, gpa, joined, ") sloppy (var-declared-names", ") strict (var-declared-names");
}

test "FP-0082 case 9: the strict prefix gives a strict script, a strict-mode syntax error, or an unsupported outcome" {
    const gpa = testing.allocator;
    const strict_codes = [_][]const u8{
        "strict_octal",                  "strict_octal_escape",      "strict_reserved_word",
        "strict_eval_arguments",         "strict_delete_identifier", "strict_with",
        "function_declaration_position", "duplicate_parameter",      "invalid_assignment_target",
    };
    var failures: usize = 0;
    for (t_cases) |case| {
        // Amendment 1: a HashbangComment is allowed only at the start of a Script (12.5), so T30 has its own row below.
        if (std.mem.eql(u8, case.name, "T30")) continue;
        const text = try std.mem.concat(gpa, u8, &.{ "\"use strict\";\n", case.source });
        defer gpa.free(text);
        const actual = try outcomeOf(gpa, text, .{});
        defer gpa.free(actual);
        const accepted = if (std.mem.startsWith(u8, actual, "(script ")) accepted: {
            const expected = try strictDump(gpa, case.expected);
            defer gpa.free(expected);
            break :accepted std.mem.eql(u8, expected, actual);
        } else if (std.mem.startsWith(u8, actual, "syntax-error ")) accepted: {
            const rest = actual["syntax-error ".len..];
            const name = rest[0..std.mem.indexOfScalar(u8, rest, ' ').?];
            for (strict_codes) |allowed| {
                if (std.mem.eql(u8, allowed, name)) break :accepted true;
            }
            break :accepted false;
        } else std.mem.startsWith(u8, actual, "unsupported ");
        if (!accepted) {
            std.debug.print("case {s}: {s}\n", .{ case.name, actual });
            failures += 1;
        }
    }
    if (failures != 0) return error.TestUnexpectedResult;
    const hashbang = try outcomeOf(gpa, "\"use strict\";\n" ++ "#!anything\nx", .{});
    defer gpa.free(hashbang);
    try testing.expectEqualStrings("syntax-error invalid_character @14", hashbang);
}

/// The pattern that `paintStack` writes below the stack pointer.
const stack_paint: usize = 0x5AFE_C0DE_5AFE_C0DE;
/// The stack that a depth case runs on.
const case_stack_size = 1024 * 1024;
/// The bytes below the thread's first frame that `paintStack` does not paint, which holds its own frame.
const paint_margin = 16 * 1024;

/// Writes `stack_paint` over the `length` bytes that end `paint_margin` bytes below `top`, from high to low addresses.
fn paintStack(top: usize, length: usize) void {
    var address = std.mem.alignBackward(usize, top - paint_margin, @alignOf(usize));
    const end = address - length;
    while (address > end) {
        address -= @sizeOf(usize);
        @as(*volatile usize, @ptrFromInt(address)).* = stack_paint;
    }
}

/// Returns the bytes from `top` to the lowest painted word that a later call overwrote.
fn stackUse(top: usize, length: usize) usize {
    const start = std.mem.alignBackward(usize, top - paint_margin, @alignOf(usize));
    var address = start - length;
    while (address < start) : (address += @sizeOf(usize)) {
        if (@as(*volatile usize, @ptrFromInt(address)).* != stack_paint) return top - address;
    }
    return 0;
}

const DepthRun = struct {
    source: []const u16,
    /// False when the outcome must be a script.
    limit: bool,
    failure: ?anyerror = null,
    stack_bytes: usize = 0,

    fn run(depth_run: *DepthRun) void {
        const top = @frameAddress();
        const paintable = case_stack_size - 2 * paint_margin;
        paintStack(top, paintable);
        depth_run.check() catch |err| {
            depth_run.failure = err;
        };
        depth_run.stack_bytes = stackUse(top, paintable);
    }

    fn check(depth_run: *DepthRun) !void {
        var parse = try parseScript(std.heap.page_allocator, depth_run.source, .{});
        defer parse.deinit();
        switch (parse.outcome) {
            .script => {
                if (depth_run.limit) return error.TestExpectedLimit;
                var discarding: std.Io.Writer.Discarding = .init(&.{});
                try writeOutcome(&parse, &discarding.writer);
            },
            .diagnostic => |diagnostic| switch (diagnostic) {
                .limit => |limit| {
                    if (!depth_run.limit or limit.code != .depth) return error.TestExpectedScript;
                },
                else => return error.TestUnexpectedDiagnostic,
            },
        }
    }
};

/// Parses `source` on a thread with a 1 MiB stack and returns the stack bytes that the run used.
fn runOnSmallStack(source: []const u16, limit: bool) !usize {
    var depth_run: DepthRun = .{ .source = source, .limit = limit };
    const thread = try std.Thread.spawn(.{ .stack_size = case_stack_size }, DepthRun.run, .{&depth_run});
    thread.join();
    if (depth_run.failure) |err| return err;
    // The run must stay inside the painted part of the 1 MiB stack.
    if (depth_run.stack_bytes >= case_stack_size - 2 * paint_margin) {
        std.debug.print("the run used at least {d} bytes of its 1 MiB stack\n", .{depth_run.stack_bytes});
        return error.TestStackExceeded;
    }
    return depth_run.stack_bytes;
}

fn repeatUnits(gpa: Allocator, parts: []const []const u8) ![]u16 {
    var units: std.ArrayList(u16) = .empty;
    errdefer units.deinit(gpa);
    for (parts) |part| for (part) |byte| try units.append(gpa, byte);
    return units.toOwnedSlice(gpa);
}

/// `open` repeated `count` times, then `middle`, then `close` repeated `count` times.
fn nested(gpa: Allocator, open: []const u8, middle: []const u8, close: []const u8, count: usize) ![]u16 {
    var units: std.ArrayList(u16) = .empty;
    errdefer units.deinit(gpa);
    for (0..count) |_| for (open) |byte| try units.append(gpa, byte);
    for (middle) |byte| try units.append(gpa, byte);
    for (0..count) |_| for (close) |byte| try units.append(gpa, byte);
    return units.toOwnedSlice(gpa);
}

fn joinedTerms(gpa: Allocator, terms: usize) ![]u16 {
    var units: std.ArrayList(u16) = .empty;
    errdefer units.deinit(gpa);
    for (0..terms) |index| {
        if (index != 0) try units.append(gpa, '+');
        try units.append(gpa, 'a');
    }
    return units.toOwnedSlice(gpa);
}

test "FP-0082 case 10: the depth bound holds at its boundaries on a 1 MiB stack" {
    const gpa = testing.allocator;
    const accepted_terms = try joinedTerms(gpa, 1022);
    defer gpa.free(accepted_terms);
    const limited_terms = try joinedTerms(gpa, 1023);
    defer gpa.free(limited_terms);
    const accepted_parens = try nested(gpa, "(", "a", ")", 1021);
    defer gpa.free(accepted_parens);
    const limited_parens = try nested(gpa, "(", "a", ")", 1022);
    defer gpa.free(limited_parens);
    const terms_stack = try runOnSmallStack(accepted_terms, false);
    _ = try runOnSmallStack(limited_terms, true);
    const parens_stack = try runOnSmallStack(accepted_parens, false);
    _ = try runOnSmallStack(limited_parens, true);
    std.debug.print("FP-0082 case 10: measured stack use {d} bytes for 1022 terms and {d} bytes for 1021 parentheses\n", .{ terms_stack, parens_stack });
}

test "FP-0082 case 11: inputs nested 100,000 times give limit depth on a 1 MiB stack" {
    const gpa = testing.allocator;
    const count = 100_000;
    const shapes = [_]struct { open: []const u8, close: []const u8 }{
        .{ .open = "(", .close = ")" },
        .{ .open = "!", .close = "" },
        .{ .open = "typeof ", .close = "" },
        .{ .open = "{", .close = "}" },
        .{ .open = "if (a) ", .close = "" },
        .{ .open = "(function(){", .close = "})" },
        .{ .open = "a(", .close = ")" },
        .{ .open = "a[", .close = "]" },
        .{ .open = "a?a:", .close = "" },
        .{ .open = "a=", .close = "" },
        .{ .open = "a**", .close = "" },
        .{ .open = "new ", .close = "" },
        .{ .open = "({a:", .close = "})" },
    };
    for (shapes) |shape| {
        const source = try nested(gpa, shape.open, "a", shape.close, count);
        defer gpa.free(source);
        _ = runOnSmallStack(source, true) catch |err| {
            std.debug.print("shape {s}\n", .{shape.open});
            return err;
        };
    }
    var labels: std.ArrayList(u16) = .empty;
    defer labels.deinit(gpa);
    var name: [16]u8 = undefined;
    for (0..count) |index| {
        const label = try std.fmt.bufPrint(&name, "l{d}:", .{index});
        for (label) |byte| try labels.append(gpa, byte);
    }
    try labels.append(gpa, 'a');
    _ = try runOnSmallStack(labels.items, true);
}

test "FP-0082 case 12: the memory and source-length limits, and a million statements under the defaults" {
    const gpa = testing.allocator;
    const statements = try repeatN(gpa, "a;", 10_000);
    defer gpa.free(statements);
    {
        var parse = try parseScript(gpa, statements, .{ .max_memory_bytes = 4096 });
        defer parse.deinit();
        try testing.expectEqual(LimitCode.memory, parse.outcome.diagnostic.limit.code);
    }
    {
        const actual = try outcomeOf(gpa, "var abcdefgh;", .{ .max_source_units = 10 });
        defer gpa.free(actual);
        try testing.expectEqualStrings("limit source_length @0", actual);
    }
    {
        const million = try repeatN(gpa, "a;", 1_000_000);
        defer gpa.free(million);
        var parse = try parseScript(gpa, million, .{});
        defer parse.deinit();
        try testing.expectEqual(@as(usize, 1_000_000), parse.outcome.script.statements.len);
    }
}

fn repeatN(gpa: Allocator, text: []const u8, count: usize) ![]u16 {
    const units = try gpa.alloc(u16, text.len * count);
    for (0..count) |index| {
        for (text, 0..) |byte, offset| units[index * text.len + offset] = byte;
    }
    return units;
}

fn parseAndWrite(gpa: Allocator, source: []const u16) !void {
    var parse = try parseScript(gpa, source, .{});
    defer parse.deinit();
    var discarding: std.Io.Writer.Discarding = .init(&.{});
    // A Discarding writer never fails, so the only possible error is an allocation failure of the write stack.
    writeOutcome(&parse, &discarding.writer) catch |err| switch (err) {
        error.WriteFailed => unreachable,
        error.OutOfMemory => |e| return e,
    };
}

test "FP-0082 case 13: every induced allocation failure returns error.OutOfMemory without a leak" {
    const gpa = testing.allocator;
    const text = try std.mem.join(gpa, "\n", &.{ caseNamed("T9").source, caseNamed("T11").source, caseNamed("T18").source, caseNamed("T21").source, caseNamed("T33").source });
    defer gpa.free(text);
    var source = try web_string.WebString.fromUtf8(gpa, text);
    defer source.deinit(gpa);
    try testing.checkAllAllocationFailures(gpa, parseAndWrite, .{source.units});
}

test "FP-0082 case 14: random sources, prefixes, and deletions yield outcomes without a panic or a leak" {
    const gpa = testing.allocator;
    const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
    const extra = [_]u16{ 0x000A, 0x000D, 0x2028, 0x00A0, 0xFEFF, 0xD800, 0xDC00, 0x00E9, 0x180E };
    var prng: std.Random.DefaultPrng = .init(0x4650303132000002);
    const random = prng.random();
    var source: [64]u16 = undefined;
    for (0..50_000) |_| {
        const length = random.uintLessThan(usize, 65);
        for (source[0..length]) |*unit| {
            const pick = random.uintLessThan(usize, alphabet.len + extra.len);
            unit.* = if (pick < alphabet.len) alphabet[pick] else extra[pick - alphabet.len];
        }
        try parseAndWrite(gpa, source[0..length]);
    }
    const groups = [_][]const Case{ &t_cases, &e_cases, &u_cases };
    for (groups) |group| for (group) |case| {
        var whole = try web_string.WebString.fromUtf8(gpa, case.source);
        defer whole.deinit(gpa);
        const units = whole.units;
        for (0..units.len + 1) |end| try parseAndWrite(gpa, units[0..end]);
        var deleted: std.ArrayList(u16) = .empty;
        defer deleted.deinit(gpa);
        for (0..units.len) |skip| {
            deleted.clearRetainingCapacity();
            try deleted.appendSlice(gpa, units[0..skip]);
            try deleted.appendSlice(gpa, units[skip + 1 ..]);
            try parseAndWrite(gpa, deleted.items);
        }
    };
}

test "FP-0082 revision 1 case 4: the duplicate-parameter check of 10,000 strict parameters makes at most 20,000 comparisons" {
    const gpa = testing.allocator;
    // The first function becomes strict through its own directive, and the second is strict when its parameters are read.
    const shapes = [_]struct { prefix: []const u8, suffix: []const u8 }{
        .{ .prefix = "function f(", .suffix = ") { \"use strict\"; }" },
        .{ .prefix = "\"use strict\"; function g(", .suffix = ") {}" },
    };
    for (shapes) |shape| for ([_]bool{ false, true }) |repeat| {
        var text: std.Io.Writer.Allocating = .init(gpa);
        defer text.deinit();
        try text.writer.writeAll(shape.prefix);
        for (0..10_000) |index| try text.writer.print("{s}a{d}", .{ if (index == 0) "" else ", ", index });
        const repeat_offset = text.written().len + ", ".len;
        if (repeat) try text.writer.writeAll(", a0");
        try text.writer.writeAll(shape.suffix);
        var source = try web_string.WebString.fromUtf8(gpa, text.written());
        defer source.deinit(gpa);
        Parser.duplicate_comparisons = 0;
        var parse = try parseScript(gpa, source.units, .{});
        defer parse.deinit();
        const expected_tag: std.meta.Tag(@FieldType(Parse, "outcome")) = if (repeat) .diagnostic else .script;
        try testing.expectEqual(expected_tag, std.meta.activeTag(parse.outcome));
        if (repeat) try testing.expectEqual(Diagnostic{ .syntax_error = .{ .code = .duplicate_parameter, .offset = @intCast(repeat_offset) } }, parse.outcome.diagnostic);
        if (Parser.duplicate_comparisons > 20_000) {
            std.debug.print("{s}...{s} with repeat {}: {d} comparisons\n", .{ shape.prefix, shape.suffix, repeat, Parser.duplicate_comparisons });
            return error.TestTooManyComparisons;
        }
    };
}
