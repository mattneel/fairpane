// FP-0082 evidence item 5: parses every source of contract cases 2, 6, and 7 with Node's vm.Script.
// The contract expects case 2 sources to be valid and case 6 sources to be syntax errors.
// The only allowed disagreements among cases 2 and 6 are E54, E55, and E56. Case 7 rows are for information only.
// V8 is an oracle only; no expected value comes from this run.
import vm from 'node:vm';

const valid = [
  ['T1', ''],
  ['T2', '"use strict";'],
  ['T3', '"use\\x20strict"; var let;'],
  ['T4', '"a"; "use strict";'],
  ['T5', '"use strict"\n+1; var let;'],
  ['T6', '("use strict"); var let;'],
  ['T7', 'var a, b = 1; var a;'],
  ['T8', 'function f() {} function g() {} function f() {}'],
  ['T9', 'function f(a, b) { var c = a; function g() {} return c + b; }'],
  ['T10', 'function f() { "use strict"; return this; }'],
  ['T11', 'if (a) { var x; } while (b) var y; for (var z;;) {} try { var p } catch (q) { var r } finally { var s } l: var t; switch (u) { case 1: var v; default: var w; }'],
  ['T12', 'a + b * c - d; a = b = c; a || b && c; a ? b : c ? d : e;'],
  ['T13', '2 ** 3 ** 2; (-2) ** 2; ++a ** 2; a ** -b;'],
  ['T14', 'a < b == c > d; a & b | c ^ d; a << b + c >>> d; a instanceof b in c;'],
  ['T15', 'typeof void delete a.b; - -a; ~!a; a+++b; a, b, c;'],
  ['T16', 'new a.b(c).d(e)[f]; new new a()(); new a; new a().b; new (a()); new a()();'],
  ['T17', 'a.if.class[0](1, 2,); a.\\u0069f; 5..a; a ? .5 : 1;'],
  ['T18', '({a: 1, "b": 2, 3: 3, 0x10: 4, 1.50: 5, [k]: 6, c, __proto__: null, if: 7, \\u0069f: 8,});'],
  ['T19', '({"__proto__": a, ["__proto__"]: b, __proto__, get: 1, set: 2, async: 3, get});'],
  ['T20', '(function () {}); (function g(a,) { "use strict"; }); x = function () { return 1; };'],
  ['T21', '"\\0\\b\\f\\n\\r\\t\\v\\x41\\u0042\\u{43}\\u{1F600}\\uD800\\\'\\"\\\\a\\\nb";'],
  ['T22', '"\\101\\08\\8\\9\\400";'],
  ['T23', '"a\u2028b"; "a\\\u2028b"; "\\u{0000000000041}";'],
  ['T24', '0; 1.5; .5; 5.; 1e3; 1E-3; 0x1F; 0o17; 0b101; 010; 08; 09.5; 1_000; 0x1_F; 1e1_0; 9007199254740993; 1e400; 0.1; 0.0000001;'],
  ['T25', 'var \\u0061b\\u{63};'],
  ['T26', '/* a */ a /* b\n */ b // c\n<!-- d\n--> e\n c'],
  ['T27', 'x = 1 <!-- y'],
  ['T28', 'a /* x */ --> b'],
  ['T29 first', '--> b'],
  ['T29 second', '  --> b'],
  ['T29 third', '/* */ --> b'],
  ['T29 fourth', 'a /*\n*/ --> b'],
  ['T30', '#!anything\nx'],
  ['T31 white space', 'a\t\v\f \u00A0\uFEFF\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200A\u202F\u205F\u3000= 1'],
  ['T31 LS', 'a\u2028b'],
  ['T31 PS', 'a\u2029b'],
  ['T31 CR LF', 'a\r\nb'],
  ['T31 CR', 'a\rb'],
  ['T32 call', 'a\n(b)'],
  ['T32 update', 'x\n++y'],
  ['T32 do-while', 'do ; while (0) x'],
  ['T32 comment', 'var a = 1 /*\n*/ b = 2'],
  ['T32 division', 'a\n/b/g'],
  ['T32 break', 'l: while (1) { break\nl }'],
  ['T32 block', '{ 1\n2 } 3'],
  ['T32 return', 'function f() { return\n1 }'],
  ['T33', 'if (a) if (b) c; else d; l1: l2: for (;;) { continue l1; } a: { b: { break a; } } switch (x) { case 1: a; case 2: default: b; case 3: } try { a } catch (e) { var e = 1; } finally { b } try {} catch {} try {} finally {} throw a; debugger; ;'],
  ['T34', 'do x++; while (x < 3) for (var i = 0, j; i < 1; i++) continue; for (i = 0; ; ) break; while (a) {}'],
  ['T35', 'f() = 1; f() += 1; f()++; --f(); eval = 1; arguments = 2; delete (x); (a) = 1; ((a.b)) = 2;'],
  ['T36', 'var yield, await, let, static, async, of, get, set; let = 1; let(1); yield = 1; await = 2; let: 1; l\\u0065t = 1; async\nfunction f() {}'],
  ['T37', 'function f(arguments) { return arguments; } function g() { function arguments() {} return arguments; } arguments;'],
  ['T38', 'a: while (1) { (function () { a: ; }); break a; }'],
  ['T39', '"use strict"; var a = function () {}; function f() {}'],
  ['T40', 'try {} catch (e) { var e; }'],
  ['T41', 'debugger; ;'],
];

const errors = [
  ['E1', 'var 1;'], ['E2', 'a b'], ['E3', 'if (a'], ['E4', 'a @ b'], ['E5', 'a \u0001 b'], ['E6', 'a \\ b'],
  ['E7', '"abc'], ['E8', '"a\nb"'], ['E9', '"a\rb"'], ['E10', '/* a'], ['E11', '"\\x4"'], ['E12', '"\\u12"'],
  ['E13', '"\\u{110000}"'], ['E14', '"\\u{}"'], ['E15', '\\u0030abc'], ['E16', 'a\\u002Db'],
  ...['3in []', '0x', '0b12', '1__0', '1_', '0_1', '08_1', '1e', '1e_1', '0x_1', '1.a', '1._5', '1_.5', '1.5n', '01n', '0x1g'].map(s => [`E17 ${s}`, s]),
  ['E18', '07.5'], ['E19', '"use strict"; 010;'], ['E20', '"use strict"; 08;'], ['E21', '"use strict"; 09.5'],
  ['E22', 'function f(a) { "use strict"; 010 }'], ['E23', '"use strict"; "\\08";'], ['E24', '"use strict"; "\\8";'],
  ['E25', 'function f() { "\\07"; "use strict"; }'], ['E26', '"\\07"; "use strict";'], ['E27', 'var if;'], ['E28', 'var enum;'],
  ['E29', 'var v\\u0061r;'], ['E30', '\\u0074his'], ['E31', '({if})'], ['E32', '({\\u0069f})'], ['E33', '"use strict"; var let;'],
  ['E34', '"use strict"; var yield;'], ['E35', '"use strict"; implements = 1;'], ['E36', '"use strict"; l\\u0065t = 1;'],
  ['E37', '"use strict"; let: 1'], ['E38', 'function yield() { "use strict"; }'], ['E39', '"use strict"; var eval;'],
  ['E40', '"use strict"; arguments = 1;'], ['E41', '"use strict"; eval++;'], ['E42', '"use strict"; function arguments() {}'],
  ['E43', 'function eval() { "use strict"; }'], ['E44', '"use strict"; try {} catch (eval) {}'], ['E45', '"use strict"; function f(eval) {}'],
  ['E46', '1 = 2'], ['E47', 'a + 1 = 2'], ['E48', 'this = 1'], ['E49', '(a, b) = 1'], ['E50', '++1'], ['E51', '1++'],
  ['E52', 'new f() = 1'], ['E53', 'typeof a = 1'], ['E54', '"use strict"; f() = 1;'], ['E55', '"use strict"; f()++;'],
  ['E56', '"use strict"; f() += 1;'], ['E57', '"use strict"; delete x;'], ['E58', '"use strict"; delete (x);'],
  ['E59', '"use strict"; delete ((x));'], ['E60', 'function f() { "use strict"; delete x; }'], ['E61', '"use strict"; with (a) {}'],
  ['E62', '"use strict"; if (a) function f() {}'], ['E63', '"use strict"; l: function f() {}'], ['E64', 'while (a) function f() {}'],
  ['E65', 'while (0) l: function f() {}'], ['E66', 'do function f() {} while (0)'], ['E67', 'if (a) l: function f() {}'],
  ['E68', 'a: a: ;'], ['E69', 'a: { a: ; }'], ['E70', 'a: { break b; }'], ['E71', 'break a;'], ['E72', 'a: { while (1) { continue a; } }'],
  ['E73', 'a: while (1) { continue b; }'], ['E74', 'break;'], ['E75', 'while (1) { (function () { break; }); }'], ['E76', 'continue;'],
  ['E77', 'switch (1) { case 1: continue; }'], ['E78', 'return;'], ['E79', '"use strict"; function f(a, a) {}'],
  ['E80', 'function f(a, a) { "use strict"; }'], ['E81', '({__proto__: 1, __proto__: 2})'], ['E82', '({__proto__: 1, "__proto__": 2})'],
  ['E83', '({a = 1})'], ['E84', '-a ** 2'], ['E85', 'typeof a ** 2'], ['E86', '!a ** 2'], ['E87', '#x'], ['E88', 'a.#x'], ['E89', ' #!x'],
  ['E90', 'throw\n1'], ['E91', '{ 1 2 } 3'], ['E92', 'for (a; b\n) c'], ['E93', 'if (a)\nelse b'], ['E94', 'a\n++'], ['E95', 'function () {}'],
  ['E96', '()'], ['E97', 'function f(,) {}'], ['E98', 'try {}'], ['E99', 'switch (a) { default: default: }'], ['E100', 'export var a;'],
  ['E101', 'x = 1; --> y'], ['E102', '@dec class A {}'],
];

const unsupported = [
  ['U1', 'let x;'], ['U2', 'const x = 1;'], ['U3', 'let [a] = b;'], ['U4', 'let\nx'], ['U5', 'for (let i;;) {}'], ['U6', 'if (a) { let x; }'],
  ['U7', 'using x = y;'], ['U8', 'class A {}'], ['U9', '(class {})'], ['U10', 'function* g() {}'], ['U11', '(function* () {})'],
  ['U12', 'async function f() {}'], ['U13', 'async x => x'], ['U14', 'async (x) => x'], ['U15', '(async function () {})'], ['U16', 'x => x'],
  ['U17', '(a, b) => a'], ['U18', '() => 1'], ['U19', '(a, ...b) => 1'], ['U20', '`a`'], ['U21', 'f`a`'], ['U22', '/a/'], ['U23', 'a = /b/g'],
  ['U24', 'if (a) /x/.test(b)'], ['U25', '[1]'], ['U26', 'a = []'], ['U27', '1n'], ['U28', '0x1Fn'], ['U29', 'f(...a)'], ['U30', 'new F(...a)'],
  ['U31', '({a() {}})'], ['U32 get', '({get a() {}})'], ['U32 set', '({set a(v) {}})'], ['U32 generator', '({*g() {}})'], ['U32 async', '({async f() {}})'],
  ['U33', '({...a})'], ['U34', 'var {a} = b;'], ['U35', 'var [a] = b;'], ['U36', 'function f({a}) {}'], ['U37', 'try {} catch ([e]) {}'],
  ['U38', '({a} = b)'], ['U39', '({a = 1} = b)'], ['U40', 'function f(a = 1) {}'], ['U41', 'function f(...a) {}'], ['U42 member', 'a?.b'],
  ['U42 index', 'a?.[0]'], ['U42 call', 'a?.()'], ['U43', 'a ?? b'], ['U44 and', 'a &&= b'], ['U44 coalesce', 'a ??= b'], ['U44 or', 'a ||= b'],
  ['U45', 'function f() { new.target }'], ['U46', 'super.x'], ['U47 declaration', 'import x from "y"'], ['U47 call', 'import("y")'],
  ['U47 meta', 'import.meta'], ['U48 expression', 'for (a in b) {}'], ['U48 var', 'for (var a in b) {}'], ['U48 initializer', 'for (var a = 1 in b) {}'],
  ['U49 expression', 'for (a of b) {}'], ['U49 var', 'for (var a of b) {}'], ['U50', 'for await (x of y) {}'], ['U51', 'with (a) {}'],
  ['U52 block', '{ function f() {} }'], ['U52 if', 'if (a) function f() {}'], ['U52 label', 'l: function f() {}'],
  ['U52 case', 'switch (a) { case 1: function f() {} }'], ['U52 strict block', '"use strict"; { function f() {} }'], ['U53 raw', 'var \u00E9;'],
  ['U53 escape', 'var \\u00e9;'], ['U53 joiner', 'var a\\u200C;'], ['U53 separator', 'var\u180Ea;'],
  ['U54 reference', 'function f() { return arguments; }'], ['U54 var', 'function f() { var arguments; return arguments; }'],
  ['U54 nested', 'function f() { return function () { return arguments; }; }'],
];

function parses(source) {
  try { new vm.Script(source); return true; } catch (e) { if (e instanceof SyntaxError) return false; throw e; }
}

const allowed = new Set(['E54', 'E55', 'E56']);
let disagreements = 0, unexpected = 0;
for (const [group, rows, expectValid] of [['case 2', valid, true], ['case 6', errors, false]]) {
  for (const [name, source] of rows) {
    const v8 = parses(source);
    if (v8 === expectValid) continue;
    disagreements++;
    const note = allowed.has(name) ? 'allowed' : 'NOT ALLOWED';
    if (!allowed.has(name)) unexpected++;
    console.log(`${group} ${name}: contract ${expectValid ? 'valid' : 'syntax error'}, V8 ${v8 ? 'valid' : 'syntax error'} (${note})`);
  }
}
for (const [name, source] of unsupported) console.log(`case 7 ${name}: V8 ${parses(source) ? 'valid' : 'syntax error'} (information only)`);
console.log(JSON.stringify({ case2_rows: valid.length, case6_rows: errors.length, case7_rows: unsupported.length, disagreements, not_allowed: unexpected }));
process.exitCode = unexpected === 0 ? 0 : 1;
