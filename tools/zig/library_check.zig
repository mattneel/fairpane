//! Checks the static library that `zig build` installs, for FP-0066 contract cases 1, 2, 4, and 5.
//!
//! `library_check same <a> <b>` confirms for case 1 that two libraries are byte-identical.
//! `library_check absent <library> (--name <text> | --dir <directory>)...` confirms for case 2 that the library contains
//! no name and no directory path, where `--dir` resolves its directory against the current directory first.
//! `library_check names <library> <directory>` confirms for case 4 that the library's object names the absolute path of the directory.
//! `library_check members <library> <member>` confirms for case 5 that the library's only member is named `member`.
//! `library_check metadata <library>` confirms that every member header has a zero time stamp, owner, and group.
//!
//! A search ignores ASCII letter case and treats `/` and `\` as the same byte, because a compiler may write either spelling of a path.

const std = @import("std");
const Io = std.Io;

/// The largest library that the checks read.
const library_size_limit = 1 << 30;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) return usage();
    const command = args[1];
    if (std.mem.eql(u8, command, "same") and args.len == 4) {
        const a = try readLibrary(init.io, arena, args[2]);
        const b = try readLibrary(init.io, arena, args[3]);
        if (!std.mem.eql(u8, a, b)) {
            std.debug.print("{s} ({d} bytes) and {s} ({d} bytes) differ\n", .{ args[2], a.len, args[3], b.len });
            return 1;
        }
        return 0;
    }
    if (std.mem.eql(u8, command, "absent") and args.len >= 5 and args.len % 2 == 1) {
        const bytes = try readLibrary(init.io, arena, args[2]);
        const cwd = try std.process.currentPathAlloc(init.io, arena);
        var needles: std.ArrayList([]const u8) = .empty;
        var index: usize = 3;
        while (index < args.len) : (index += 2) {
            const value = args[index + 1];
            if (std.mem.eql(u8, args[index], "--name")) {
                try needles.append(arena, value);
            } else if (std.mem.eql(u8, args[index], "--dir")) {
                try needles.append(arena, try std.fs.path.resolveAlloc(arena, &.{ cwd, value }));
            } else return usage();
        }
        return reportAbsent(arena, args[2], bytes, needles.items);
    }
    if (std.mem.eql(u8, command, "names") and args.len == 4) {
        const bytes = try readLibrary(init.io, arena, args[2]);
        const archive = parse(arena, bytes) catch |err| return malformed(args[2], err);
        if (archive.members.len != 1) {
            std.debug.print("{s} has {d} members, not one object\n", .{ args[2], archive.members.len });
            return 1;
        }
        const cwd = try std.process.currentPathAlloc(init.io, arena);
        const directory = try std.fs.path.resolveAlloc(arena, &.{ cwd, args[3] });
        if (try find(arena, archive.members[0].data, directory) == null) {
            std.debug.print("the object {s} of {s} does not name {s}\n", .{ archive.members[0].name, args[2], directory });
            return 1;
        }
        return 0;
    }
    if (std.mem.eql(u8, command, "members") and args.len == 4) {
        const bytes = try readLibrary(init.io, arena, args[2]);
        const archive = parse(arena, bytes) catch |err| return malformed(args[2], err);
        if (archive.members.len != 1 or !std.mem.eql(u8, archive.members[0].name, args[3])) {
            std.debug.print("{s} has {d} members, not only {s}:\n", .{ args[2], archive.members.len, args[3] });
            for (archive.members) |member| std.debug.print("  {s}\n", .{member.name});
            return 1;
        }
        return 0;
    }
    if (std.mem.eql(u8, command, "metadata") and args.len == 3) {
        const bytes = try readLibrary(init.io, arena, args[2]);
        const archive = parse(arena, bytes) catch |err| return malformed(args[2], err);
        var failed = false;
        for (archive.headers) |header| {
            if (!header.deterministic()) {
                std.debug.print("{s}: the header of {s} has time stamp {s}, owner {s}, and group {s}\n", .{
                    args[2], header.name, header.date, header.uid, header.gid,
                });
                failed = true;
            }
        }
        return if (failed) 1 else 0;
    }
    return usage();
}

fn usage() u8 {
    std.debug.print(
        \\usage: library_check same <a> <b>
        \\       library_check absent <library> (--name <text> | --dir <directory>)...
        \\       library_check names <library> <directory>
        \\       library_check members <library> <member>
        \\       library_check metadata <library>
        \\
    , .{});
    return 2;
}

fn readLibrary(io: Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(library_size_limit));
}

fn malformed(path: []const u8, err: ParseError) u8 {
    std.debug.print("{s} is not a well-formed ar archive: {t}\n", .{ path, err });
    return 1;
}

fn reportAbsent(gpa: std.mem.Allocator, path: []const u8, bytes: []const u8, needles: []const []const u8) !u8 {
    var found = false;
    for (needles) |needle| {
        if (try find(gpa, bytes, needle)) |offset| {
            std.debug.print("{s} contains {s} at byte {d}\n", .{ path, needle, offset });
            found = true;
        }
    }
    return if (found) 1 else 0;
}

/// Lowercases ASCII letters and writes every `\` as `/`.
fn fold(byte: u8) u8 {
    return if (byte == '\\') '/' else std.ascii.toLower(byte);
}

/// The offset of the first occurrence of `needle` in `haystack`, comparing folded bytes.
fn find(gpa: std.mem.Allocator, haystack: []const u8, needle: []const u8) !?usize {
    if (needle.len == 0) return error.EmptyNeedle;
    const folded_needle = try gpa.alloc(u8, needle.len);
    defer gpa.free(folded_needle);
    for (folded_needle, needle) |*out, byte| out.* = fold(byte);
    const folded = try gpa.alloc(u8, haystack.len);
    defer gpa.free(folded);
    for (folded, haystack) |*out, byte| out.* = fold(byte);
    return std.mem.find(u8, folded, folded_needle);
}

const ParseError = error{
    NotAnArchive,
    TruncatedHeader,
    MalformedHeader,
    TruncatedMember,
    MissingNameTable,
    MalformedName,
    OutOfMemory,
};

/// One member header's raw fields, with its decoded name.
const Header = struct {
    name: []const u8,
    date: []const u8,
    uid: []const u8,
    gid: []const u8,

    /// A deterministic archiver writes 0 in each field, or leaves it blank, as the GNU layout does for the name table.
    fn deterministic(header: Header) bool {
        return zeroOrBlank(header.date) and zeroOrBlank(header.uid) and zeroOrBlank(header.gid);
    }

    fn zeroOrBlank(field: []const u8) bool {
        return field.len == 0 or std.mem.eql(u8, field, "0");
    }
};

const Member = struct { name: []const u8, data: []const u8 };

/// Every header of an archive, and its members other than the symbol tables and the name table.
const Archive = struct { headers: []const Header, members: []const Member };

/// Parses an ar archive in the System V or GNU layout, the COFF layout, or the BSD layout.
/// The symbol tables `/`, `/SYM64/`, `/<ECSYMBOLS>/`, and `__.SYMDEF` in its variants, and the name table `//`, are not members.
fn parse(gpa: std.mem.Allocator, bytes: []const u8) ParseError!Archive {
    const magic = "!<arch>\n";
    if (!std.mem.startsWith(u8, bytes, magic)) return error.NotAnArchive;
    var headers: std.ArrayList(Header) = .empty;
    var members: std.ArrayList(Member) = .empty;
    var names: ?[]const u8 = null;
    var offset: usize = magic.len;
    while (offset < bytes.len) {
        // A member starts at an even offset; a single newline pads an odd-sized member.
        if (offset + 1 == bytes.len and bytes[offset] == '\n') break;
        if (bytes.len - offset < 60) return error.TruncatedHeader;
        const raw = bytes[offset..][0..60];
        if (!std.mem.eql(u8, raw[58..60], "`\n")) return error.MalformedHeader;
        const size = std.fmt.parseInt(usize, trimSpaces(raw[48..58]), 10) catch return error.MalformedHeader;
        const start = offset + 60;
        if (size > bytes.len - start) return error.TruncatedMember;
        var data = bytes[start..][0..size];
        offset = start + size + (size & 1);

        const field = trimSpaces(raw[0..16]);
        var name: []const u8 = field;
        if (std.mem.startsWith(u8, field, "#1/")) {
            // BSD: the name occupies the first bytes of the data.
            const length = std.fmt.parseInt(usize, field[3..], 10) catch return error.MalformedName;
            if (length > data.len) return error.MalformedName;
            name = std.mem.trimEnd(u8, data[0..length], "\x00");
            data = data[length..];
        } else if (std.mem.eql(u8, field, "//")) {
            names = data;
        } else if (field.len > 1 and field[0] == '/' and std.ascii.isDigit(field[1])) {
            // GNU and COFF: an offset into the name table, ended by `/\n` or a zero byte.
            const table = names orelse return error.MissingNameTable;
            const at = std.fmt.parseInt(usize, field[1..], 10) catch return error.MalformedName;
            if (at >= table.len) return error.MalformedName;
            const end = std.mem.findAnyPos(u8, table, at, "\n\x00") orelse table.len;
            name = std.mem.trimEnd(u8, table[at..end], "/");
        } else if (field.len > 1 and field[field.len - 1] == '/' and field[0] != '/') {
            name = field[0 .. field.len - 1];
        }
        try headers.append(gpa, .{ .name = name, .date = trimSpaces(raw[16..28]), .uid = trimSpaces(raw[28..34]), .gid = trimSpaces(raw[34..40]) });
        if (!isIndex(name)) try members.append(gpa, .{ .name = name, .data = data });
    }
    return .{ .headers = try headers.toOwnedSlice(gpa), .members = try members.toOwnedSlice(gpa) };
}

fn trimSpaces(field: []const u8) []const u8 {
    return std.mem.trimEnd(u8, field, " ");
}

fn isIndex(name: []const u8) bool {
    const indexes = [_][]const u8{ "/", "//", "/SYM64/", "/<ECSYMBOLS>/", "__.SYMDEF", "__.SYMDEF SORTED", "__.SYMDEF_64", "__.SYMDEF_64 SORTED" };
    for (indexes) |index| if (std.mem.eql(u8, name, index)) return true;
    return false;
}

const testing = std.testing;

/// Builds an archive from `entries`, each a raw 16-byte name field, the header's time stamp, and the data.
fn testArchive(gpa: std.mem.Allocator, entries: []const struct { []const u8, []const u8, []const u8 }) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "!<arch>\n");
    for (entries) |entry| {
        const name, const date, const data = entry;
        var header: [60]u8 = @splat(' ');
        @memcpy(header[0..name.len], name);
        @memcpy(header[16..][0..date.len], date);
        header[28] = '0';
        header[34] = '0';
        @memcpy(header[40..43], "644");
        _ = try std.fmt.bufPrint(header[48..58], "{d}", .{data.len});
        @memcpy(header[58..60], "`\n");
        try out.appendSlice(gpa, &header);
        try out.appendSlice(gpa, data);
        if (data.len % 2 == 1) try out.append(gpa, '\n');
    }
    return out.toOwnedSlice(gpa);
}

test "FP-0066: a GNU or COFF archive names a long member through the name table and skips both symbol tables" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const bytes = try testArchive(gpa, &.{
        .{ "/", "0", "\x00\x00\x00\x00" },
        .{ "/", "0", "\x00\x00\x00\x00" },
        .{ "//", "", "fairpane_zcu.obj/\n" },
        .{ "/0", "0", "object" },
    });
    const archive = try parse(gpa, bytes);
    try testing.expectEqual(@as(usize, 1), archive.members.len);
    try testing.expectEqualStrings("fairpane_zcu.obj", archive.members[0].name);
    try testing.expectEqualStrings("object", archive.members[0].data);
    try testing.expectEqual(@as(usize, 4), archive.headers.len);
    for (archive.headers) |header| try testing.expect(header.deterministic());
}

test "FP-0066: a member name that holds a cache directory is reported in full" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const bytes = try testArchive(gpa, &.{
        .{ "//", "0", ".zig-cache\\o\\61c2b72ff156fe963e2d6fc2510b6176\\fairpane_zcu.obj\x00" },
        .{ "/0", "0", "odd" },
    });
    const archive = try parse(gpa, bytes);
    try testing.expectEqual(@as(usize, 1), archive.members.len);
    try testing.expectEqualStrings(".zig-cache\\o\\61c2b72ff156fe963e2d6fc2510b6176\\fairpane_zcu.obj", archive.members[0].name);
}

test "FP-0066: a short GNU name, a BSD name, and a BSD symbol table" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const bytes = try testArchive(gpa, &.{
        .{ "#1/20", "0", "__.SYMDEF SORTED\x00\x00\x00\x00table" },
        .{ "#1/16", "0", "fairpane_zcu.o\x00\x00data" },
        .{ "short.o/", "0", "x" },
    });
    const archive = try parse(gpa, bytes);
    try testing.expectEqual(@as(usize, 2), archive.members.len);
    try testing.expectEqualStrings("fairpane_zcu.o", archive.members[0].name);
    try testing.expectEqualStrings("data", archive.members[0].data);
    try testing.expectEqualStrings("short.o", archive.members[1].name);
}

test "FP-0066: a time stamp makes a header nondeterministic" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const archive = try parse(gpa, try testArchive(gpa, &.{.{ "a.o/", "1760000000", "x" }}));
    try testing.expect(!archive.headers[0].deterministic());
}

test "FP-0066: malformed archives fail to parse" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    try testing.expectError(error.NotAnArchive, parse(gpa, "not an archive"));
    try testing.expectError(error.TruncatedHeader, parse(gpa, "!<arch>\na.o/"));
    const good = try testArchive(gpa, &.{.{ "a.o/", "0", "data" }});
    try testing.expectError(error.TruncatedMember, parse(gpa, good[0 .. good.len - 1]));
    var bad_magic = try gpa.dupe(u8, good);
    bad_magic[8 + 58] = 'x';
    try testing.expectError(error.MalformedHeader, parse(gpa, bad_magic));
    try testing.expectError(error.MissingNameTable, parse(gpa, try testArchive(gpa, &.{.{ "/0", "0", "data" }})));
    try testing.expectError(error.MalformedName, parse(gpa, try testArchive(gpa, &.{ .{ "//", "0", "a.o/\n" }, .{ "/9", "0", "data" } })));
    try testing.expectError(error.MalformedName, parse(gpa, try testArchive(gpa, &.{.{ "#1/9", "0", "data" }})));
}

test "FP-0066: a search ignores letter case and the path separator" {
    const library = "debug info: C:\\Src\\Fairpane\\SRC\\root.zig";
    try testing.expectEqual(@as(?usize, 12), try find(testing.allocator, library, "c:/src/fairpane/src"));
    try testing.expectEqual(@as(?usize, 12), try find(testing.allocator, library, "C:\\src\\FAIRPANE"));
    try testing.expectEqual(@as(?usize, null), try find(testing.allocator, library, "c:/src/fairpane/lib"));
    try testing.expectError(error.EmptyNeedle, find(testing.allocator, library, ""));
}
