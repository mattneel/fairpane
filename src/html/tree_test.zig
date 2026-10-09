//! FP-0100 contract cases 1, 3 to 11, 13, and 14: the insertion modes, the tree dump, whole documents, the mode walks,
//! in body and the head modes, the adoption agency algorithm, scripts, unsupported features, branch coverage,
//! node retention, and allocation failures.
//!
//! A case's record is its outcome sequence, its errors with their offsets, its document mode, and its dump.
//! The partition harness in `tree_partition_test.zig` compares the same record.

const std = @import("std");
const dom = @import("../dom.zig");
const html = @import("root.zig");
const tree = @import("tree.zig");
const modes = @import("modes.zig");
const errors = @import("errors.zig");
const tree_dump = @import("tree_dump.zig");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const ScriptingMode = html.ScriptingMode;

/// One case of the contract. `input` is the case's Zig string literal. `errors` is the case's error notation, or
/// "none". `offsets` lists the error offsets of a multi-line input; for any other input each offset is the column
/// minus one. `outcomes` lists the outcome sequence without `need_input`.
pub const Case = struct {
    id: []const u8,
    input: []const u8,
    scripting: ScriptingMode = .disabled,
    units: ?usize = null,
    outcomes: []const u8 = "done",
    errors: []const u8,
    offsets: ?[]const usize = null,
    mode: dom.DocumentMode,
    dump: []const u8,
};

const html_head_body = "| <html>\n|   <head>\n|   <body>\n";

fn doctypeCase(comptime id: []const u8, comptime input: []const u8, comptime line: ?[]const u8, mode: dom.DocumentMode, comptime errors_text: []const u8) Case {
    return .{
        .id = id,
        .input = input,
        .errors = errors_text,
        .mode = mode,
        .dump = (if (line) |text| text ++ "\n" else "") ++ html_head_body,
    };
}

/// Case 4.
pub const doctypes = [_]Case{
    doctypeCase("D1", "<!DOCTYPE html>", "| <!DOCTYPE html>", .no_quirks, "none"),
    doctypeCase("D2", "<!DOCTYPE html SYSTEM \"about:legacy-compat\">", "| <!DOCTYPE html \"\" \"about:legacy-compat\">", .no_quirks, "none"),
    doctypeCase("D3", "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">", "| <!DOCTYPE html \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"\">", .quirks, "!tree@1:1"),
    doctypeCase("D4", "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">", "| <!DOCTYPE html \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">", .limited_quirks, "!tree@1:1"),
    doctypeCase("D5", "<!DOCTYPE html PUBLIC \"-//w3c//dtd xhtml 1.0 transitional//en\" \"x\">", "| <!DOCTYPE html \"-//w3c//dtd xhtml 1.0 transitional//en\" \"x\">", .limited_quirks, "!tree@1:1"),
    doctypeCase("D6", "<!DOCTYPE svg>", "| <!DOCTYPE svg>", .quirks, "!tree@1:1"),
    doctypeCase("D7", "<!DOCTYPE>", "| <!DOCTYPE >", .quirks, "!missing-doctype-name@1:10 !tree@1:1"),
    doctypeCase("D8", "<!DOCTYPE html PUBLIC \"HTML\">", "| <!DOCTYPE html \"HTML\" \"\">", .quirks, "!tree@1:1"),
    doctypeCase("D9", "<!DOCTYPE html SYSTEM \"http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd\">", "| <!DOCTYPE html \"\" \"http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd\">", .quirks, "!tree@1:1"),
    doctypeCase("D10", "<html><!DOCTYPE html>", null, .quirks, "!tree@1:1 !tree@1:7"),
    doctypeCase("D11", "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Frameset//EN\" \"\">", "| <!DOCTYPE html \"-//W3C//DTD HTML 4.01 Frameset//EN\" \"\">", .quirks, "!tree@1:1"),
};

/// Case 5.
pub const documents = [_]Case{
    .{
        .id = "T1",
        .input = "<!DOCTYPE html><html><head><title>T</title></head><body><p>x</p></body></html>",
        .errors = "none",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   <head>
        \\|     <title>
        \\|       "T"
        \\|   <body>
        \\|     <p>
        \\|       "x"
        ++ "\n",
    },
    .{ .id = "T2", .input = "", .errors = "!tree@1:1", .mode = .quirks, .dump = html_head_body },
    .{
        .id = "T3",
        .input = " <!--a--><?t d?><!DOCTYPE html> <!--b-->x",
        .errors = "none",
        .mode = .no_quirks,
        .dump =
        \\| <!-- a -->
        \\| <?t d?>
        \\| <!DOCTYPE html>
        \\| <!-- b -->
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     "x"
        ++ "\n",
    },
};

/// Case 6.
pub const walks = [_]Case{
    .{
        .id = "W1",
        .input = " <!--a--><?t d?><!DOCTYPE html> <!--b--><?u v?><!DOCTYPE html></x><html> <!--c--><?w?><!DOCTYPE html><html k=v></y><head>",
        .units = 121,
        .errors = "!tree@1:48 !tree@1:63 !tree@1:87 !tree@1:102 !tree@1:112",
        .mode = .no_quirks,
        .dump =
        \\| <!-- a -->
        \\| <?t d?>
        \\| <!DOCTYPE html>
        \\| <!-- b -->
        \\| <?u v?>
        \\| <html>
        \\|   k="v"
        \\|   <!-- c -->
        \\|   <?w ?>
        \\|   <head>
        \\|   <body>
        ++ "\n",
    },
    .{
        .id = "W2",
        .input = "<!DOCTYPE html></head></br>",
        .errors = "!tree@1:23",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <br>
        ++ "\n",
    },
    .{
        .id = "W3",
        .input = "<!DOCTYPE html><head> <!--c--><?p?><!DOCTYPE html><html a=b><base><basefont><bgsound><link/><meta/><title>t</title><noframes>n</noframes><style>s</style><script>j</script></template><head></p></br>",
        .units = 197,
        .outcomes = "script@171 done",
        .errors = "!tree@1:36 !tree@1:51 !tree@1:172 !tree@1:183 !tree@1:189 !tree@1:193",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   a="b"
        \\|   <head>
        \\|     " "
        \\|     <!-- c -->
        \\|     <?p ?>
        \\|     <base>
        \\|     <basefont>
        \\|     <bgsound>
        \\|     <link>
        \\|     <meta>
        \\|     <title>
        \\|       "t"
        \\|     <noframes>
        \\|       "n"
        \\|     <style>
        \\|       "s"
        \\|     <script>
        \\|       "j"
        \\|   <body>
        \\|     <br>
        ++ "\n",
    },
    .{
        .id = "W4",
        .input = "<!DOCTYPE html><head><noscript><!DOCTYPE html><html c=d> <!--x--><?y?><basefont><bgsound><link><meta><noframes>f</noframes><style>g</style><head><noscript></q></noscript><noscript></br>",
        .units = 185,
        .errors = "!tree@1:32 !tree@1:47 !tree@1:140 !tree@1:146 !tree@1:156 !tree@1:181 !tree@1:181",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   c="d"
        \\|   <head>
        \\|     <noscript>
        \\|       " "
        \\|       <!-- x -->
        \\|       <?y ?>
        \\|       <basefont>
        \\|       <bgsound>
        \\|       <link>
        \\|       <meta>
        \\|       <noframes>
        \\|         "f"
        \\|       <style>
        \\|         "g"
        \\|     <noscript>
        \\|   <body>
        \\|     <br>
        ++ "\n",
    },
    .{
        .id = "W5",
        .input = "<!DOCTYPE html><head></head> <!--a--><?b?><!DOCTYPE html><html e=f><meta></template><head></p></html>",
        .units = 101,
        .errors = "!tree@1:43 !tree@1:58 !tree@1:68 !tree@1:74 !tree@1:85 !tree@1:91",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   e="f"
        \\|   <head>
        \\|     <meta>
        \\|   " "
        \\|   <!-- a -->
        \\|   <?b ?>
        \\|   <body>
        ++ "\n",
    },
    .{
        .id = "W6",
        .input = "<!DOCTYPE html><body></body> <!--a--><?b?><!DOCTYPE html><html g=h></html> <!--c--><?d?><!DOCTYPE html><html i=j>x",
        .units = 114,
        .errors = "!tree@1:43 !tree@1:58 !tree@1:89 !tree@1:104 !tree@1:114",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   g="h"
        \\|   i="j"
        \\|   <head>
        \\|   <body>
        \\|     "  x"
        \\|   <!-- a -->
        \\|   <?b ?>
        \\| <!-- c -->
        \\| <?d ?>
        ++ "\n",
    },
    .{
        .id = "W7",
        .input = "<!DOCTYPE html><body a=1><!--c--><?p?><!DOCTYPE html><body a=2 b=3>x",
        .errors = "!tree@1:39 !tree@1:54",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     a="1"
        \\|     b="3"
        \\|     <!-- c -->
        \\|     <?p ?>
        \\|     "x"
        ++ "\n",
    },
    .{
        .id = "W8",
        .input = "<dl><dd>a</dd><dt>b</dt></dd></sarcasm><param><source><track><xmp><p></xmp><iframe><b></iframe><noembed><i></noembed><noscript><u></noscript>",
        .scripting = .normal,
        .units = 141,
        .errors = "!tree@1:1 !tree@1:25 !tree@1:30 !tree@1:142",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <dl>
        \\|       <dd>
        \\|         "a"
        \\|       <dt>
        \\|         "b"
        \\|       <param>
        \\|       <source>
        \\|       <track>
        \\|       <xmp>
        \\|         "<p>"
        \\|       <iframe>
        \\|         "<b>"
        \\|       <noembed>
        \\|         "<i>"
        \\|       <noscript>
        \\|         "<u>"
        ++ "\n",
    },
};

/// Case 7.
pub const body_cases = [_]Case{
    .{ .id = "B1", .input = "a\x00 b", .units = 4, .errors = "!tree@1:1 !unexpected-null-character@1:2 !tree@1:2", .mode = .quirks, .dump = html_head_body ++ "|     \"a b\"\n" },
    .{
        .id = "B2",
        .input = "<head></head>  x",
        .units = 16,
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   "  "
        \\|   <body>
        \\|     "x"
        ++ "\n",
    },
    .{
        .id = "B3",
        .input = "<head></head><style>x</style><body>",
        .errors = "!tree@1:1 !tree@1:14",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|     <style>
        \\|       "x"
        \\|   <body>
        ++ "\n",
    },
    .{
        .id = "B4",
        .input = "<!DOCTYPE html><noscript><link><style>s</style><!--c--> </noscript><noscript>x",
        .units = 78,
        .errors = "!tree@1:78",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   <head>
        \\|     <noscript>
        \\|       <link>
        \\|       <style>
        \\|         "s"
        \\|       <!-- c -->
        \\|       " "
        \\|     <noscript>
        \\|   <body>
        \\|     "x"
        ++ "\n",
    },
    .{
        .id = "B5",
        .input = "<!DOCTYPE html><noscript><link><style>s</style><!--c--> </noscript><noscript>x",
        .scripting = .normal,
        .units = 78,
        .errors = "!tree@1:79",
        .mode = .no_quirks,
        .dump =
        \\| <!DOCTYPE html>
        \\| <html>
        \\|   <head>
        \\|     <noscript>
        \\|       "<link><style>s</style><!--c--> "
        \\|     <noscript>
        \\|       "x"
        \\|   <body>
        ++ "\n",
    },
    .{
        .id = "B6",
        .input = "<p>a<div>b</p>c",
        .errors = "!tree@1:1 !tree@1:11 !tree@1:16",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <p>
        \\|       "a"
        \\|     <div>
        \\|       "b"
        \\|       <p>
        \\|       "c"
        ++ "\n",
    },
    .{
        .id = "B7",
        .input = "<h1>a<h2>b</h3>c</h1>d",
        .errors = "!tree@1:1 !tree@1:6 !tree@1:11 !tree@1:17",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <h1>
        \\|       "a"
        \\|     <h2>
        \\|       "b"
        \\|     "cd"
        ++ "\n",
    },
    .{
        .id = "B8",
        .input = "<ul><li>a<li>b<div><li>c</ul>d</li>",
        .errors = "!tree@1:1 !tree@1:20 !tree@1:31",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <ul>
        \\|       <li>
        \\|         "a"
        \\|       <li>
        \\|         "b"
        \\|         <div>
        \\|       <li>
        \\|         "c"
        \\|     "d"
        ++ "\n",
    },
    .{
        .id = "B9",
        .input = "<dl><dt>a<dd>b<dt>c</dl>",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <dl>
        \\|       <dt>
        \\|         "a"
        \\|       <dd>
        \\|         "b"
        \\|       <dt>
        \\|         "c"
        ++ "\n",
    },
    .{
        .id = "B10",
        .input = "<pre>\nA</pre><listing>\n\nB</listing><textarea>\nC</textarea>",
        .units = 58,
        .errors = "!tree@1:1",
        .offsets = &.{0},
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <pre>
        \\|       "A"
        \\|     <listing>
        \\|       "
        \\B"
        \\|     <textarea>
        \\|       "C"
        ++ "\n",
    },
    .{
        .id = "B11",
        .input = "<pre>&#10x",
        .units = 10,
        .errors = "!tree@1:1 !missing-semicolon-after-character-reference@1:10 !tree@1:11",
        .mode = .quirks,
        .dump = html_head_body ++ "|     <pre>\n|       \"x\"\n",
    },
    .{
        .id = "B12",
        .input = "<textarea>\nx",
        .units = 12,
        .errors = "!tree@1:1 !tree@2:2",
        .offsets = &.{ 0, 12 },
        .mode = .quirks,
        .dump = html_head_body ++ "|     <textarea>\n|       \"x\"\n",
    },
    .{
        .id = "B13",
        .input = "<pre>\r\nA</pre>",
        .units = 14,
        .errors = "!tree@1:1",
        .offsets = &.{0},
        .mode = .quirks,
        .dump = html_head_body ++ "|     <pre>\n|       \"A\"\n",
    },
    .{
        .id = "B14",
        .input = "<b><plaintext>a</b><p>",
        .errors = "!tree@1:1 !tree@1:23",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <b>
        \\|       <plaintext>
        \\|         "a</b><p>"
        ++ "\n",
    },
    .{
        .id = "B15",
        .input = "<button>a<button>b",
        .errors = "!tree@1:1 !tree@1:10 !tree@1:19",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <button>
        \\|       "a"
        \\|     <button>
        \\|       "b"
        ++ "\n",
    },
    .{
        .id = "B16",
        .input = "<form><form><div></form>x</div></form>",
        .errors = "!tree@1:1 !tree@1:7 !tree@1:18 !tree@1:32",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <form>
        \\|       <div>
        \\|         "x"
        ++ "\n",
    },
    .{
        .id = "B17",
        .input = "<html a=1><body b=2><html a=3 c=4><body b=5 d=6>",
        .errors = "!tree@1:1 !tree@1:21 !tree@1:35",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   a="1"
        \\|   c="4"
        \\|   <head>
        \\|   <body>
        \\|     b="2"
        \\|     d="6"
        ++ "\n",
    },
    .{
        .id = "B18",
        .input = "<body></body> <!--x--></html> <!--y-->z",
        .errors = "!tree@1:1 !tree@1:39",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     "  z"
        \\|   <!-- x -->
        \\| <!-- y -->
        ++ "\n",
    },
    .{
        .id = "B19",
        .input = "<!DOCTYPE html></body>",
        .errors = "none",
        .mode = .no_quirks,
        .dump = "| <!DOCTYPE html>\n" ++ html_head_body,
    },
    .{
        .id = "B20",
        .input = "<select><option>a<option>b<optgroup><option>c</select><select><hr><input>",
        .errors = "!tree@1:1 !tree@1:67",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <select>
        \\|       <option>
        \\|         "a"
        \\|       <option>
        \\|         "b"
        \\|       <optgroup>
        \\|         <option>
        \\|           "c"
        \\|     <select>
        \\|       <hr>
        \\|     <input>
        ++ "\n",
    },
    .{
        .id = "B21",
        .input = "<select>a<select>b",
        .errors = "!tree@1:1 !tree@1:10",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <select>
        \\|       "a"
        \\|     "b"
        ++ "\n",
    },
    .{
        .id = "B22",
        .input = "<ruby>a<rb>b<rt>c<rtc>d<rp>e</ruby>",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <ruby>
        \\|       "a"
        \\|       <rb>
        \\|         "b"
        \\|       <rt>
        \\|         "c"
        \\|       <rtc>
        \\|         "d"
        \\|         <rp>
        \\|           "e"
        ++ "\n",
    },
    .{
        .id = "B23",
        .input = "<image src=a>",
        .errors = "!tree@1:1 !tree@1:1",
        .mode = .quirks,
        .dump = html_head_body ++ "|     <img>\n|       src=\"a\"\n",
    },
    .{
        .id = "B24",
        .input = "<b><object><i>x</object>y",
        .errors = "!tree@1:1 !tree@1:16 !tree@1:26",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <b>
        \\|       <object>
        \\|         <i>
        \\|           "x"
        \\|       "y"
        ++ "\n",
    },
    .{
        .id = "B25",
        .input = "<td>x<tr>y</td>",
        .errors = "!tree@1:1 !tree@1:1 !tree@1:6 !tree@1:11",
        .mode = .quirks,
        .dump = html_head_body ++ "|     \"xy\"\n",
    },
    .{
        .id = "B26",
        .input = "<span><div></span>x</div>",
        .errors = "!tree@1:1 !tree@1:12 !tree@1:26",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <span>
        \\|       <div>
        \\|         "x"
        ++ "\n",
    },
    .{
        .id = "B27",
        .input = "a</br x=1>b",
        .errors = "!tree@1:1 !end-tag-with-attributes@1:10 !tree@1:2",
        .mode = .quirks,
        .dump = html_head_body ++ "|     \"a\"\n|     <br>\n|     \"b\"\n",
    },
    .{
        .id = "B28",
        .input = "<br/><div/>x",
        .errors = "!tree@1:1 !non-void-html-element-start-tag-with-trailing-solidus@1:6 !tree@1:13",
        .mode = .quirks,
        .dump = html_head_body ++ "|     <br>\n|     <div>\n|       \"x\"\n",
    },
    .{
        .id = "B29",
        .input = "<body><title>&amp;</title><meta>",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump = html_head_body ++ "|     <title>\n|       \"&\"\n|     <meta>\n",
    },
    .{
        .id = "B30",
        .input = "<p><![CDATA[x]]>",
        .units = 16,
        .errors = "!tree@1:1 !cdata-in-html-content@1:12",
        .mode = .quirks,
        .dump = html_head_body ++ "|     <p>\n|       <!-- [CDATA[x]] -->\n",
    },
    .{
        .id = "B31",
        .input = "<!DOCTYPE html></body><p>x",
        .units = 26,
        .errors = "!tree@1:23",
        .mode = .no_quirks,
        .dump = "| <!DOCTYPE html>\n" ++ html_head_body ++ "|     <p>\n|       \"x\"\n",
    },
    .{
        .id = "B32",
        .input = " \r\nx",
        .units = 4,
        .errors = "!tree@2:1",
        .offsets = &.{3},
        .mode = .quirks,
        .dump = html_head_body ++ "|     \"x\"\n",
    },
};

/// Case 8.
pub const formatting_cases = [_]Case{
    .{
        .id = "A1",
        .input = "<b>1<p>2</b>3</p>",
        .units = 17,
        .errors = "!tree@1:1 !tree@1:9",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <b>
        \\|       "1"
        \\|     <p>
        \\|       <b>
        \\|         "2"
        \\|       "3"
        ++ "\n",
    },
    .{
        .id = "A2",
        .input = "<a>1<b>2<p>3</a>4",
        .units = 17,
        .errors = "!tree@1:1 !tree@1:13 !tree@1:18",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <a>
        \\|       "1"
        \\|       <b>
        \\|         "2"
        \\|     <b>
        \\|       <p>
        \\|         <a>
        \\|           "3"
        \\|         "4"
        ++ "\n",
    },
    .{
        .id = "A3",
        .input = "<a><b><i><u><s><div>x</a>y",
        .errors = "!tree@1:1 !tree@1:22 !tree@1:27",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <a>
        \\|       <b>
        \\|         <i>
        \\|           <u>
        \\|             <s>
        \\|     <i>
        \\|       <u>
        \\|         <s>
        \\|           <div>
        \\|             <a>
        \\|               "x"
        \\|             "y"
        ++ "\n",
    },
    .{
        .id = "A4",
        .input = "<b><i></b>x",
        .errors = "!tree@1:1 !tree@1:7 !tree@1:12",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <b>
        \\|       <i>
        \\|     <i>
        \\|       "x"
        ++ "\n",
    },
    .{
        .id = "A5",
        .input = "<b><object></b>x",
        .errors = "!tree@1:1 !tree@1:12 !tree@1:17",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <b>
        \\|       <object>
        \\|         "x"
        ++ "\n",
    },
    .{
        .id = "A6",
        .input = "<b><select></b>x",
        .errors = "!tree@1:1 !tree@1:12 !tree@1:17",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <b>
        \\|       <select>
        \\|         "x"
        ++ "\n",
    },
    .{
        .id = "A7",
        .input = "<a>1<p>2<a>3",
        .units = 12,
        .errors = "!tree@1:1 !tree@1:9 !tree@1:9 !tree@1:13",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <a>
        \\|       "1"
        \\|     <p>
        \\|       <a>
        \\|         "2"
        \\|       <a>
        \\|         "3"
        ++ "\n",
    },
    .{
        .id = "A8",
        .input = "<p><b></p></b>x",
        .errors = "!tree@1:1 !tree@1:7 !tree@1:11",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <p>
        \\|       <b>
        \\|     "x"
        ++ "\n",
    },
    .{
        .id = "A9",
        .input = "<p><b><b><b><b><p>x",
        .errors = "!tree@1:1 !tree@1:16 !tree@1:20",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <p>
        \\|       <b>
        \\|         <b>
        \\|           <b>
        \\|             <b>
        \\|     <p>
        \\|       <b>
        \\|         <b>
        \\|           <b>
        \\|             "x"
        ++ "\n",
    },
    .{
        .id = "A10",
        .input = "<p><b c=1><b c=1><b c=2><b c=1><b c=1><p>x",
        .units = 42,
        .errors = "!tree@1:1 !tree@1:39 !tree@1:43",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <p>
        \\|       <b>
        \\|         c="1"
        \\|         <b>
        \\|           c="1"
        \\|           <b>
        \\|             c="2"
        \\|             <b>
        \\|               c="1"
        \\|               <b>
        \\|                 c="1"
        \\|     <p>
        \\|       <b>
        \\|         c="1"
        \\|         <b>
        \\|           c="2"
        \\|           <b>
        \\|             c="1"
        \\|             <b>
        \\|               c="1"
        \\|               "x"
        ++ "\n",
    },
    .{
        .id = "A11",
        .input = "<nobr>a<nobr>b",
        .errors = "!tree@1:1 !tree@1:8 !tree@1:15",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <nobr>
        \\|       "a"
        \\|     <nobr>
        \\|       "b"
        ++ "\n",
    },
    .{
        .id = "A12",
        .input = "<b><b><b><b>x</b></b></b></b>y",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <b>
        \\|       <b>
        \\|         <b>
        \\|           <b>
        \\|             "x"
        \\|     "y"
        ++ "\n",
    },
};

/// The S1 dump at its script boundary, before the next `run`.
pub const s1_boundary_dump =
    \\| <html>
    \\|   <head>
    \\|   <body>
    \\|     <p>
    \\|       "a"
    \\|       <script>
    \\|         "b"
++ "\n";

/// Case 9.
pub const script_cases = [_]Case{
    .{
        .id = "S1",
        .input = "<p>a<script>b</script>c",
        .scripting = .normal,
        .units = 23,
        .outcomes = "script@22 done",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|   <body>
        \\|     <p>
        \\|       "a"
        \\|       <script>
        \\|         "b"
        \\|       "c"
        ++ "\n",
    },
    .{
        .id = "S2",
        .input = "<script>x",
        .scripting = .normal,
        .units = 9,
        .errors = "!tree@1:1 !tree@1:10",
        .mode = .quirks,
        .dump =
        \\| <html>
        \\|   <head>
        \\|     <script>
        \\|       "x"
        \\|   <body>
        ++ "\n",
    },
};

/// Case 10, with the owner of each unsupported feature.
pub const unsupported_cases = [_]Case{
    .{
        .id = "U1",
        .input = "<p><table>",
        .outcomes = "unsupported(mode in_table)@10",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump = html_head_body ++ "|     <p>\n|       <table>\n",
    },
    .{
        .id = "U2",
        .input = "<!DOCTYPE html><p><table>",
        .outcomes = "unsupported(mode in_table)@25",
        .errors = "none",
        .mode = .no_quirks,
        .dump = "| <!DOCTYPE html>\n" ++ html_head_body ++ "|     <p>\n|     <table>\n",
    },
    .{
        .id = "U3",
        .input = "<template>",
        .outcomes = "unsupported(template)@0",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump = "| <html>\n|   <head>\n",
    },
    .{
        .id = "U4",
        .input = "<frameset><frame>",
        .outcomes = "unsupported(mode in_frameset)@10",
        .errors = "!tree@1:1",
        .mode = .quirks,
        .dump = "| <html>\n|   <head>\n|   <frameset>\n",
    },
    .{ .id = "U5", .input = "<svg>", .outcomes = "unsupported(foreign)@0", .errors = "!tree@1:1", .mode = .quirks, .dump = html_head_body },
    .{ .id = "U6", .input = "<math>", .outcomes = "unsupported(foreign)@0", .errors = "!tree@1:1", .mode = .quirks, .dump = html_head_body },
    .{
        .id = "F1",
        .input = "<p>x</p><frameset>y",
        .errors = "!tree@1:1 !tree@1:9",
        .mode = .quirks,
        .dump = html_head_body ++ "|     <p>\n|       \"x\"\n|     \"y\"\n",
    },
    .{
        .id = "F2",
        .input = "<p> </p><frameset>",
        .outcomes = "unsupported(mode in_frameset)@18",
        .errors = "!tree@1:1 !tree@1:9",
        .mode = .quirks,
        .dump = "| <html>\n|   <head>\n|   <frameset>\n",
    },
};

/// The owner that case 10 names for each case with an unsupported outcome.
const unsupported_owners = [_]struct { id: []const u8, owner: []const u8 }{
    .{ .id = "U1", .owner = "FP-0102" },
    .{ .id = "U2", .owner = "FP-0102" },
    .{ .id = "U3", .owner = "FP-0103" },
    .{ .id = "U4", .owner = "FP-0103" },
    .{ .id = "U5", .owner = "FP-0104" },
    .{ .id = "U6", .owner = "FP-0104" },
    .{ .id = "F2", .owner = "FP-0103" },
};

/// The tables of cases 4 to 10, in case order.
pub const tables = [_][]const Case{ &doctypes, &documents, &walks, &body_cases, &formatting_cases, &script_cases, &unsupported_cases };

/// Returns the case of cases 4 to 10 named `id`.
pub fn find(id: []const u8) Case {
    for (tables) |table| {
        for (table) |case| {
            if (std.mem.eql(u8, case.id, id)) return case;
        }
    }
    std.debug.panic("no case {s}", .{id});
}

/// Returns the UTF-16 code units of an ASCII input. The caller frees the result with `gpa`.
pub fn units(gpa: Allocator, input: []const u8) Allocator.Error![]u16 {
    const result = try gpa.alloc(u16, input.len);
    for (input, result) |byte, *unit| {
        std.debug.assert(byte < 0x80);
        unit.* = byte;
    }
    return result;
}

fn asciiView(comptime text: []const u8) html.View {
    const converted = comptime blk: {
        var buffer: [text.len]u16 = undefined;
        for (text, &buffer) |byte, *unit| unit.* = byte;
        break :blk buffer;
    };
    return .{ .units = &converted };
}

/// Writes an outcome in the case notation. `need_input` writes nothing.
pub fn writeOutcome(w: *Writer, outcome: html.Outcome) Writer.Error!void {
    switch (outcome) {
        .need_input => {},
        .done => try w.writeAll("done"),
        .script => |script| try w.print("script@{d}", .{@backingInt(script.offset)}),
        .unsupported => |unsupported| {
            switch (unsupported.feature) {
                .mode => |mode| try w.print("unsupported(mode {s})", .{@tagName(mode)}),
                .template_start_tag => try w.writeAll("unsupported(template)"),
                .foreign_start_tag => try w.writeAll("unsupported(foreign)"),
            }
            try w.print("@{d}", .{@backingInt(unsupported.offset)});
        },
    }
}

fn sameOutcome(a: html.Outcome, b: html.Outcome) bool {
    return switch (a) {
        .need_input => b == .need_input,
        .done => b == .done,
        .script => |s| b == .script and std.meta.eql(s.element, b.script.element) and s.offset == b.script.offset,
        .unsupported => |u| b == .unsupported and std.meta.eql(u, b.unsupported),
    };
}

/// The observed results of one parse.
pub const Observed = struct {
    outcomes: std.ArrayList(html.Outcome) = .empty,
    /// The record: the outcome sequence, the errors, their offsets, the document mode, and the dump.
    record: []u8 = &.{},

    pub fn deinit(o: *Observed, gpa: Allocator) void {
        o.outcomes.deinit(gpa);
        gpa.free(o.record);
        o.* = undefined;
    }
};

/// Writes the record of a finished parse.
fn writeRecord(w: *Writer, store: *dom.Store, parser: *const html.Parser, outcomes: []const html.Outcome) !void {
    try w.writeAll("outcomes:");
    for (outcomes) |outcome| {
        try w.writeByte(' ');
        try writeOutcome(w, outcome);
    }
    try w.writeAll("\nerrors:");
    const list = parser.errors();
    if (list.len == 0) try w.writeAll(" none");
    for (list) |e| {
        try w.print(" !{s}@{d}:{d}", .{ if (e.code) |code| errors.name(code) else "tree", e.position.line, e.position.column });
    }
    try w.writeAll("\noffsets:");
    for (list) |e| try w.print(" {d}", .{@backingInt(e.position.offset)});
    try w.print("\nmode: {s}\n", .{@tagName(try store.documentMode(parser.document()))});
    try tree_dump.writeChildren(store, parser.document(), w);
}

/// Returns the expected record of `case`. The caller frees it with `gpa`.
pub fn expectedRecord(gpa: Allocator, case: Case) ![]u8 {
    var out: Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.print("outcomes: {s}\nerrors: {s}\noffsets:", .{ case.outcomes, case.errors });
    if (case.offsets) |offsets| {
        for (offsets) |offset| try w.print(" {d}", .{offset});
    } else if (!std.mem.eql(u8, case.errors, "none")) {
        // A single-line input: each error's offset is its column minus one.
        if (std.mem.indexOfAny(u8, case.input, "\r\n") != null) return error.TestUnexpectedResult;
        var items = std.mem.splitScalar(u8, case.errors, ' ');
        while (items.next()) |item| {
            const at = std.mem.indexOfScalar(u8, item, '@') orelse return error.TestUnexpectedResult;
            const colon = std.mem.indexOfScalarPos(u8, item, at, ':') orelse return error.TestUnexpectedResult;
            if (!std.mem.eql(u8, item[at + 1 .. colon], "1")) return error.TestUnexpectedResult;
            const column = try std.fmt.parseInt(usize, item[colon + 1 ..], 10);
            try w.print(" {d}", .{column - 1});
        }
    }
    try w.print("\nmode: {s}\n{s}", .{ @tagName(case.mode), case.dump });
    return out.toOwnedSlice();
}

/// Whether `outcome` ends the parse.
pub fn terminal(outcome: html.Outcome) bool {
    return outcome == .done or outcome == .unsupported;
}

/// Parses `input` in the chunks that the sorted `boundaries` delimit and returns its observations.
/// With no boundaries, it is the reference run: it calls `feed` with the whole input and `finish` before its first `run`.
/// Otherwise, after each chunk it runs until `need_input` and then overwrites the chunk's buffer with 0xAAAA.
/// A `script` outcome is followed by another `run`. After the terminal outcome, it checks that a second `run` returns
/// it again and that the store's invariants hold.
pub fn parseChunks(gpa: Allocator, input: []const u16, boundaries: []const usize, scripting: ScriptingMode) !Observed {
    var store = try dom.Store.init(gpa);
    defer store.deinit();
    var parser = try html.Parser.init(gpa, &store, .{ .scripting = scripting });
    defer parser.deinit();
    var observed: Observed = .{};
    errdefer observed.deinit(gpa);
    var ended = false;
    if (boundaries.len == 0) {
        try parser.feed(input);
        try parser.finish();
    } else {
        var start: usize = 0;
        for (0..boundaries.len + 1) |index| {
            const end = if (index < boundaries.len) boundaries[index] else input.len;
            const buffer = try gpa.dupe(u16, input[start..end]);
            defer gpa.free(buffer);
            try parser.feed(buffer);
            while (!ended) {
                const outcome = try parser.run();
                if (outcome == .need_input) break;
                try observed.outcomes.append(gpa, outcome);
                ended = terminal(outcome);
            }
            if (ended) break;
            @memset(buffer, 0xAAAA);
            start = end;
        }
        if (!ended) try parser.finish();
    }
    while (!ended) {
        const outcome = try parser.run();
        if (outcome == .need_input) return error.TestUnexpectedResult;
        try observed.outcomes.append(gpa, outcome);
        ended = terminal(outcome);
    }
    const last = observed.outcomes.items[observed.outcomes.items.len - 1];
    if (!sameOutcome(last, try parser.run())) return error.TestUnexpectedResult;
    try dom.expectInvariants(&store);
    var out: Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try writeRecord(&out.writer, &store, &parser, observed.outcomes.items);
    observed.record = try out.toOwnedSlice();
    return observed;
}

/// Checks that `case` gives its frozen record as one chunk. Prints a mismatch and returns false.
pub fn checkCase(task: []const u8, case: Case) !bool {
    const gpa = testing.allocator;
    const input = try units(gpa, case.input);
    defer gpa.free(input);
    var passed = true;
    if (case.units) |count| {
        if (count != input.len) {
            std.debug.print("{s} case {s}: the case lists {d} code units, and the input has {d}\n", .{ task, case.id, count, input.len });
            passed = false;
        }
    }
    const expected = try expectedRecord(gpa, case);
    defer gpa.free(expected);
    var observed = try parseChunks(gpa, input, &.{}, case.scripting);
    defer observed.deinit(gpa);
    if (!std.mem.eql(u8, expected, observed.record)) {
        std.debug.print("{s} case {s}:\nexpected:\n{s}observed:\n{s}", .{ task, case.id, expected, observed.record });
        passed = false;
    }
    return passed;
}

fn checkTable(table: []const Case) !void {
    var failed = false;
    for (table) |case| {
        if (!try checkCase("FP-0100", case)) failed = true;
    }
    try testing.expect(!failed);
}

const frozen_mode_titles = "initial; before html; before head; in head; in head noscript; after head; in body; text; in table; in table text; in caption; in column group; in table body; in row; in cell; in template; after body; in frameset; after frameset; after after body; after after frameset";

/// The branch table of the contract, one row per implemented mode, with branches separated by "; ".
const frozen_branches = [_]struct { mode: modes.Mode, branches: []const u8 }{
    .{ .mode = .initial, .branches = "whitespace; comment; processing instruction; DOCTYPE; else" },
    .{ .mode = .before_html, .branches = "DOCTYPE; comment; processing instruction; whitespace; start html; end head, body, html, or br; other end tag; else" },
    .{ .mode = .before_head, .branches = "whitespace; comment; processing instruction; DOCTYPE; start html; start head; end head, body, html, or br; other end tag; else" },
    .{ .mode = .in_head, .branches = "whitespace; comment; processing instruction; DOCTYPE; start html; start base, basefont, bgsound, or link; start meta; start title; start noscript when scripting is not Disabled, noframes, or style; start noscript when scripting is Disabled; start script; end head; end body, html, or br; start template; end template; start head or other end tag; else" },
    .{ .mode = .in_head_noscript, .branches = "DOCTYPE; start html; end noscript; whitespace, comment, processing instruction, or start basefont, bgsound, link, meta, noframes, or style; end br; start head or noscript, or other end tag; else" },
    .{ .mode = .after_head, .branches = "whitespace; comment; processing instruction; DOCTYPE; start html; start body; start frameset; start base, basefont, bgsound, link, meta, noframes, script, style, template, or title; end template; end body, html, or br; start head or other end tag; else" },
    .{ .mode = .in_body, .branches = "NULL; whitespace; other character; comment; processing instruction; DOCTYPE; start html; start base, basefont, bgsound, link, meta, noframes, script, style, template, or title, or end template; start body; start frameset; EOF; end body; end html; start address group; start h1 to h6; start pre or listing; start form; start li; start dd or dt; start plaintext; start button; end address group; end form; end p; end li; end dd or dt; end h1 to h6; end sarcasm; start a; start b group; start nobr; end formatting group; start applet, marquee, or object; end applet, marquee, or object; start table; end br; start area, br, embed, img, keygen, or wbr; start input; start param, source, or track; start hr; start image; start textarea; start xmp; start iframe; start noembed, or noscript when scripting is not Disabled; start select; start option; start optgroup; start rb or rtc; start rp or rt; start math; start svg; start caption, col, colgroup, frame, head, tbody, td, tfoot, th, thead, or tr; other start tag; other end tag" },
    .{ .mode = .text, .branches = "character; EOF; end script; other end tag" },
    .{ .mode = .after_body, .branches = "whitespace; comment; processing instruction; DOCTYPE; start html; end html; EOF; else" },
    .{ .mode = .after_after_body, .branches = "comment; processing instruction; DOCTYPE, whitespace, or start html; EOF; else" },
};

test "FP-0100 case 1: Mode has 21 tags in the order of the standard, ten are implemented, and the branch table has 130 branches" {
    const values = std.enums.values(modes.Mode);
    try testing.expectEqual(@as(usize, 21), values.len);
    var titles = std.mem.splitSequence(u8, frozen_mode_titles, "; ");
    for (values, 1..) |mode, section| {
        try testing.expectEqual(section, modes.section(mode));
        try testing.expectEqualStrings(titles.next().?, modes.title(mode));
    }
    try testing.expectEqual(null, titles.next());

    const implemented = [_]modes.Mode{ .initial, .before_html, .before_head, .in_head, .in_head_noscript, .after_head, .in_body, .text, .after_body, .after_after_body };
    for (values) |mode| {
        const listed = std.mem.indexOfScalar(modes.Mode, &implemented, mode) != null;
        try testing.expectEqual(listed, modes.implemented(mode));
        const expected_owner: ?[]const u8 = switch (mode) {
            .in_table, .in_table_text, .in_caption, .in_column_group, .in_table_body, .in_row, .in_cell => "FP-0102",
            .in_template, .in_frameset, .after_frameset, .after_after_frameset => "FP-0103",
            else => null,
        };
        if (expected_owner) |owner| {
            try testing.expectEqualStrings(owner, modes.owner(mode).?);
            try testing.expectEqual(@as(usize, 0), modes.branches(mode).len);
        } else {
            try testing.expectEqual(null, modes.owner(mode));
        }
    }

    var total: usize = 0;
    for (frozen_branches) |row| {
        var names = std.mem.splitSequence(u8, row.branches, "; ");
        for (modes.branches(row.mode)) |branch| try testing.expectEqualStrings(names.next().?, branch);
        try testing.expectEqual(null, names.next());
        total += modes.branches(row.mode).len;
    }
    try testing.expectEqual(@as(usize, 130), total);
    try testing.expectEqual(@as(usize, 130), modes.branch_count);
    try testing.expectEqual(@as(usize, 0), comptime modes.branchIndex(.initial, "whitespace"));
    try testing.expectEqual(@as(usize, 129), comptime modes.branchIndex(.after_after_body, "else"));
}

const xlink_namespace = asciiView("http://www.w3.org/1999/xlink");
const xml_namespace = asciiView("http://www.w3.org/XML/1998/namespace");
const xmlns_namespace = asciiView("http://www.w3.org/2000/xmlns/");
const html_namespace = asciiView("http://www.w3.org/1999/xhtml");
const svg_namespace = asciiView("http://www.w3.org/2000/svg");
const mathml_namespace = asciiView("http://www.w3.org/1998/Math/MathML");

fn dumpOf(gpa: Allocator, store: *dom.Store, root: dom.NodeHandle) ![]u8 {
    var out: Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try tree_dump.writeChildren(store, root, &out.writer);
    return out.toOwnedSlice();
}

test "FP-0100 case 3: the tree dump writes every node type, sorts attributes, and rejects other namespaces" {
    const gpa = testing.allocator;
    var store = try dom.Store.init(gpa);
    defer store.deinit();
    const s = &store;
    // Y1.
    const document = try s.createHtmlDocument();
    try s.appendChild(document, try s.createDocumentType(document, asciiView("html"), asciiView("p"), asciiView("")));
    const root = try s.createElement(document, html_namespace, asciiView("html"));
    try s.setAttribute(root, null, asciiView("b"), asciiView("2"));
    try s.setAttribute(root, null, asciiView("a"), asciiView("1"));
    try s.appendChild(document, root);
    const svg = try s.createElement(document, svg_namespace, asciiView("svg"));
    try s.setAttribute(svg, xlink_namespace, asciiView("href"), asciiView("x"));
    try s.setAttribute(svg, null, asciiView("viewBox"), asciiView("0"));
    try s.setAttribute(svg, xml_namespace, asciiView("lang"), asciiView("en"));
    try s.setAttribute(svg, xmlns_namespace, asciiView("xmlns"), asciiView("y"));
    try s.appendChild(root, svg);
    try s.appendChild(root, try s.createElement(document, mathml_namespace, asciiView("mi")));
    try s.appendChild(root, try s.createText(document, asciiView("a\nb")));
    try s.appendChild(root, try s.createComment(document, asciiView(" c ")));
    try s.appendChild(root, try s.createProcessingInstruction(document, asciiView("t"), asciiView("")));
    try dom.expectInvariants(s);
    const y1 = try dumpOf(gpa, s, document);
    defer gpa.free(y1);
    try testing.expectEqualStrings(
        \\| <!DOCTYPE html "p" "">
        \\| <html>
        \\|   a="1"
        \\|   b="2"
        \\|   <svg svg>
        \\|     viewBox="0"
        \\|     xlink href="x"
        \\|     xml lang="en"
        \\|     xmlns xmlns="y"
        \\|   <math mi>
        \\|   "a
        \\b"
        \\|   <!--  c  -->
        \\|   <?t ?>
    ++ "\n", y1);

    // Y2.
    var discard_buffer: [64]u8 = undefined;
    var discard: Writer.Discarding = .init(&discard_buffer);
    const plain = try s.createElement(document, null, asciiView("x"));
    try s.appendChild(svg, plain);
    try testing.expectError(error.UndumpableNamespace, tree_dump.writeChildren(s, document, &discard.writer));
    try s.removeChild(svg, plain);
    try s.setAttribute(svg, asciiView("urn:x"), asciiView("y"), asciiView("z"));
    try testing.expectError(error.UndumpableNamespace, tree_dump.writeChildren(s, document, &discard.writer));
    const empty = try s.createHtmlDocument();
    const nothing = try dumpOf(gpa, s, empty);
    defer gpa.free(nothing);
    try testing.expectEqualStrings("", nothing);
    try dom.expectInvariants(s);
}

test "FP-0100 case 4: each DOCTYPE gives its document mode, doctype, and errors" {
    try checkTable(&doctypes);
}

test "FP-0100 case 5: whole documents" {
    try checkTable(&documents);
}

test "FP-0100 case 6: the mode walks" {
    try checkTable(&walks);
}

test "FP-0100 case 7: in body and the head modes" {
    try checkTable(&body_cases);
}

test "FP-0100 case 8: formatting elements and the adoption agency algorithm" {
    try checkTable(&formatting_cases);
}

/// Parses `input` as one chunk and returns the parser and store through `harness`. The caller drives `run`.
const Harness = struct {
    store: dom.Store,
    parser: html.Parser,
    input: []u16,

    fn init(h: *Harness, gpa: Allocator, case: Case) !void {
        h.input = try units(gpa, case.input);
        errdefer gpa.free(h.input);
        h.store = try dom.Store.init(gpa);
        errdefer h.store.deinit();
        h.parser = try html.Parser.init(gpa, &h.store, .{ .scripting = case.scripting });
        try h.parser.feed(h.input);
        try h.parser.finish();
    }

    fn deinit(h: *Harness, gpa: Allocator) void {
        h.parser.deinit();
        h.store.deinit();
        gpa.free(h.input);
    }

    fn dump(h: *Harness, gpa: Allocator) ![]u8 {
        return dumpOf(gpa, &h.store, h.parser.document());
    }
};

fn expectScriptState(state: ?html.ScriptState, document: dom.NodeHandle, already_started: bool) !void {
    const actual = state orelse return error.TestUnexpectedResult;
    try testing.expect(std.meta.eql(actual.parser_document.?, document));
    try testing.expect(!actual.force_async);
    try testing.expectEqual(already_started, actual.already_started);
}

test "FP-0100 case 9: a script end tag returns a script boundary before any later character, and the next run continues" {
    try checkTable(&script_cases);
    const gpa = testing.allocator;

    // S1: the dump at the boundary has no "c".
    {
        var h: Harness = undefined;
        try h.init(gpa, find("S1"));
        defer h.deinit(gpa);
        const boundary = try h.parser.run();
        try testing.expect(boundary == .script);
        try testing.expectEqual(@as(usize, 22), @backingInt(boundary.script.offset));
        const at_boundary = try h.dump(gpa);
        defer gpa.free(at_boundary);
        try testing.expectEqualStrings(s1_boundary_dump, at_boundary);
        try expectScriptState(h.parser.scriptState(boundary.script.element), h.parser.document(), false);
        try testing.expectEqual(html.Outcome.done, try h.parser.run());
        try dom.expectInvariants(&h.store);
    }

    // S2: the end-of-file token in the text mode sets already started.
    {
        var h: Harness = undefined;
        try h.init(gpa, find("S2"));
        defer h.deinit(gpa);
        try testing.expectEqual(html.Outcome.done, try h.parser.run());
        const head = (try h.store.firstChild((try h.store.firstChild(h.parser.document())).?)).?;
        const script = (try h.store.firstChild(head)).?;
        try expectScriptState(h.parser.scriptState(script), h.parser.document(), true);
        try testing.expectEqual(null, h.parser.scriptState(head));
        try dom.expectInvariants(&h.store);
    }

    // W3 covers the boundary with scripting disabled.
    {
        var h: Harness = undefined;
        try h.init(gpa, find("W3"));
        defer h.deinit(gpa);
        const boundary = try h.parser.run();
        try testing.expect(boundary == .script);
        try testing.expectEqual(@as(usize, 171), @backingInt(boundary.script.offset));
        const name = (try h.store.elementName(boundary.script.element)).?;
        try testing.expect(name.local_name.eql(asciiView("script")));
        try expectScriptState(h.parser.scriptState(boundary.script.element), h.parser.document(), false);
        try testing.expectEqual(null, h.parser.scriptState((try h.store.lastChild(h.parser.document())).?));
        try testing.expectEqual(html.Outcome.done, try h.parser.run());
        try dom.expectInvariants(&h.store);
    }
}

test "FP-0100 case 10: unsupported features report their owners, repeat on a second run, and keep the tree, and frameset-ok decides a frameset" {
    try checkTable(&unsupported_cases);
    const gpa = testing.allocator;
    for (unsupported_owners) |row| {
        var h: Harness = undefined;
        try h.init(gpa, find(row.id));
        defer h.deinit(gpa);
        const first = try h.parser.run();
        try testing.expect(first == .unsupported);
        try testing.expectEqualStrings(row.owner, html.unsupportedOwner(first.unsupported.feature));
        try testing.expect(sameOutcome(first, try h.parser.run()));
    }
    try testing.expectEqualStrings("FP-0102", html.unsupportedOwner(.{ .mode = .in_cell }));
    try testing.expectEqualStrings("FP-0103", html.unsupportedOwner(.template_start_tag));
    try testing.expectEqualStrings("FP-0104", html.unsupportedOwner(.foreign_start_tag));
}

test "FP-0100 case 11: cases 4 to 10 execute every one of the 130 branches of the ten modes" {
    @memset(&tree.coverage, 0);
    for (tables) |table| {
        for (table) |case| _ = try checkCase("FP-0100", case);
    }
    var missing: usize = 0;
    for (tree.coverage, 0..) |count, index| {
        if (count != 0) continue;
        const branch = modes.branchAt(index);
        std.debug.print("FP-0100 case 11: branch \"{s}\" of {s} never ran\n", .{ branch.name, modes.title(branch.mode) });
        missing += 1;
    }
    try testing.expectEqual(@as(usize, 0), missing);
}

test "FP-0100 case 13: the parser retains every node that it references, and a sweep frees none of them" {
    const gpa = testing.allocator;
    // R1.
    {
        var h: Harness = undefined;
        try h.init(gpa, find("S1"));
        defer h.store.deinit();
        defer gpa.free(h.input);
        const boundary = try h.parser.run();
        try testing.expect(boundary == .script);
        try testing.expectEqual(@as(usize, 22), @backingInt(boundary.script.offset));
        const document_element = (try h.store.lastChild(h.parser.document())).?;
        const body = (try h.store.lastChild(document_element)).?;
        const paragraph = (try h.store.firstChild(body)).?;
        try h.store.removeChild(body, paragraph);
        try testing.expectEqual(@as(usize, 0), h.store.sweep());
        try dom.expectInvariants(&h.store);
        try testing.expectEqual(html.Outcome.done, try h.parser.run());
        const document_dump = try h.dump(gpa);
        defer gpa.free(document_dump);
        try testing.expectEqualStrings(html_head_body, document_dump);
        const detached = try dumpOf(gpa, &h.store, paragraph);
        defer gpa.free(detached);
        try testing.expectEqualStrings("| \"a\"\n| <script>\n|   \"b\"\n| \"c\"\n", detached);
        try dom.expectInvariants(&h.store);
        h.parser.deinit();
        try testing.expectEqual(@as(usize, 5), h.store.sweep());
        try dom.expectInvariants(&h.store);
    }
    // R2.
    {
        var store = try dom.Store.init(gpa);
        defer store.deinit();
        var parser = try html.Parser.init(gpa, &store, .{ .scripting = .disabled });
        defer parser.deinit();
        try store.appendChild(parser.document(), try store.createElement(parser.document(), html_namespace, asciiView("div")));
        const input = [_]u16{'x'};
        try parser.feed(&input);
        try parser.finish();
        try testing.expectError(error.HierarchyRequest, parser.run());
        try testing.expectError(error.HierarchyRequest, parser.run());
        try testing.expectError(error.HierarchyRequest, parser.feed(&.{}));
        try testing.expectError(error.HierarchyRequest, parser.finish());
        try testing.expectEqual(@as(usize, 1), parser.errors().len);
        try testing.expectEqual(null, parser.errors()[0].code);
        try testing.expectEqual(@as(usize, 1), parser.errors()[0].position.line);
        try testing.expectEqual(@as(usize, 1), parser.errors()[0].position.column);
        try testing.expectEqual(@as(usize, 0), @backingInt(parser.errors()[0].position.offset));
        try testing.expectEqual(dom.DocumentMode.quirks, try store.documentMode(parser.document()));
        const dumped = try dumpOf(gpa, &store, parser.document());
        defer gpa.free(dumped);
        try testing.expectEqualStrings("| <div>\n", dumped);
        try dom.expectInvariants(&store);
    }
}

/// Returns `err` after checking that the store's invariants hold and that every later `feed`, `finish`, and `run`
/// returns `error.OutOfMemory` again.
fn again(store: *dom.Store, parser: *html.Parser, err: html.ParserError) anyerror {
    if (err != error.OutOfMemory) return err;
    try dom.expectInvariants(store);
    try testing.expectError(error.OutOfMemory, parser.feed(&.{}));
    try testing.expectError(error.OutOfMemory, parser.finish());
    try testing.expectError(error.OutOfMemory, parser.run());
    return err;
}

const allocation_input = blk: {
    const text = "<a>1<b>2<p>3</a>4";
    var buffer: [text.len]u16 = undefined;
    for (text, &buffer) |byte, *unit| unit.* = byte;
    break :blk buffer;
};

/// Parses A2 in two chunks split at offset 8. The store and the parser allocate with `gpa`; the dump and the record
/// allocate with `record_gpa`, which never fails.
fn parseUnderAllocationFailure(gpa: Allocator, record_gpa: Allocator) !void {
    var store = try dom.Store.init(gpa);
    defer store.deinit();
    var parser = try html.Parser.init(gpa, &store, .{ .scripting = .disabled });
    defer parser.deinit();
    const s = &store;
    const p = &parser;
    p.feed(allocation_input[0..8]) catch |err| return again(s, p, err);
    if ((p.run() catch |err| return again(s, p, err)) != .need_input) return error.TestUnexpectedResult;
    p.feed(allocation_input[8..]) catch |err| return again(s, p, err);
    if ((p.run() catch |err| return again(s, p, err)) != .need_input) return error.TestUnexpectedResult;
    p.finish() catch |err| return again(s, p, err);
    const outcome = p.run() catch |err| return again(s, p, err);
    try testing.expectEqual(html.Outcome.done, outcome);
    try dom.expectInvariants(&store);
    var out: Writer.Allocating = .init(record_gpa);
    defer out.deinit();
    const outcomes = [_]html.Outcome{outcome};
    try writeRecord(&out.writer, &store, &parser, &outcomes);
    const expected = try expectedRecord(record_gpa, find("A2"));
    defer record_gpa.free(expected);
    try testing.expectEqualStrings(expected, out.written());
}

test "FP-0100 case 14: each induced allocation failure returns OutOfMemory, every later call returns it again, and nothing leaks" {
    // Fail every remap so that each growth step is an allocation the checker can induce.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_remap.allocator(), parseUnderAllocationFailure, .{testing.allocator});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}
