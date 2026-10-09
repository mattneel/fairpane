//! FP-0123 contract cases 1 to 13, the text scan of case 14, and case 16.
//!
//! Inputs are bytes, and outputs are UTF-16 code units.
//! `E` is one decoder error, which "replacement" mode writes as U+FFFD.

const std = @import("std");
const encoding = @import("root.zig");
const testing = std.testing;
const Encoding = encoding.Encoding;
const ErrorMode = encoding.ErrorMode;
const Status = encoding.Status;
const Result = encoding.Result;

const E: u16 = 0xFFFD;

/// The frozen §4.2 table of the contract, transcribed separately from `labels.zig`.
const frozen_table = [_]struct { name: []const u8, labels: []const []const u8 }{
    .{ .name = "UTF-8", .labels = &.{ "unicode-1-1-utf-8", "unicode11utf8", "unicode20utf8", "utf-8", "utf8", "x-unicode20utf8" } },
    .{ .name = "IBM866", .labels = &.{ "866", "cp866", "csibm866", "ibm866" } },
    .{ .name = "ISO-8859-2", .labels = &.{ "csisolatin2", "iso-8859-2", "iso-ir-101", "iso8859-2", "iso88592", "iso_8859-2", "iso_8859-2:1987", "l2", "latin2" } },
    .{ .name = "ISO-8859-3", .labels = &.{ "csisolatin3", "iso-8859-3", "iso-ir-109", "iso8859-3", "iso88593", "iso_8859-3", "iso_8859-3:1988", "l3", "latin3" } },
    .{ .name = "ISO-8859-4", .labels = &.{ "csisolatin4", "iso-8859-4", "iso-ir-110", "iso8859-4", "iso88594", "iso_8859-4", "iso_8859-4:1988", "l4", "latin4" } },
    .{ .name = "ISO-8859-5", .labels = &.{ "csisolatincyrillic", "cyrillic", "iso-8859-5", "iso-ir-144", "iso8859-5", "iso88595", "iso_8859-5", "iso_8859-5:1988" } },
    .{ .name = "ISO-8859-6", .labels = &.{ "arabic", "asmo-708", "csiso88596e", "csiso88596i", "csisolatinarabic", "ecma-114", "iso-8859-6", "iso-8859-6-e", "iso-8859-6-i", "iso-ir-127", "iso8859-6", "iso88596", "iso_8859-6", "iso_8859-6:1987" } },
    .{ .name = "ISO-8859-7", .labels = &.{ "csisolatingreek", "ecma-118", "elot_928", "greek", "greek8", "iso-8859-7", "iso-ir-126", "iso8859-7", "iso88597", "iso_8859-7", "iso_8859-7:1987", "sun_eu_greek" } },
    .{ .name = "ISO-8859-8", .labels = &.{ "csiso88598e", "csisolatinhebrew", "hebrew", "iso-8859-8", "iso-8859-8-e", "iso-ir-138", "iso8859-8", "iso88598", "iso_8859-8", "iso_8859-8:1988", "visual" } },
    .{ .name = "ISO-8859-8-I", .labels = &.{ "csiso88598i", "iso-8859-8-i", "logical" } },
    .{ .name = "ISO-8859-10", .labels = &.{ "csisolatin6", "iso-8859-10", "iso-ir-157", "iso8859-10", "iso885910", "l6", "latin6" } },
    .{ .name = "ISO-8859-13", .labels = &.{ "iso-8859-13", "iso8859-13", "iso885913" } },
    .{ .name = "ISO-8859-14", .labels = &.{ "iso-8859-14", "iso8859-14", "iso885914" } },
    .{ .name = "ISO-8859-15", .labels = &.{ "csisolatin9", "iso-8859-15", "iso8859-15", "iso885915", "iso_8859-15", "l9" } },
    .{ .name = "ISO-8859-16", .labels = &.{"iso-8859-16"} },
    .{ .name = "KOI8-R", .labels = &.{ "cskoi8r", "koi", "koi8", "koi8-r", "koi8_r" } },
    .{ .name = "KOI8-U", .labels = &.{ "koi8-ru", "koi8-u" } },
    .{ .name = "macintosh", .labels = &.{ "csmacintosh", "mac", "macintosh", "x-mac-roman" } },
    .{ .name = "windows-874", .labels = &.{ "dos-874", "iso-8859-11", "iso8859-11", "iso885911", "tis-620", "windows-874" } },
    .{ .name = "windows-1250", .labels = &.{ "cp1250", "windows-1250", "x-cp1250" } },
    .{ .name = "windows-1251", .labels = &.{ "cp1251", "windows-1251", "x-cp1251" } },
    .{ .name = "windows-1252", .labels = &.{ "ansi_x3.4-1968", "ascii", "cp1252", "cp819", "csisolatin1", "ibm819", "iso-8859-1", "iso-ir-100", "iso8859-1", "iso88591", "iso_8859-1", "iso_8859-1:1987", "l1", "latin1", "us-ascii", "windows-1252", "x-cp1252" } },
    .{ .name = "windows-1253", .labels = &.{ "cp1253", "windows-1253", "x-cp1253" } },
    .{ .name = "windows-1254", .labels = &.{ "cp1254", "csisolatin5", "iso-8859-9", "iso-ir-148", "iso8859-9", "iso88599", "iso_8859-9", "iso_8859-9:1989", "l5", "latin5", "windows-1254", "x-cp1254" } },
    .{ .name = "windows-1255", .labels = &.{ "cp1255", "windows-1255", "x-cp1255" } },
    .{ .name = "windows-1256", .labels = &.{ "cp1256", "windows-1256", "x-cp1256" } },
    .{ .name = "windows-1257", .labels = &.{ "cp1257", "windows-1257", "x-cp1257" } },
    .{ .name = "windows-1258", .labels = &.{ "cp1258", "windows-1258", "x-cp1258" } },
    .{ .name = "x-mac-cyrillic", .labels = &.{ "x-mac-cyrillic", "x-mac-ukrainian" } },
    .{ .name = "GBK", .labels = &.{ "chinese", "csgb2312", "csiso58gb231280", "gb2312", "gb_2312", "gb_2312-80", "gbk", "iso-ir-58", "x-gbk" } },
    .{ .name = "gb18030", .labels = &.{"gb18030"} },
    .{ .name = "Big5", .labels = &.{ "big5", "big5-hkscs", "cn-big5", "csbig5", "x-x-big5" } },
    .{ .name = "EUC-JP", .labels = &.{ "cseucpkdfmtjapanese", "euc-jp", "x-euc-jp" } },
    .{ .name = "ISO-2022-JP", .labels = &.{ "csiso2022jp", "iso-2022-jp" } },
    .{ .name = "Shift_JIS", .labels = &.{ "csshiftjis", "ms932", "ms_kanji", "shift-jis", "shift_jis", "sjis", "windows-31j", "x-sjis" } },
    .{ .name = "EUC-KR", .labels = &.{ "cseuckr", "csksc56011987", "euc-kr", "iso-ir-149", "korean", "ks_c_5601-1987", "ks_c_5601-1989", "ksc5601", "ksc_5601", "windows-949" } },
    .{ .name = "replacement", .labels = &.{ "csiso2022kr", "hz-gb-2312", "iso-2022-cn", "iso-2022-cn-ext", "iso-2022-kr", "replacement" } },
    .{ .name = "UTF-16BE", .labels = &.{ "unicodefffe", "utf-16be" } },
    .{ .name = "UTF-16LE", .labels = &.{ "csunicode", "iso-10646-ucs-2", "ucs-2", "unicode", "unicodefeff", "utf-16", "utf-16le" } },
    .{ .name = "x-user-defined", .labels = &.{"x-user-defined"} },
};

test "FP-0123 case 1: name gives the 40 names in table order, and fromName is exact and case-sensitive" {
    const all = std.enums.values(Encoding);
    try testing.expectEqual(@as(usize, 40), all.len);
    try testing.expectEqual(frozen_table.len, all.len);
    for (all, frozen_table) |e, row| {
        try testing.expectEqualStrings(row.name, encoding.name(e));
        try testing.expectEqual(@as(?Encoding, e), encoding.fromName(encoding.name(e)));
    }
    try testing.expectEqual(@as(?Encoding, null), encoding.fromName("utf-8"));
    try testing.expectEqual(@as(?Encoding, null), encoding.fromName("Utf-8"));
}

test "FP-0123 case 2: labels equals the frozen table, with 228 unique lowercase ASCII labels that include each lowercased name" {
    var all_labels: [228][]const u8 = undefined;
    var count: usize = 0;
    for (std.enums.values(Encoding), frozen_table) |e, row| {
        const observed = encoding.labels(e);
        try testing.expectEqual(row.labels.len, observed.len);
        for (row.labels, observed) |expected, label| try testing.expectEqualStrings(expected, label);

        var buffer: [32]u8 = undefined;
        const lowered = std.ascii.lowerString(&buffer, encoding.name(e));
        var found = false;
        for (observed) |label| {
            try testing.expect(label.len != 0);
            for (label) |byte| try testing.expect(byte >= 0x21 and byte <= 0x7E and !std.ascii.isUpper(byte));
            if (std.mem.eql(u8, label, lowered)) found = true;
            try testing.expect(count < all_labels.len);
            all_labels[count] = label;
            count += 1;
        }
        try testing.expect(found);
    }
    try testing.expectEqual(@as(usize, 228), count);
    for (all_labels, 0..) |label, index| {
        for (all_labels[0..index]) |earlier| try testing.expect(!std.mem.eql(u8, earlier, label));
    }
}

/// Checks `getEncoding` for `label` as bytes and as code units of the same values.
fn expectGet(expected: ?Encoding, label: []const u8) !void {
    errdefer std.debug.print("getEncoding label: \"{f}\"\n", .{std.zig.fmtString(label)});
    try testing.expectEqual(expected, encoding.getEncoding(u8, label));
    var units: [64]u16 = undefined;
    for (label, 0..) |byte, index| units[index] = byte;
    try testing.expectEqual(expected, encoding.getEncoding(u16, units[0..label.len]));
}

test "FP-0123 case 3: getEncoding trims ASCII whitespace and matches labels ASCII case-insensitively, for u8 and u16" {
    const whitespace = "\x09\x0A\x0C\x0D\x20";
    for (std.enums.values(Encoding)) |e| {
        for (encoding.labels(e)) |label| {
            try expectGet(e, label);
            var upper: [32]u8 = undefined;
            try expectGet(e, std.ascii.upperString(&upper, label));
            var padded: [64]u8 = undefined;
            const surrounded = try std.fmt.bufPrint(&padded, "{s}{s}{s}", .{ whitespace, label, whitespace });
            try expectGet(e, surrounded);
        }
    }

    const unmatched = [_][]const u8{
        "",
        "\x20",
        "\x0Butf-8",
        "utf-8\x00",
        "utf-32",
        "utf-7",
        "utf_8",
        "latin9",
        "iso-8859-8 visual",
        "x-user-defined\xC2\xA0",
    };
    for (unmatched) |label| try expectGet(null, label);

    // U+212A KELVIN SIGN and U+017F LATIN SMALL LETTER LONG S fold to ASCII letters only under Unicode case rules.
    const unmatched_units = [_][]const u16{
        &.{ 0x212A, 'o', 'i', '8', '-', 'r' },
        &.{ 0x017F, 'j', 'i', 's' },
        &.{ 'x', '-', 'u', 's', 'e', 'r', '-', 'd', 'e', 'f', 'i', 'n', 'e', 'd', 0x00A0 },
    };
    for (unmatched_units) |units| try testing.expectEqual(@as(?Encoding, null), encoding.getEncoding(u16, units));

    const spots = [_]struct { label: []const u8, encoding: Encoding }{
        .{ .label = "utf-16", .encoding = .utf_16le },
        .{ .label = "unicode", .encoding = .utf_16le },
        .{ .label = "unicodefffe", .encoding = .utf_16be },
        .{ .label = "latin1", .encoding = .windows_1252 },
        .{ .label = "ascii", .encoding = .windows_1252 },
        .{ .label = "us-ascii", .encoding = .windows_1252 },
        .{ .label = "logical", .encoding = .iso_8859_8_i },
        .{ .label = "visual", .encoding = .iso_8859_8 },
        .{ .label = "iso-2022-kr", .encoding = .replacement },
        .{ .label = "x-mac-ukrainian", .encoding = .x_mac_cyrillic },
        .{ .label = "tis-620", .encoding = .windows_874 },
    };
    for (spots) |spot| try expectGet(spot.encoding, spot.label);
}

test "FP-0123 case 4: outputEncoding maps replacement, UTF-16BE, and UTF-16LE to UTF-8 and every other encoding to itself" {
    for (std.enums.values(Encoding)) |e| {
        const expected: Encoding = switch (e) {
            .replacement, .utf_16be, .utf_16le => .utf_8,
            else => e,
        };
        try testing.expectEqual(expected, encoding.outputEncoding(e));
    }
}

/// The decoder or hook that a row runs.
const Subject = union(enum) {
    decoder: struct { encoding: Encoding, mode: ErrorMode },
    /// The "decode" hook with this fallback encoding.
    decode: Encoding,
    utf8: encoding.Utf8Decode.Kind,
};

const Machine = union(enum) {
    decoder: encoding.Decoder,
    decode: encoding.Decode,
    utf8: encoding.Utf8Decode,

    fn init(subject: Subject) !Machine {
        return switch (subject) {
            .decoder => |d| .{ .decoder = try encoding.Decoder.init(d.encoding, d.mode) },
            .decode => |fallback| .{ .decode = .init(fallback) },
            .utf8 => |kind| .{ .utf8 = .init(kind) },
        };
    }

    fn call(m: *Machine, input: []const u8, output: []u16, last: bool) !Result {
        return switch (m.*) {
            .decoder => |*d| d.decode(input, output, last),
            .decode => |*d| try d.decode(input, output, last),
            .utf8 => |*d| d.decode(input, output, last),
        };
    }
};

const Row = struct {
    id: []const u8,
    subject: Subject,
    input: []const u8,
    output: []const u16,
    errors: usize = 0,
    status: Status = .finished,
    /// The `read` of a `malformed` row; a `finished` row reads its whole input.
    read: ?usize = null,
    /// The encoding and byte order mark length that a "decode" row decides.
    decided: ?struct { encoding: Encoding, bom: u2 } = null,
};

fn decoderSubject(e: Encoding, mode: ErrorMode) Subject {
    return .{ .decoder = .{ .encoding = e, .mode = mode } };
}

const utf_8 = decoderSubject(.utf_8, .replacement);
const utf_16le = decoderSubject(.utf_16le, .replacement);
const utf_16be = decoderSubject(.utf_16be, .replacement);
const replacement = decoderSubject(.replacement, .replacement);
const x_user_defined = decoderSubject(.x_user_defined, .replacement);
const utf_8_fatal = decoderSubject(.utf_8, .fatal);
const utf_16le_fatal = decoderSubject(.utf_16le, .fatal);
const utf_16be_fatal = decoderSubject(.utf_16be, .fatal);

const case_5_rows = [_]Row{
    .{ .id = "A1", .subject = utf_8, .input = "", .output = &.{} },
    .{ .id = "A2", .subject = utf_8, .input = "\x41", .output = &.{0x0041} },
    .{ .id = "A3", .subject = utf_8, .input = "\x00", .output = &.{0x0000} },
    .{ .id = "A4", .subject = utf_8, .input = "\x7F\x80", .output = &.{ 0x007F, E }, .errors = 1 },
    .{ .id = "A5", .subject = utf_8, .input = "\xC2\x80", .output = &.{0x0080} },
    .{ .id = "A6", .subject = utf_8, .input = "\xDF\xBF", .output = &.{0x07FF} },
    .{ .id = "A7", .subject = utf_8, .input = "\xE0\xA0\x80", .output = &.{0x0800} },
    .{ .id = "A8", .subject = utf_8, .input = "\xED\x9F\xBF", .output = &.{0xD7FF} },
    .{ .id = "A9", .subject = utf_8, .input = "\xEE\x80\x80", .output = &.{0xE000} },
    .{ .id = "A10", .subject = utf_8, .input = "\xEF\xBF\xBF", .output = &.{0xFFFF} },
    .{ .id = "A11", .subject = utf_8, .input = "\xF0\x90\x80\x80", .output = &.{ 0xD800, 0xDC00 } },
    .{ .id = "A12", .subject = utf_8, .input = "\xF4\x8F\xBF\xBF", .output = &.{ 0xDBFF, 0xDFFF } },
    .{ .id = "A13", .subject = utf_8, .input = "\xF0\x9F\x92\xA9", .output = &.{ 0xD83D, 0xDCA9 } },
    .{ .id = "A14", .subject = utf_8, .input = "\xEF\xBF\xBD", .output = &.{0xFFFD} },
    .{ .id = "A15", .subject = utf_8, .input = "\xEF\xBB\xBF\x41", .output = &.{ 0xFEFF, 0x0041 } },
    .{ .id = "A16", .subject = utf_8, .input = "\xC0\x80", .output = &.{ E, E }, .errors = 2 },
    .{ .id = "A17", .subject = utf_8, .input = "\xC1\xBF", .output = &.{ E, E }, .errors = 2 },
    .{ .id = "A18", .subject = utf_8, .input = "\xE0\x80\x80", .output = &.{ E, E, E }, .errors = 3 },
    .{ .id = "A19", .subject = utf_8, .input = "\xE0\x9F\xBF", .output = &.{ E, E, E }, .errors = 3 },
    .{ .id = "A20", .subject = utf_8, .input = "\xED\xA0\x80", .output = &.{ E, E, E }, .errors = 3 },
    .{ .id = "A21", .subject = utf_8, .input = "\xED\xBF\xBF", .output = &.{ E, E, E }, .errors = 3 },
    .{ .id = "A22", .subject = utf_8, .input = "\xF0\x80\x80\x80", .output = &.{ E, E, E, E }, .errors = 4 },
    .{ .id = "A23", .subject = utf_8, .input = "\xF0\x8F\xBF\xBF", .output = &.{ E, E, E, E }, .errors = 4 },
    .{ .id = "A24", .subject = utf_8, .input = "\xF4\x90\x80\x80", .output = &.{ E, E, E, E }, .errors = 4 },
    .{ .id = "A25", .subject = utf_8, .input = "\xF5\x80\x80\x80", .output = &.{ E, E, E, E }, .errors = 4 },
    .{ .id = "A26", .subject = utf_8, .input = "\xF8\x88\x80\x80\x80", .output = &.{ E, E, E, E, E }, .errors = 5 },
    .{ .id = "A27", .subject = utf_8, .input = "\xFE\xFF", .output = &.{ E, E }, .errors = 2 },
    .{ .id = "A28", .subject = utf_8, .input = "\xC2\x41", .output = &.{ E, 0x0041 }, .errors = 1 },
    .{ .id = "A29", .subject = utf_8, .input = "\xE2\x82\x41", .output = &.{ E, 0x0041 }, .errors = 1 },
    .{ .id = "A30", .subject = utf_8, .input = "\xF0\x9F\x92\x41", .output = &.{ E, 0x0041 }, .errors = 1 },
    .{ .id = "A31", .subject = utf_8, .input = "\xE2\x82", .output = &.{E}, .errors = 1 },
    .{ .id = "A32", .subject = utf_8, .input = "\xF0\x9F\x92", .output = &.{E}, .errors = 1 },
    .{ .id = "A33", .subject = utf_8, .input = "\xC2", .output = &.{E}, .errors = 1 },
    .{ .id = "A34", .subject = utf_8, .input = "\x80\xBF", .output = &.{ E, E }, .errors = 2 },
    .{
        .id = "A35",
        .subject = utf_8,
        .input = "\x61\xF1\x80\x80\xE1\x80\xC2\x62\x80\x63\x80\xBF\x64",
        .output = &.{ 0x0061, E, E, E, 0x0062, E, 0x0063, E, E, 0x0064 },
        .errors = 6,
    },
    .{ .id = "A36", .subject = utf_8, .input = "\xF4\x8F\xBF\xC0", .output = &.{ E, E }, .errors = 2 },
};

const case_6_rows = [_]Row{
    .{ .id = "B1", .subject = utf_16le, .input = "", .output = &.{} },
    .{ .id = "B2", .subject = utf_16le, .input = "\x41\x00", .output = &.{0x0041} },
    .{ .id = "B3", .subject = utf_16le, .input = "\xFF\xFE", .output = &.{0xFEFF} },
    .{ .id = "B4", .subject = utf_16le, .input = "\x3D\xD8\xA9\xDC", .output = &.{ 0xD83D, 0xDCA9 } },
    .{ .id = "B5", .subject = utf_16le, .input = "\x00\xD8\x00\xDC", .output = &.{ 0xD800, 0xDC00 } },
    .{ .id = "B6", .subject = utf_16le, .input = "\xFF\xDB\xFF\xDF", .output = &.{ 0xDBFF, 0xDFFF } },
    .{ .id = "B7", .subject = utf_16le, .input = "\x3D\xD8\x41\x00", .output = &.{ E, 0x0041 }, .errors = 1 },
    .{ .id = "B8", .subject = utf_16le, .input = "\x00\xDC", .output = &.{E}, .errors = 1 },
    .{ .id = "B9", .subject = utf_16le, .input = "\x00\xDC\x41\x00", .output = &.{ E, 0x0041 }, .errors = 1 },
    .{ .id = "B10", .subject = utf_16le, .input = "\x41", .output = &.{E}, .errors = 1 },
    .{ .id = "B11", .subject = utf_16le, .input = "\x3D\xD8", .output = &.{E}, .errors = 1 },
    .{ .id = "B12", .subject = utf_16le, .input = "\x3D\xD8\x41", .output = &.{E}, .errors = 1 },
    .{ .id = "B13", .subject = utf_16le, .input = "\x3D\xD8\x3D\xD8\xA9\xDC", .output = &.{ E, 0xD83D, 0xDCA9 }, .errors = 1 },
    .{ .id = "B14", .subject = utf_16le, .input = "\xFF\xD7\x00\xE0", .output = &.{ 0xD7FF, 0xE000 } },
    .{ .id = "B15", .subject = utf_16le, .input = "\x00\xDC\x00\xD8", .output = &.{ E, E }, .errors = 2 },
    .{ .id = "C1", .subject = utf_16be, .input = "\x00\x41", .output = &.{0x0041} },
    .{ .id = "C2", .subject = utf_16be, .input = "\xFE\xFF", .output = &.{0xFEFF} },
    .{ .id = "C3", .subject = utf_16be, .input = "\xD8\x3D\xDC\xA9", .output = &.{ 0xD83D, 0xDCA9 } },
    .{ .id = "C4", .subject = utf_16be, .input = "\xD8\x3D\x00\x41", .output = &.{ E, 0x0041 }, .errors = 1 },
    .{ .id = "C5", .subject = utf_16be, .input = "\xDC\x00", .output = &.{E}, .errors = 1 },
    .{ .id = "C6", .subject = utf_16be, .input = "\x00", .output = &.{E}, .errors = 1 },
    .{ .id = "C7", .subject = utf_16be, .input = "\xD8\x3D", .output = &.{E}, .errors = 1 },
    .{ .id = "C8", .subject = utf_16be, .input = "\xD8\x3D\x00", .output = &.{E}, .errors = 1 },
};

const case_7_rows = [_]Row{
    .{ .id = "D1", .subject = replacement, .input = "", .output = &.{} },
    .{ .id = "D2", .subject = replacement, .input = "\x41", .output = &.{E}, .errors = 1 },
    .{ .id = "D3", .subject = replacement, .input = "\x41\x42\x43", .output = &.{E}, .errors = 1 },
    .{ .id = "D4", .subject = replacement, .input = "\xEF\xBB\xBF", .output = &.{E}, .errors = 1 },
    .{
        .id = "X1",
        .subject = x_user_defined,
        .input = "\x00\x41\x7F\x80\x81\xFE\xFF",
        .output = &.{ 0x0000, 0x0041, 0x007F, 0xF780, 0xF781, 0xF7FE, 0xF7FF },
    },
};

const case_8_rows = [_]Row{
    .{ .id = "F1", .subject = utf_8_fatal, .input = "\x41\x42", .output = &.{ 0x0041, 0x0042 } },
    .{ .id = "F2", .subject = utf_8_fatal, .input = "\x41\xC2\x41\x42", .output = &.{0x0041}, .errors = 1, .status = .malformed, .read = 3 },
    .{ .id = "F3", .subject = utf_8_fatal, .input = "\x41\xFF\x42", .output = &.{0x0041}, .errors = 1, .status = .malformed, .read = 2 },
    .{ .id = "F4", .subject = utf_8_fatal, .input = "\xF0\x9F\x92", .output = &.{}, .errors = 1, .status = .malformed, .read = 3 },
    .{ .id = "F5", .subject = utf_16le_fatal, .input = "\x41\x00\x00\xDC", .output = &.{0x0041}, .errors = 1, .status = .malformed, .read = 4 },
    .{ .id = "F8", .subject = utf_16be_fatal, .input = "\x00\x41\xDC\x00", .output = &.{0x0041}, .errors = 1, .status = .malformed, .read = 4 },
};

fn decodeRow(id: []const u8, input: []const u8, fallback: Encoding, decided: Encoding, bom: u2, output: []const u16, errors: usize) Row {
    return .{ .id = id, .subject = .{ .decode = fallback }, .input = input, .output = output, .errors = errors, .decided = .{ .encoding = decided, .bom = bom } };
}

const case_9_rows = [_]Row{
    decodeRow("G1", "\xEF\xBB\xBF\x41", .utf_8, .utf_8, 3, &.{0x0041}, 0),
    decodeRow("G2", "\xEF\xBB\xBF\x41", .utf_16le, .utf_8, 3, &.{0x0041}, 0),
    decodeRow("G3", "\xFE\xFF\x00\x41", .utf_8, .utf_16be, 2, &.{0x0041}, 0),
    decodeRow("G4", "\xFF\xFE\x41\x00", .utf_8, .utf_16le, 2, &.{0x0041}, 0),
    decodeRow("G5", "\xEF\xBB\xBF\xEF\xBB\xBF", .utf_8, .utf_8, 3, &.{0xFEFF}, 0),
    decodeRow("G6", "\xFF\xFE\xFF\xFE", .utf_8, .utf_16le, 2, &.{0xFEFF}, 0),
    decodeRow("G7", "\xFE\xFF\xFF\xFE", .utf_8, .utf_16be, 2, &.{0xFFFE}, 0),
    decodeRow("G8", "\xEF\xBB", .utf_8, .utf_8, 0, &.{E}, 1),
    decodeRow("G9", "\xFF\xFE", .utf_8, .utf_16le, 2, &.{}, 0),
    decodeRow("G10", "\xFE", .utf_8, .utf_8, 0, &.{E}, 1),
    decodeRow("G11", "\xFE\xFF\x41", .utf_8, .utf_16be, 2, &.{E}, 1),
    decodeRow("G12", "\x41\x42\x43", .utf_16le, .utf_16le, 0, &.{ 0x4241, E }, 1),
    decodeRow("G13", "\xEF\xBB\xBF", .replacement, .utf_8, 3, &.{}, 0),
    decodeRow("G14", "\x41", .replacement, .replacement, 0, &.{E}, 1),
    decodeRow("G15", "", .utf_8, .utf_8, 0, &.{}, 0),
    decodeRow("G17", "\xFF\xFE\x41\x00", .windows_1252, .utf_16le, 2, &.{0x0041}, 0),
    decodeRow("G18", "\xEF\xBB\xBF\xFE\xFF", .utf_8, .utf_8, 3, &.{ E, E }, 2),
};

const case_10_rows = [_]Row{
    .{ .id = "H1", .subject = .{ .utf8 = .utf8_decode }, .input = "\xEF\xBB\xBF\x41", .output = &.{0x0041} },
    .{ .id = "H2", .subject = .{ .utf8 = .utf8_decode }, .input = "\xFE\xFF\x00\x41", .output = &.{ E, E, 0x0000, 0x0041 }, .errors = 2 },
    .{ .id = "H3", .subject = .{ .utf8 = .utf8_decode }, .input = "\xEF\xBB", .output = &.{E}, .errors = 1 },
    .{ .id = "H4", .subject = .{ .utf8 = .utf8_decode }, .input = "\xEF\xBB\xBF\xEF\xBB\xBF", .output = &.{0xFEFF} },
    .{ .id = "H5", .subject = .{ .utf8 = .without_bom }, .input = "\xEF\xBB\xBF\x41", .output = &.{ 0xFEFF, 0x0041 } },
    .{ .id = "H6", .subject = .{ .utf8 = .without_bom_or_fail }, .input = "\x41\x42", .output = &.{ 0x0041, 0x0042 } },
    .{ .id = "H7", .subject = .{ .utf8 = .without_bom_or_fail }, .input = "\x41\xC2", .output = &.{0x0041}, .errors = 1, .status = .malformed, .read = 2 },
    .{ .id = "H8", .subject = .{ .utf8 = .without_bom_or_fail }, .input = "\xEF\xBB\xBF", .output = &.{0xFEFF} },
};

/// Fails when `units` holds a surrogate that is not part of a leading-trailing pair.
fn expectNoUnpairedSurrogate(units: []const u16) !void {
    var index: usize = 0;
    while (index < units.len) : (index += 1) {
        const unit = units[index];
        if (unit >= 0xDC00 and unit <= 0xDFFF) return error.TestUnexpectedResult;
        if (unit >= 0xD800 and unit <= 0xDBFF) {
            index += 1;
            if (index == units.len or units[index] < 0xDC00 or units[index] > 0xDFFF) return error.TestUnexpectedResult;
        }
    }
}

fn expectDecided(row: Row, machine: *const Machine) !void {
    const decided = row.decided orelse return;
    try testing.expectEqual(@as(?Encoding, decided.encoding), machine.decode.encoding());
    try testing.expectEqual(@as(?u2, decided.bom), machine.decode.bomLength());
}

/// Runs `row` in one call with `last` true.
fn expectSingleCall(row: Row) !void {
    errdefer std.debug.print("row {s}: one call\n", .{row.id});
    var machine = try Machine.init(row.subject);
    var output: [64]u16 = undefined;
    const r = try machine.call(row.input, &output, true);
    try testing.expectEqualSlices(u16, row.output, output[0..r.written]);
    try testing.expectEqual(row.errors, r.errors);
    try testing.expectEqual(row.status, r.status);
    try testing.expectEqual(row.read orelse row.input.len, r.read);
    try expectNoUnpairedSurrogate(output[0..r.written]);
    try expectDecided(row, &machine);
}

/// Runs every row in one call and fails after the last row when any row failed, so a failure names every row.
fn expectRows(rows: []const Row) !void {
    var failed: usize = 0;
    for (rows) |row| expectSingleCall(row) catch {
        failed += 1;
    };
    if (failed != 0) return error.TestUnexpectedResult;
}

test "FP-0123 case 5: the UTF-8 decoder in replacement mode" {
    try expectRows(&case_5_rows);
}

test "FP-0123 case 6: the UTF-16LE and UTF-16BE decoders in replacement mode" {
    try expectRows(&case_6_rows);
}

test "FP-0123 case 7: the replacement and x-user-defined decoders" {
    try expectRows(&case_7_rows);

    // D5: the error is returned once, and the next byte finishes the decoder.
    var decoder = try encoding.Decoder.init(.replacement, .replacement);
    var output: [4]u16 = undefined;
    const first = decoder.decode("\x41", &output, false);
    try testing.expectEqual(Result{ .read = 1, .written = 1, .errors = 1, .status = .input_empty }, first);
    try testing.expectEqual(E, output[0]);
    const second = decoder.decode("\x42", &output, true);
    try testing.expectEqual(Result{ .read = 1, .written = 0, .errors = 0, .status = .finished }, second);

    // X2: every byte value in order.
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*byte, value| byte.* = @intCast(value);
    var units: [258]u16 = undefined;
    var user_defined = try encoding.Decoder.init(.x_user_defined, .replacement);
    const r = user_defined.decode(&bytes, &units, true);
    try testing.expectEqual(Result{ .read = 256, .written = 256, .errors = 0, .status = .finished }, r);
    for (units[0..256], 0..) |unit, value| {
        const expected: u16 = if (value < 0x80) @intCast(value) else @intCast(0xF780 + value - 0x80);
        try testing.expectEqual(expected, unit);
    }
}

test "FP-0123 case 8: fatal mode stops at the first error and stays malformed" {
    try expectRows(&case_8_rows);

    // F6: the replacement decoder in fatal mode.
    var output: [4]u16 = undefined;
    var empty = try encoding.Decoder.init(.replacement, .fatal);
    try testing.expectEqual(Result{ .read = 0, .written = 0, .errors = 0, .status = .finished }, empty.decode("", &output, true));
    var nonempty = try encoding.Decoder.init(.replacement, .fatal);
    try testing.expectEqual(Result{ .read = 1, .written = 0, .errors = 1, .status = .malformed }, nonempty.decode("\x41", &output, true));

    // F7: a call after F2 reads and writes nothing.
    var decoder = try encoding.Decoder.init(.utf_8, .fatal);
    try testing.expectEqual(Result{ .read = 3, .written = 1, .errors = 1, .status = .malformed }, decoder.decode("\x41\xC2\x41\x42", &output, true));
    try testing.expectEqual(Result{ .read = 0, .written = 0, .errors = 0, .status = .malformed }, decoder.decode("\x41", &output, true));
    try testing.expectEqual(Result{ .read = 0, .written = 0, .errors = 0, .status = .malformed }, decoder.decode("\x41", &output, false));

    // After `finished`, a call reads its whole input and writes nothing.
    var finished = try encoding.Decoder.init(.utf_8, .fatal);
    try testing.expectEqual(Result{ .read = 1, .written = 1, .errors = 0, .status = .finished }, finished.decode("\x41", &output, true));
    try testing.expectEqual(Result{ .read = 2, .written = 0, .errors = 0, .status = .finished }, finished.decode("\x42\xFF", &output, false));
}

test "FP-0123 case 9: the decode hook sniffs a byte order mark, then decodes in replacement mode" {
    try expectRows(&case_9_rows);
}

test "FP-0123 case 9 G16: a fallback whose decoder belongs to FP-0124 is unsupported" {
    var unsupported: encoding.Decode = .init(.windows_1252);
    var output: [8]u16 = undefined;
    try testing.expectError(error.UnsupportedEncoding, unsupported.decode("\x41", &output, true));
    try testing.expectEqualStrings("FP-0124", encoding.unsupportedOwner(.windows_1252).?);
}

test "FP-0123 case 9 T1: two bytes do not decide the byte order mark before end-of-queue" {
    var output: [8]u16 = undefined;
    var d: encoding.Decode = .init(.utf_8);
    const first = try d.decode("\xFF\xFE", &output, false);
    try testing.expectEqual(@as(usize, 0), first.written);
    try testing.expectEqual(@as(usize, 2), first.read);
    try testing.expectEqual(Status.input_empty, first.status);
    try testing.expectEqual(@as(?Encoding, null), d.encoding());
    try testing.expectEqual(@as(?u2, null), d.bomLength());
    const second = try d.decode("\x41", &output, false);
    try testing.expectEqual(@as(usize, 0), second.written);
    try testing.expectEqual(@as(?Encoding, .utf_16le), d.encoding());
    try testing.expectEqual(@as(?u2, 2), d.bomLength());
    const third = try d.decode("\x00", &output, true);
    try testing.expectEqualSlices(u16, &.{0x0041}, output[0..third.written]);
    try testing.expectEqual(Status.finished, third.status);
}

test "FP-0123 case 9 T2: the byte order mark arrives one byte per call" {
    var output: [8]u16 = undefined;
    var d: encoding.Decode = .init(.utf_8);
    var written: usize = 0;
    for ([_][]const u8{ "\xEF", "\xBB", "\xBF", "\x41" }, 0..) |chunk, index| {
        const r = try d.decode(chunk, output[written..], index == 3);
        try testing.expectEqual(chunk.len, r.read);
        written += r.written;
    }
    try testing.expectEqual(@as(?Encoding, .utf_8), d.encoding());
    try testing.expectEqual(@as(?u2, 3), d.bomLength());
    try testing.expectEqualSlices(u16, &.{0x0041}, output[0..written]);
}

test "FP-0123 case 9 T3: end-of-queue decides on the two bytes that peeking returned" {
    var output: [8]u16 = undefined;
    var d: encoding.Decode = .init(.utf_8);
    const first = try d.decode("\xEF\xBB", &output, false);
    try testing.expectEqual(@as(usize, 0), first.written);
    try testing.expectEqual(@as(?Encoding, null), d.encoding());
    const second = try d.decode("", &output, true);
    try testing.expectEqual(@as(?Encoding, .utf_8), d.encoding());
    try testing.expectEqual(@as(?u2, 0), d.bomLength());
    try testing.expectEqualSlices(u16, &.{E}, output[0..second.written]);
    try testing.expectEqual(@as(usize, 1), second.errors);
}

test "FP-0123 case 10: the UTF-8 decode hooks" {
    try expectRows(&case_10_rows);
}

test "FP-0123 case 11: the 35 index-based encodings are unsupported and name their owning task" {
    var single_byte: usize = 0;
    var multi_byte: usize = 0;
    var implemented: usize = 0;
    for (std.enums.values(Encoding)) |e| {
        const owner = encoding.unsupportedOwner(e);
        switch (e) {
            .utf_8, .replacement, .utf_16be, .utf_16le, .x_user_defined => {
                try testing.expectEqual(@as(?[]const u8, null), owner);
                _ = try encoding.Decoder.init(e, .replacement);
                _ = try encoding.Decoder.init(e, .fatal);
                implemented += 1;
                continue;
            },
            .gbk, .gb18030, .big5, .euc_jp, .iso_2022_jp, .shift_jis, .euc_kr => {
                try testing.expectEqualStrings("FP-0125", owner.?);
                multi_byte += 1;
            },
            else => {
                try testing.expectEqualStrings("FP-0124", owner.?);
                single_byte += 1;
            },
        }
        try testing.expectError(error.UnsupportedEncoding, encoding.Decoder.init(e, .replacement));
        try testing.expectError(error.UnsupportedEncoding, encoding.Decoder.init(e, .fatal));
    }
    try testing.expectEqual(@as(usize, 28), single_byte);
    try testing.expectEqual(@as(usize, 7), multi_byte);
    try testing.expectEqual(@as(usize, 5), implemented);
}

/// Runs `row` with the chunks that `mask` selects: bit `i` splits the input after byte `i`.
/// With `trailing`, every chunk has `last` false, and an empty final call carries `last`.
fn expectPartition(row: Row, mask: usize, trailing: bool) !void {
    errdefer std.debug.print("row {s}: partition mask {b}, trailing empty call {}\n", .{ row.id, mask, trailing });
    var machine = try Machine.init(row.subject);
    var output: [64]u16 = undefined;
    var written: usize = 0;
    var errors: usize = 0;
    var status: Status = .input_empty;
    var start: usize = 0;
    var position: usize = 1;
    while (true) : (position += 1) {
        const at_end = position >= row.input.len;
        if (!at_end and (mask >> @intCast(position - 1)) & 1 == 0) continue;
        const end = @min(position, row.input.len);
        const chunk = row.input[start..end];
        const r = try machine.call(chunk, output[written..], at_end and !trailing);
        if (r.status != .malformed) try testing.expectEqual(chunk.len, r.read);
        written += r.written;
        errors += r.errors;
        status = r.status;
        start = end;
        if (at_end) break;
    }
    if (trailing) {
        const r = try machine.call("", output[written..], true);
        try testing.expectEqual(@as(usize, 0), r.read);
        written += r.written;
        errors += r.errors;
        status = r.status;
    }
    try testing.expectEqualSlices(u16, row.output, output[0..written]);
    try testing.expectEqual(row.errors, errors);
    try testing.expectEqual(row.status, status);
    try expectDecided(row, &machine);
}

/// Runs `row` with repeated calls that each have a 2-unit output buffer.
fn expectSmallOutput(row: Row) !void {
    errdefer std.debug.print("row {s}: 2-unit output buffer\n", .{row.id});
    var machine = try Machine.init(row.subject);
    var output: [64]u16 = undefined;
    var written: usize = 0;
    var errors: usize = 0;
    var position: usize = 0;
    var calls: usize = 0;
    const status: Status = while (true) {
        calls += 1;
        try testing.expect(calls <= 4 * row.input.len + 8);
        var small: [2]u16 = undefined;
        const r = try machine.call(row.input[position..], &small, true);
        @memcpy(output[written..][0..r.written], small[0..r.written]);
        written += r.written;
        errors += r.errors;
        position += r.read;
        switch (r.status) {
            .finished, .malformed => break r.status,
            .output_full => try testing.expect(r.read != 0 or r.written != 0),
            .input_empty => return error.TestUnexpectedResult,
        }
    };
    try testing.expectEqualSlices(u16, row.output, output[0..written]);
    try testing.expectEqual(row.errors, errors);
    try testing.expectEqual(row.status, status);
    try testing.expectEqual(row.read orelse row.input.len, position);
    try expectDecided(row, &machine);
}

/// Runs every partition of `row` and then the 2-unit output buffer, and stops at the first difference.
fn expectRowPartitions(row: Row) !void {
    const partitions: usize = if (row.input.len == 0) 1 else @as(usize, 1) << @intCast(row.input.len - 1);
    for (0..partitions) |mask| {
        try expectPartition(row, mask, false);
        try expectPartition(row, mask, true);
    }
    try expectSmallOutput(row);
}

/// Runs `expectRowPartitions` on every row of at most 13 bytes, and returns whether every row passed.
fn expectPartitions(rows: []const Row) bool {
    var failed = false;
    for (rows) |row| {
        if (row.input.len > 13) continue;
        expectRowPartitions(row) catch {
            failed = true;
        };
    }
    return !failed;
}

test "FP-0123 case 12: every partition of each row into chunks, and a 2-unit output buffer, give the one-call result" {
    var passed = true;
    for ([_][]const Row{ &case_5_rows, &case_6_rows, &case_7_rows, &case_8_rows, &case_9_rows, &case_10_rows }) |rows| {
        if (!expectPartitions(rows)) passed = false;
    }
    try testing.expect(passed);
}

fn isScalar(code_point: u21) bool {
    return code_point < 0xD800 or code_point > 0xDFFF;
}

test "FP-0123 case 13: every scalar value decodes in 7-byte chunks from UTF-8, UTF-16LE, and UTF-16BE" {
    const gpa = testing.allocator;
    var utf8_len: usize = 0;
    var units_len: usize = 0;
    var code_point: u21 = 0;
    while (code_point <= 0x10FFFF) : (code_point += 1) {
        if (!isScalar(code_point)) continue;
        utf8_len += try std.unicode.utf8CodepointSequenceLength(code_point);
        units_len += if (code_point < 0x10000) 1 else 2;
    }

    const utf8_bytes = try gpa.alloc(u8, utf8_len);
    defer gpa.free(utf8_bytes);
    const expected = try gpa.alloc(u16, units_len);
    defer gpa.free(expected);
    const le_bytes = try gpa.alloc(u8, 2 * units_len);
    defer gpa.free(le_bytes);
    const be_bytes = try gpa.alloc(u8, 2 * units_len);
    defer gpa.free(be_bytes);

    var byte_index: usize = 0;
    var unit_index: usize = 0;
    code_point = 0;
    while (code_point <= 0x10FFFF) : (code_point += 1) {
        if (!isScalar(code_point)) continue;
        byte_index += try std.unicode.utf8Encode(code_point, utf8_bytes[byte_index..]);
        if (code_point < 0x10000) {
            expected[unit_index] = @intCast(code_point);
            unit_index += 1;
        } else {
            const offset = code_point - 0x10000;
            expected[unit_index] = @intCast(0xD800 + (offset >> 10));
            expected[unit_index + 1] = @intCast(0xDC00 + (offset & 0x3FF));
            unit_index += 2;
        }
    }
    try testing.expectEqual(utf8_len, byte_index);
    try testing.expectEqual(units_len, unit_index);
    for (expected, 0..) |unit, index| {
        std.mem.writeInt(u16, le_bytes[2 * index ..][0..2], unit, .little);
        std.mem.writeInt(u16, be_bytes[2 * index ..][0..2], unit, .big);
    }

    const output = try gpa.alloc(u16, units_len + 2);
    defer gpa.free(output);
    const inputs = [_]struct { encoding: Encoding, bytes: []const u8 }{
        .{ .encoding = .utf_8, .bytes = utf8_bytes },
        .{ .encoding = .utf_16le, .bytes = le_bytes },
        .{ .encoding = .utf_16be, .bytes = be_bytes },
    };
    for (inputs) |input| {
        errdefer std.debug.print("sweep: {s}\n", .{encoding.name(input.encoding)});
        var decoder = try encoding.Decoder.init(input.encoding, .replacement);
        var written: usize = 0;
        var position: usize = 0;
        while (true) {
            const end = @min(position + 7, input.bytes.len);
            const last = end == input.bytes.len;
            const r = decoder.decode(input.bytes[position..end], output[written..], last);
            if (r.read != end - position or r.errors != 0) return error.TestUnexpectedResult;
            written += r.written;
            position = end;
            if (last) {
                try testing.expectEqual(Status.finished, r.status);
                break;
            }
            if (r.status != .input_empty) return error.TestUnexpectedResult;
        }
        try testing.expectEqual(units_len, written);
        try testing.expect(std.mem.eql(u16, expected, output[0..written]));
        try expectNoUnpairedSurrogate(output[0..written]);
    }
}

test "FP-0123 case 14: the web_string module imports encoding/utf8.zig and carries no UTF-8 decoder of its own" {
    const text = try std.Io.Dir.cwd().readFileAlloc(testing.io, "src/web_" ++ "string.zig", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(text);
    for ([_][]const u8{ "Utf8Decoder", "bytes_needed", "lower_boundary" }) |needle| {
        errdefer std.debug.print("found {s}\n", .{needle});
        try testing.expect(std.mem.indexOf(u8, text, needle) == null);
    }
    try testing.expect(std.mem.indexOf(u8, text, "@import(\"encoding/utf8.zig\")") != null);
}

test "FP-0123 case 16: the encoding module is exported and isolated" {
    try testing.expect(@import("../root.zig").encoding == encoding);

    // Each needle is joined at compile time, so this file contains none of them.
    const forbidden = [_][]const u8{ "ex" ++ "port ", "call" ++ "conv(", "ex" ++ "tern struct", "ex" ++ "tern union", "web_" ++ "string.zig" };
    const expected_files = [_][]const u8{ "labels.zig", "root.zig", "tests.zig", "utf16.zig", "utf8.zig" };
    var seen: [expected_files.len]bool = @splat(false);
    var dir = try std.Io.Dir.cwd().openDir(testing.io, "src/encoding", .{ .iterate = true });
    defer dir.close(testing.io);
    var entries = dir.iterate();
    while (try entries.next(testing.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
        errdefer std.debug.print("src/encoding/{s}\n", .{entry.name});
        const known = for (expected_files, 0..) |file, index| {
            if (std.mem.eql(u8, file, entry.name)) break index;
        } else return error.TestUnexpectedResult;
        seen[known] = true;
        const text = try dir.readFileAlloc(testing.io, entry.name, testing.allocator, .limited(1 << 20));
        defer testing.allocator.free(text);
        for (forbidden) |needle| try testing.expect(std.mem.indexOf(u8, text, needle) == null);
        if (!std.mem.eql(u8, entry.name, "tests.zig")) {
            try testing.expect(std.mem.indexOf(u8, text, "Allocator") == null);
            try testing.expect(std.mem.indexOf(u8, text, "std.heap") == null);
        }
        if (std.mem.eql(u8, entry.name, "utf8.zig")) {
            var imports: usize = 0;
            var rest = text;
            while (std.mem.indexOf(u8, rest, "@import(")) |at| {
                rest = rest[at + "@import(".len ..];
                try testing.expect(std.mem.startsWith(u8, rest, "\"std\")"));
                imports += 1;
            }
            try testing.expect(imports != 0);
        }
    }
    for (seen) |found| try testing.expect(found);
}
