"""Write `<stem>.expect.json` beside a font fixture, reading the font only through fontTools 4.66.1.

Usage, from the repository root:

    .tools/python/fonttools-4.66.1/Scripts/python tools/fonts/font_expectations.py tests/text/fonts/<dir>/<font>

The expectation file is the reference that FP-0013 case 13 compares with Fairpane's own OpenType parser.
No expectation file is edited by hand; rerun this script instead.
"""

import hashlib
import json
import platform
import sys
from pathlib import Path

import fontTools
from fontTools.misc.textTools import tobytes
from fontTools.ttLib import TTFont
from fontTools.ttLib.sfnt import SFNTDirectoryEntry, sfntDirectoryEntrySize, sfntDirectorySize

FONT_ROOT = Path("tests/text/fonts")
SEED_ROOT = Path("tests/text/seeds")
SCRIPT = Path("tools/fonts/font_expectations.py")
FONTTOOLS_VERSION = "4.66.1"

# Selection order: (3, 10) format 12, (0, 4) format 12, (3, 1) format 4, then (0, 3) format 4.
CMAP_PRECEDENCE = [(3, 10, 12), (0, 4, 12), (3, 1, 4), (0, 3, 4)]


def fixed(value):
    """A 16.16 fixed-point or version value as its stored integer."""
    if isinstance(value, int):
        return value
    raw = round(value * 65536)
    if raw / 65536 != value:
        raise ValueError(f"{value} is not a 16.16 value")
    return raw


def version_parts(value):
    raw = fixed(value)
    return raw >> 16, raw & 0xFFFF


def fields(table, names):
    return {json_name: getattr(table, attr) for json_name, attr in names}


def head_fields(font):
    head = font["head"]
    major, minor = version_parts(head.tableVersion)
    out = {"major_version": major, "minor_version": minor, "font_revision": fixed(head.fontRevision)}
    out.update(fields(head, [
        ("checksum_adjustment", "checkSumAdjustment"), ("magic_number", "magicNumber"), ("flags", "flags"),
        ("units_per_em", "unitsPerEm"), ("created", "created"), ("modified", "modified"),
        ("x_min", "xMin"), ("y_min", "yMin"), ("x_max", "xMax"), ("y_max", "yMax"), ("mac_style", "macStyle"),
        ("lowest_rec_ppem", "lowestRecPPEM"), ("font_direction_hint", "fontDirectionHint"),
        ("index_to_loc_format", "indexToLocFormat"), ("glyph_data_format", "glyphDataFormat"),
    ]))
    return out


def hhea_fields(font):
    hhea = font["hhea"]
    major, minor = version_parts(hhea.tableVersion)
    out = {"major_version": major, "minor_version": minor}
    out.update(fields(hhea, [
        ("ascender", "ascent"), ("descender", "descent"), ("line_gap", "lineGap"), ("advance_width_max", "advanceWidthMax"),
        ("min_left_side_bearing", "minLeftSideBearing"), ("min_right_side_bearing", "minRightSideBearing"),
        ("x_max_extent", "xMaxExtent"), ("caret_slope_rise", "caretSlopeRise"), ("caret_slope_run", "caretSlopeRun"),
        ("caret_offset", "caretOffset"), ("metric_data_format", "metricDataFormat"), ("number_of_h_metrics", "numberOfHMetrics"),
    ]))
    return out


def maxp_fields(font):
    maxp = font["maxp"]
    out = {"version": fixed(maxp.tableVersion), "num_glyphs": maxp.numGlyphs}
    if fixed(maxp.tableVersion) == 0x00010000:
        out.update(fields(maxp, [
            ("max_points", "maxPoints"), ("max_contours", "maxContours"), ("max_composite_points", "maxCompositePoints"),
            ("max_composite_contours", "maxCompositeContours"), ("max_zones", "maxZones"), ("max_twilight_points", "maxTwilightPoints"),
            ("max_storage", "maxStorage"), ("max_function_defs", "maxFunctionDefs"), ("max_instruction_defs", "maxInstructionDefs"),
            ("max_stack_elements", "maxStackElements"), ("max_size_of_instructions", "maxSizeOfInstructions"),
            ("max_component_elements", "maxComponentElements"), ("max_component_depth", "maxComponentDepth"),
        ]))
    return out


PANOSE = ["bFamilyType", "bSerifStyle", "bWeight", "bProportion", "bContrast", "bStrokeVariation",
          "bArmStyle", "bLetterForm", "bMidline", "bXHeight"]


def os2_fields(font):
    if "OS/2" not in font:
        return None
    os2 = font["OS/2"]
    vendor = tobytes(os2.achVendID, encoding="latin-1")
    if len(vendor) != 4:
        raise ValueError(f"achVendID has {len(vendor)} bytes")
    out = fields(os2, [
        ("version", "version"), ("x_avg_char_width", "xAvgCharWidth"), ("us_weight_class", "usWeightClass"),
        ("us_width_class", "usWidthClass"), ("fs_type", "fsType"), ("y_subscript_x_size", "ySubscriptXSize"),
        ("y_subscript_y_size", "ySubscriptYSize"), ("y_subscript_x_offset", "ySubscriptXOffset"),
        ("y_subscript_y_offset", "ySubscriptYOffset"), ("y_superscript_x_size", "ySuperscriptXSize"),
        ("y_superscript_y_size", "ySuperscriptYSize"), ("y_superscript_x_offset", "ySuperscriptXOffset"),
        ("y_superscript_y_offset", "ySuperscriptYOffset"), ("y_strikeout_size", "yStrikeoutSize"),
        ("y_strikeout_position", "yStrikeoutPosition"), ("s_family_class", "sFamilyClass"),
        ("ul_unicode_range1", "ulUnicodeRange1"), ("ul_unicode_range2", "ulUnicodeRange2"),
        ("ul_unicode_range3", "ulUnicodeRange3"), ("ul_unicode_range4", "ulUnicodeRange4"),
        ("fs_selection", "fsSelection"), ("us_first_char_index", "usFirstCharIndex"), ("us_last_char_index", "usLastCharIndex"),
    ])
    out["panose"] = bytes(getattr(os2.panose, name) for name in PANOSE).hex()
    out["ach_vend_id"] = vendor.hex()
    length = font.reader.tables["OS/2"].length
    if os2.version >= 1 or length >= 78:
        out.update(fields(os2, [
            ("s_typo_ascender", "sTypoAscender"), ("s_typo_descender", "sTypoDescender"), ("s_typo_line_gap", "sTypoLineGap"),
            ("us_win_ascent", "usWinAscent"), ("us_win_descent", "usWinDescent"),
        ]))
    if os2.version >= 1:
        out.update(fields(os2, [("ul_code_page_range1", "ulCodePageRange1"), ("ul_code_page_range2", "ulCodePageRange2")]))
    if os2.version >= 2:
        out.update(fields(os2, [
            ("sx_height", "sxHeight"), ("s_cap_height", "sCapHeight"), ("us_default_char", "usDefaultChar"),
            ("us_break_char", "usBreakChar"), ("us_max_context", "usMaxContext"),
        ]))
    if os2.version >= 5:
        out.update(fields(os2, [
            ("us_lower_optical_point_size", "usLowerOpticalPointSize"), ("us_upper_optical_point_size", "usUpperOpticalPointSize"),
        ]))
    return out


def post_fields(font):
    if "post" not in font:
        return None
    post = font["post"]
    out = {"version": fixed(post.formatType), "italic_angle": fixed(post.italicAngle)}
    out.update(fields(post, [
        ("underline_position", "underlinePosition"), ("underline_thickness", "underlineThickness"),
        ("is_fixed_pitch", "isFixedPitch"), ("min_mem_type42", "minMemType42"), ("max_mem_type42", "maxMemType42"),
        ("min_mem_type1", "minMemType1"), ("max_mem_type1", "maxMemType1"),
    ]))
    return out


def name_records(font):
    out = []
    for record in font["name"].names:
        raw = record.string
        if not isinstance(raw, bytes):
            raise TypeError("fontTools decoded a name record before it was read raw")
        out.append({"platform": record.platformID, "encoding": record.platEncID, "language": record.langID,
                    "name_id": record.nameID, "bytes": raw.hex()})
    return out


def seed_code_points():
    points = set()
    for seed in sorted(SEED_ROOT.glob("*.json")):
        for text in json.loads(seed.read_text(encoding="utf-8"))["code_points"]:
            points.add(int(text[2:], 16))
    return sorted(points)


def cmap_fields(font):
    subtables = font["cmap"].tables
    listed = [{"platform": t.platformID, "encoding": t.platEncID, "format": t.format,
               "language": None if t.format == 14 else t.language} for t in subtables]
    selected = None
    for key in CMAP_PRECEDENCE:
        selected = next((t for t in subtables if (t.platformID, t.platEncID, t.format) == key), None)
        if selected is not None:
            break
    if selected is None:
        raise ValueError("The font has no Unicode cmap subtable")
    glyphs = [{"code_point": f"U+{cp:04X}", "glyph": font.getGlyphID(selected.cmap[cp]) if cp in selected.cmap else 0}
              for cp in seed_code_points()]
    mapped = sorted({0} | {font.getGlyphID(name) for name in selected.cmap.values()})
    selection = {"platform": selected.platformID, "encoding": selected.platEncID, "format": selected.format}
    return {"subtables": listed, "selected": selection, "glyphs": glyphs}, mapped


def hmtx_entries(font, mapped):
    metrics = font["hmtx"].metrics
    order = font.getGlyphOrder()
    return [{"glyph": gid, "advance": metrics[order[gid]][0], "lsb": metrics[order[gid]][1]} for gid in mapped]


def glyf_entries(font, mapped):
    if "glyf" not in font:
        return None
    loca, glyf, order = font["loca"], font["glyf"], font.getGlyphOrder()
    out = []
    for gid in mapped:
        if loca[gid] == loca[gid + 1]:
            out.append({"glyph": gid, "header": None})
            continue
        g = glyf[order[gid]]
        out.append({"glyph": gid, "header": {"number_of_contours": g.numberOfContours, "x_min": g.xMin, "y_min": g.yMin,
                                              "x_max": g.xMax, "y_max": g.yMax}})
    return out


def layout_fields(font, tag):
    if tag not in font:
        return None
    table = font[tag].table
    scripts = [r.ScriptTag for r in table.ScriptList.ScriptRecord] if table.ScriptList else []
    features = [r.FeatureTag for r in table.FeatureList.FeatureRecord] if table.FeatureList else []
    lookups = len(table.LookupList.Lookup) if table.LookupList else 0
    return {"version": fixed(table.Version), "scripts": scripts, "features": features, "lookup_count": lookups}


def gdef_fields(font):
    if "GDEF" not in font:
        return None
    return {"version": fixed(font["GDEF"].table.Version)}


def cff_fields(font):
    if "CFF " not in font:
        return None
    cff = font["CFF "].cff
    top = cff[cff.fontNames[0]]
    return {"names": list(cff.fontNames), "charstrings_count": len(top.CharStrings), "cid_keyed": "ROS" in top.rawDict}


def directory(data, font):
    """The table directory in file order. fontTools' reader orders its tables by offset, so the records are read again here."""
    out = []
    for i in range(font.reader.numTables):
        start = sfntDirectorySize + i * sfntDirectoryEntrySize
        entry = SFNTDirectoryEntry()
        entry.fromString(data[start:start + sfntDirectoryEntrySize])
        out.append({"tag": str(entry.tag), "checksum": entry.checkSum, "offset": entry.offset, "length": entry.length})
    if sorted(e["tag"] for e in out) != sorted(font.reader.tables.keys()):
        raise ValueError("The directory reread differs from fontTools' reader")
    return out


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    if fontTools.version != FONTTOOLS_VERSION:
        sys.exit(f"fontTools {FONTTOOLS_VERSION} is required, not {fontTools.version}")
    path = Path(argv[1])
    data = path.read_bytes()
    font = TTFont(path, lazy=False, recalcBBoxes=False, recalcTimestamp=False)
    cmap, mapped = cmap_fields(font)
    expectation = {
        "format": "fairpane-font-expectation",
        "version": 1,
        "font": path.relative_to(FONT_ROOT).as_posix(),
        "font_sha256": hashlib.sha256(data).hexdigest(),
        "generator": {"script": SCRIPT.as_posix(), "script_sha256": hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),
                      "fonttools": fontTools.version, "python": platform.python_version()},
        "sfnt_version": int.from_bytes(tobytes(font.sfntVersion, encoding="latin-1"), "big"),
        "tables": directory(data, font),
        "head": head_fields(font),
        "hhea": hhea_fields(font),
        "maxp": maxp_fields(font),
        "os2": os2_fields(font),
        "post": post_fields(font),
        "name": name_records(font),
        "cmap": cmap,
        "hmtx": hmtx_entries(font, mapped),
        "glyf": glyf_entries(font, mapped),
        "gdef": gdef_fields(font),
        "gsub": layout_fields(font, "GSUB"),
        "gpos": layout_fields(font, "GPOS"),
        "cff": cff_fields(font),
    }
    out = path.with_name(f"{path.stem}.expect.json")
    out.write_text(json.dumps(expectation, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {out.as_posix()}: font SHA-256 {expectation['font_sha256']}, {len(expectation['tables'])} tables, "
          f"{len(cmap['glyphs'])} seed code points, {len(mapped)} mapped glyphs")


if __name__ == "__main__":
    main(sys.argv)
