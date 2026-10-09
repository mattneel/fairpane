//! The FP-0082 syntax tree, its function records and declaration lists, and the dump writer.
//!
//! Every node records the code-unit offset of its first token and its height: 1 for a leaf, and
//! one more than its tallest child otherwise. The height counts the same parenthesized groups as
//! the node depth of the dump, so the parser can bound the depth of a tree that it builds bottom up.

const std = @import("std");
const number = @import("number.zig");
const Writer = std.Io.Writer;

/// An identifier's StringValue. Identifiers are ASCII until FP-0095.
pub const Name = []const u16;

pub const Script = struct {
    strict: bool,
    /// TopLevelVarDeclaredNames in source order, first occurrence only.
    var_declared_names: []const Name,
    /// The functionsToInitialize list of GlobalDeclarationInstantiation (16.1.7).
    functions_to_initialize: []const *const Function,
    statements: []const *const Statement,
};

pub const Function = struct {
    /// The 1-based index of a FunctionDeclaration among all FunctionDeclarations of the source,
    /// in the order of their `function` tokens, or 0 for a FunctionExpression.
    index: u32,
    name: ?Name,
    params: []const Name,
    strict: bool,
    /// TopLevelVarDeclaredNames of the FunctionBody in source order, first occurrence only.
    var_declared_names: []const Name,
    /// The functionsToInitialize list of FunctionDeclarationInstantiation (10.2.11).
    functions_to_initialize: []const *const Function,
    statements: []const *const Statement,
    /// The code-unit range of the function's source text, from `function` through `}`.
    source_start: u32,
    source_end: u32,
    height: u32,
};

pub const Declarator = struct { name: Name, init: ?*const Expression };

pub const ForInit = union(enum) {
    variable: []const Declarator,
    expression: *const Expression,
};

pub const Case = struct {
    /// Null for the default clause.
    test_expression: ?*const Expression,
    body: []const *const Statement,
};

pub const Catch = struct {
    /// Null for an omitted catch binding.
    param: ?Name,
    body: []const *const Statement,
};

pub const Statement = struct {
    start: u32,
    height: u32,
    data: Data,

    pub const Data = union(enum) {
        expression: *const Expression,
        variable: []const Declarator,
        block: []const *const Statement,
        empty,
        if_statement: struct { test_expression: *const Expression, consequent: *const Statement, alternate: ?*const Statement },
        do_while: struct { body: *const Statement, test_expression: *const Expression },
        while_statement: struct { test_expression: *const Expression, body: *const Statement },
        for_statement: struct { init: ?ForInit, test_expression: ?*const Expression, update: ?*const Expression, body: *const Statement },
        continue_statement: ?Name,
        break_statement: ?Name,
        return_statement: ?*const Expression,
        throw_statement: *const Expression,
        switch_statement: struct { discriminant: *const Expression, cases: []const Case },
        labelled: struct { label: Name, body: *const Statement },
        try_statement: struct { block: []const *const Statement, handler: ?Catch, finalizer: ?[]const *const Statement },
        debugger,
        function_declaration: *const Function,
    };
};

pub const UpdateOperator = enum { increment, decrement };
pub const UnaryOperator = enum { delete, void, typeof, plus, minus, bitwise_not, logical_not };
pub const BinaryOperator = enum {
    exponent,
    multiply,
    divide,
    remainder,
    add,
    subtract,
    shift_left,
    shift_right,
    shift_right_unsigned,
    less,
    greater,
    less_equal,
    greater_equal,
    instanceof,
    in,
    equal,
    not_equal,
    strict_equal,
    strict_not_equal,
    bitwise_and,
    bitwise_xor,
    bitwise_or,
};
pub const LogicalOperator = enum { @"and", @"or" };
pub const AssignmentOperator = enum {
    assign,
    multiply,
    divide,
    remainder,
    add,
    subtract,
    shift_left,
    shift_right,
    shift_right_unsigned,
    bitwise_and,
    bitwise_xor,
    bitwise_or,
    exponent,
};

pub const Property = union(enum) {
    /// `PropertyName : AssignmentExpression` with a literal key, by its PropName.
    property: struct { key: []const u16, value: *const Expression },
    computed: struct { key: *const Expression, value: *const Expression },
    shorthand: Name,
    /// The `__proto__: value` form of 13.2.5.
    proto: *const Expression,

    pub fn height(property: Property) u32 {
        return switch (property) {
            .property => |p| 1 + p.value.height,
            .computed => |c| 1 + @max(1 + c.key.height, c.value.height),
            .shorthand => 1,
            .proto => |value| 1 + value.height,
        };
    }
};

pub const Expression = struct {
    start: u32,
    height: u32,
    data: Data,

    pub const Data = union(enum) {
        identifier: Name,
        this,
        null_literal,
        true_literal,
        false_literal,
        number: f64,
        string: []const u16,
        object: []const Property,
        function: *const Function,
        paren: *const Expression,
        member: struct { object: *const Expression, name: Name },
        index: struct { object: *const Expression, index: *const Expression },
        call: struct { callee: *const Expression, arguments: []const *const Expression },
        new: struct { callee: *const Expression, arguments: []const *const Expression },
        prefix: struct { operator: UpdateOperator, operand: *const Expression },
        postfix: struct { operator: UpdateOperator, operand: *const Expression },
        unary: struct { operator: UnaryOperator, operand: *const Expression },
        binary: struct { operator: BinaryOperator, left: *const Expression, right: *const Expression },
        logical: struct { operator: LogicalOperator, left: *const Expression, right: *const Expression },
        conditional: struct { test_expression: *const Expression, consequent: *const Expression, alternate: *const Expression },
        assign: struct { operator: AssignmentOperator, target: *const Expression, value: *const Expression },
        sequence: []const *const Expression,
    };
};

pub fn updateText(operator: UpdateOperator) []const u8 {
    return switch (operator) {
        .increment => "++",
        .decrement => "--",
    };
}

pub fn unaryText(operator: UnaryOperator) []const u8 {
    return switch (operator) {
        .delete => "delete",
        .void => "void",
        .typeof => "typeof",
        .plus => "+",
        .minus => "-",
        .bitwise_not => "~",
        .logical_not => "!",
    };
}

pub fn binaryText(operator: BinaryOperator) []const u8 {
    return switch (operator) {
        .exponent => "**",
        .multiply => "*",
        .divide => "/",
        .remainder => "%",
        .add => "+",
        .subtract => "-",
        .shift_left => "<<",
        .shift_right => ">>",
        .shift_right_unsigned => ">>>",
        .less => "<",
        .greater => ">",
        .less_equal => "<=",
        .greater_equal => ">=",
        .instanceof => "instanceof",
        .in => "in",
        .equal => "==",
        .not_equal => "!=",
        .strict_equal => "===",
        .strict_not_equal => "!==",
        .bitwise_and => "&",
        .bitwise_xor => "^",
        .bitwise_or => "|",
    };
}

pub fn logicalText(operator: LogicalOperator) []const u8 {
    return switch (operator) {
        .@"and" => "&&",
        .@"or" => "||",
    };
}

pub fn assignmentText(operator: AssignmentOperator) []const u8 {
    return switch (operator) {
        .assign => "=",
        .multiply => "*=",
        .divide => "/=",
        .remainder => "%=",
        .add => "+=",
        .subtract => "-=",
        .shift_left => "<<=",
        .shift_right => ">>=",
        .shift_right_unsigned => ">>>=",
        .bitwise_and => "&=",
        .bitwise_xor => "^=",
        .bitwise_or => "|=",
        .exponent => "**=",
    };
}

// The dump writer. It walks the tree with an explicit stack of one frame per open group, so the
// native stack does not grow with the depth of the tree.

/// A group of the dump: a node, or a group that the dump adds around some of a node's children.
pub const Group = union(enum) {
    script: *const Script,
    function: *const Function,
    statement: *const Statement,
    expression: *const Expression,
    property: *const Property,
    computed: *const Expression,
    declarators: []const Declarator,
    declarator: *const Declarator,
    case: *const Case,
    block: []const *const Statement,
    catch_clause: *const Catch,
    finally: []const *const Statement,
    /// The `-` of an absent part of a `for` head.
    absent,
};

/// An open group and the index of its next child.
pub const WriteFrame = struct { group: Group, next: u32 };

/// Writes the one-line dump of `script`. `stack` holds at least one frame per level of the tree.
pub fn writeScript(script: *const Script, stack: []WriteFrame, writer: *Writer) Writer.Error!void {
    stack[0] = .{ .group = .{ .script = script }, .next = 0 };
    try writeHead(stack[0].group, writer);
    var len: usize = 1;
    while (len != 0) {
        const frame = &stack[len - 1];
        if (childOf(frame.group, frame.next)) |child| {
            frame.next += 1;
            try writer.writeByte(' ');
            try writeHead(child, writer);
            stack[len] = .{ .group = child, .next = 0 };
            len += 1;
        } else {
            try writeTail(frame.group, writer);
            len -= 1;
        }
    }
}

fn statementGroup(statement: *const Statement) Group {
    return switch (statement.data) {
        .variable => |declarators| .{ .declarators = declarators },
        .function_declaration => |function| .{ .function = function },
        else => .{ .statement = statement },
    };
}

fn expressionGroup(expression: *const Expression) Group {
    return switch (expression.data) {
        .function => |function| .{ .function = function },
        else => .{ .expression = expression },
    };
}

fn statementAt(statements: []const *const Statement, index: u32) ?Group {
    return if (index < statements.len) statementGroup(statements[index]) else null;
}

fn expressionAt(expressions: []const *const Expression, index: u32) ?Group {
    return if (index < expressions.len) expressionGroup(expressions[index]) else null;
}

/// The child group of `group` at `index`, in dump order, or null after the last child.
fn childOf(group: Group, index: u32) ?Group {
    return switch (group) {
        .script => |script| statementAt(script.statements, index),
        .function => |function| statementAt(function.statements, index),
        .block => |statements| statementAt(statements, index),
        .finally => |statements| if (index == 0) Group{ .block = statements } else null,
        .declarators => |declarators| if (index < declarators.len) Group{ .declarator = &declarators[index] } else null,
        .declarator => |declarator| if (index == 0) (if (declarator.init) |init| expressionGroup(init) else null) else null,
        .case => |case| if (case.test_expression) |test_expression|
            (if (index == 0) expressionGroup(test_expression) else statementAt(case.body, index - 1))
        else
            statementAt(case.body, index),
        .catch_clause => |clause| if (index == 0) Group{ .block = clause.body } else null,
        .computed => |key| if (index == 0) expressionGroup(key) else null,
        .property => |property| switch (property.*) {
            .property => |p| if (index == 0) expressionGroup(p.value) else null,
            .computed => |c| switch (index) {
                0 => .{ .computed = c.key },
                1 => expressionGroup(c.value),
                else => null,
            },
            .shorthand => null,
            .proto => |value| if (index == 0) expressionGroup(value) else null,
        },
        .statement => |statement| statementChild(statement, index),
        .expression => |expression| expressionChild(expression, index),
        .absent => null,
    };
}

fn optionalChild(expression: ?*const Expression) Group {
    return if (expression) |e| expressionGroup(e) else .absent;
}

fn statementChild(statement: *const Statement, index: u32) ?Group {
    return switch (statement.data) {
        .expression, .throw_statement => |e| if (index == 0) expressionGroup(e) else null,
        .block => |statements| statementAt(statements, index),
        .if_statement => |s| switch (index) {
            0 => expressionGroup(s.test_expression),
            1 => statementGroup(s.consequent),
            2 => if (s.alternate) |alternate| statementGroup(alternate) else null,
            else => null,
        },
        .do_while => |s| switch (index) {
            0 => statementGroup(s.body),
            1 => expressionGroup(s.test_expression),
            else => null,
        },
        .while_statement => |s| switch (index) {
            0 => expressionGroup(s.test_expression),
            1 => statementGroup(s.body),
            else => null,
        },
        .for_statement => |s| switch (index) {
            0 => if (s.init) |init| switch (init) {
                .variable => |declarators| Group{ .declarators = declarators },
                .expression => |e| expressionGroup(e),
            } else .absent,
            1 => optionalChild(s.test_expression),
            2 => optionalChild(s.update),
            3 => statementGroup(s.body),
            else => null,
        },
        .return_statement => |value| if (index == 0) (if (value) |e| expressionGroup(e) else null) else null,
        .switch_statement => |s| if (index == 0) expressionGroup(s.discriminant) else if (index - 1 < s.cases.len) Group{ .case = &s.cases[index - 1] } else null,
        .labelled => |s| if (index == 0) statementGroup(s.body) else null,
        .try_statement => |*s| tryChild(s.block, if (s.handler) |*handler| handler else null, s.finalizer, index),
        .variable, .function_declaration, .empty, .debugger, .continue_statement, .break_statement => null,
    };
}

fn tryChild(block: []const *const Statement, handler: ?*const Catch, finalizer: ?[]const *const Statement, index: u32) ?Group {
    var remaining = index;
    if (remaining == 0) return .{ .block = block };
    remaining -= 1;
    if (handler) |clause| {
        if (remaining == 0) return .{ .catch_clause = clause };
        remaining -= 1;
    }
    if (finalizer) |statements| {
        if (remaining == 0) return .{ .finally = statements };
    }
    return null;
}

fn expressionChild(expression: *const Expression, index: u32) ?Group {
    return switch (expression.data) {
        .identifier, .this, .null_literal, .true_literal, .false_literal, .number, .string, .function => null,
        .object => |properties| if (index < properties.len) Group{ .property = &properties[index] } else null,
        .paren => |inner| if (index == 0) expressionGroup(inner) else null,
        .member => |m| if (index == 0) expressionGroup(m.object) else null,
        .index => |i| switch (index) {
            0 => expressionGroup(i.object),
            1 => expressionGroup(i.index),
            else => null,
        },
        .call => |c| if (index == 0) expressionGroup(c.callee) else expressionAt(c.arguments, index - 1),
        .new => |n| if (index == 0) expressionGroup(n.callee) else expressionAt(n.arguments, index - 1),
        .prefix => |u| if (index == 0) expressionGroup(u.operand) else null,
        .postfix => |u| if (index == 0) expressionGroup(u.operand) else null,
        .unary => |u| if (index == 0) expressionGroup(u.operand) else null,
        .binary => |b| switch (index) {
            0 => expressionGroup(b.left),
            1 => expressionGroup(b.right),
            else => null,
        },
        .logical => |l| switch (index) {
            0 => expressionGroup(l.left),
            1 => expressionGroup(l.right),
            else => null,
        },
        .conditional => |c| switch (index) {
            0 => expressionGroup(c.test_expression),
            1 => expressionGroup(c.consequent),
            2 => expressionGroup(c.alternate),
            else => null,
        },
        .assign => |a| switch (index) {
            0 => expressionGroup(a.target),
            1 => expressionGroup(a.value),
            else => null,
        },
        .sequence => |elements| expressionAt(elements, index),
    };
}

/// Writes the text of `group` before its first child.
fn writeHead(group: Group, writer: *Writer) Writer.Error!void {
    switch (group) {
        .script => |script| {
            try writer.writeAll(if (script.strict) "(script strict " else "(script sloppy ");
            try writeDeclarations(script.var_declared_names, script.functions_to_initialize, writer);
        },
        .function => |function| try writeFunctionHead(function, writer),
        .statement => |statement| try writeStatementHead(statement, writer),
        .expression => |expression| try writeExpressionHead(expression, writer),
        .property => |property| switch (property.*) {
            .property => |p| {
                try writer.writeAll("(property ");
                try writeString(p.key, writer);
            },
            .computed => try writer.writeAll("(property"),
            .shorthand => |name| {
                try writer.writeAll("(shorthand ");
                try writeName(name, writer);
            },
            .proto => try writer.writeAll("(proto"),
        },
        .computed => try writer.writeAll("(computed"),
        .declarators => try writer.writeAll("(var"),
        .declarator => |declarator| {
            try writer.writeByte('(');
            try writeName(declarator.name, writer);
        },
        .case => |case| try writer.writeAll(if (case.test_expression == null) "(default" else "(case"),
        .block => try writer.writeAll("(block"),
        .catch_clause => |clause| {
            try writer.writeAll("(catch ");
            if (clause.param) |name| try writeName(name, writer) else try writer.writeByte('-');
        },
        .finally => try writer.writeAll("(finally"),
        .absent => try writer.writeByte('-'),
    }
}

/// Writes the text of `group` after its last child.
fn writeTail(group: Group, writer: *Writer) Writer.Error!void {
    switch (group) {
        .absent => {},
        .expression => |expression| {
            if (expression.data == .member) {
                try writer.writeByte(' ');
                try writeString(expression.data.member.name, writer);
            }
            try writer.writeByte(')');
        },
        else => try writer.writeByte(')'),
    }
}

fn writeDeclarations(names: []const Name, functions: []const *const Function, writer: *Writer) Writer.Error!void {
    try writer.writeAll("(var-declared-names");
    for (names) |name| {
        try writer.writeByte(' ');
        try writeName(name, writer);
    }
    try writer.writeAll(") (functions-to-initialize");
    for (functions) |function| {
        try writer.writeByte(' ');
        try writeName(function.name.?, writer);
        try writer.print("#{d}", .{function.index});
    }
    try writer.writeByte(')');
}

fn writeName(name: Name, writer: *Writer) Writer.Error!void {
    for (name) |unit| try writer.writeByte(@intCast(unit));
}

/// Writes `units` in double quotes, escaping `"` and `\`, and every code unit outside 0x20 to 0x7E as `\uXXXX`.
fn writeString(units: []const u16, writer: *Writer) Writer.Error!void {
    try writer.writeByte('"');
    for (units) |unit| {
        switch (unit) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            0x20...0x21, 0x23...0x5B, 0x5D...0x7E => try writer.writeByte(@intCast(unit)),
            else => try writer.print("\\u{X:0>4}", .{unit}),
        }
    }
    try writer.writeByte('"');
}

fn writeFunctionHead(function: *const Function, writer: *Writer) Writer.Error!void {
    if (function.index != 0) {
        try writer.print("(function-declaration #{d} ", .{function.index});
        try writeName(function.name.?, writer);
    } else {
        try writer.writeAll("(function-expression ");
        if (function.name) |name| try writeName(name, writer) else try writer.writeByte('-');
    }
    try writer.writeAll(" (params");
    for (function.params) |param| {
        try writer.writeByte(' ');
        try writeName(param, writer);
    }
    try writer.writeAll(if (function.strict) ") strict " else ") sloppy ");
    try writeDeclarations(function.var_declared_names, function.functions_to_initialize, writer);
}

fn writeLabel(label: ?Name, writer: *Writer) Writer.Error!void {
    if (label) |name| {
        try writer.writeByte(' ');
        try writeName(name, writer);
    }
}

fn writeStatementHead(statement: *const Statement, writer: *Writer) Writer.Error!void {
    switch (statement.data) {
        .expression => try writer.writeAll("(expression"),
        .block => try writer.writeAll("(block"),
        .empty => try writer.writeAll("(empty"),
        .if_statement => try writer.writeAll("(if"),
        .do_while => try writer.writeAll("(do-while"),
        .while_statement => try writer.writeAll("(while"),
        .for_statement => try writer.writeAll("(for"),
        .continue_statement => |label| {
            try writer.writeAll("(continue");
            try writeLabel(label, writer);
        },
        .break_statement => |label| {
            try writer.writeAll("(break");
            try writeLabel(label, writer);
        },
        .return_statement => try writer.writeAll("(return"),
        .throw_statement => try writer.writeAll("(throw"),
        .switch_statement => try writer.writeAll("(switch"),
        .labelled => |s| {
            try writer.writeAll("(labelled ");
            try writeName(s.label, writer);
        },
        .try_statement => try writer.writeAll("(try"),
        .debugger => try writer.writeAll("(debugger"),
        // These statements are written as their own groups.
        .variable, .function_declaration => unreachable,
    }
}

fn writeOperator(kind: []const u8, operator: []const u8, writer: *Writer) Writer.Error!void {
    try writer.writeByte('(');
    try writer.writeAll(kind);
    try writer.writeByte(' ');
    try writer.writeAll(operator);
}

fn writeExpressionHead(expression: *const Expression, writer: *Writer) Writer.Error!void {
    switch (expression.data) {
        .identifier => |name| {
            try writer.writeAll("(identifier ");
            try writeName(name, writer);
        },
        .this => try writer.writeAll("(this"),
        .null_literal => try writer.writeAll("(null"),
        .true_literal => try writer.writeAll("(true"),
        .false_literal => try writer.writeAll("(false"),
        .number => |value| {
            try writer.writeAll("(number ");
            var buffer: [number.max_string_units]u16 = undefined;
            try writeName(number.toString(value, &buffer), writer);
        },
        .string => |units| {
            try writer.writeAll("(string ");
            try writeString(units, writer);
        },
        .object => try writer.writeAll("(object"),
        .paren => try writer.writeAll("(paren"),
        .member => try writer.writeAll("(member"),
        .index => try writer.writeAll("(index"),
        .call => try writer.writeAll("(call"),
        .new => try writer.writeAll("(new"),
        .prefix => |u| try writeOperator("prefix", updateText(u.operator), writer),
        .postfix => |u| try writeOperator("postfix", updateText(u.operator), writer),
        .unary => |u| try writeOperator("unary", unaryText(u.operator), writer),
        .binary => |b| try writeOperator("binary", binaryText(b.operator), writer),
        .logical => |l| try writeOperator("logical", logicalText(l.operator), writer),
        .conditional => try writer.writeAll("(conditional"),
        .assign => |a| try writeOperator("assign", assignmentText(a.operator), writer),
        .sequence => try writer.writeAll("(sequence"),
        // A function expression is written as its own group.
        .function => unreachable,
    }
}
