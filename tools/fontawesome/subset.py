#!/usr/bin/env python3
"""Font Awesome subset: the icons the game can name, and nothing else.

The full Font Awesome Free 7 files live in tools/fontawesome/full/ (the source of truth, never sent to a client).
html/font-awesome/ holds what a client downloads at join: a stylesheet with only the icon rules for icons the code
names, and the two web fonts cut down to those glyphs (browse_rsc cannot make subdirectories, so the font urls are
bare file names, as the asset datum registers them).

An icon counts as used when any of these names it, in code/, interface/, strings/, maps/, html/ (not html/font-awesome)
and tgui/packages/ (.dm .ts .tsx .js .html .json .scss .dmm .txt .yml .toml):
  - a quoted string that is exactly an icon name ("user", 'door-open'), also with the legacy "-o" suffix
    tgui-core's <Icon> maps to the regular style ("circle-o" -> "far fa-circle");
  - an "fa-name" token anywhere (class names, HTML);
  - a FA_ICON_NAME macro use;
  - EXTRA_ICONS below, for names built at runtime.
That is deliberately a superset: a common word that happens to be an icon name keeps its glyph, and an icon name sent
from DM data (icon = "tasks") is found as a string. A name assembled from pieces at runtime is the only thing it cannot
see, so each such site is listed in EXTRA_ICONS.

  python tools/fontawesome/subset.py            regenerate html/font-awesome/ (needs: pip install fonttools brotli)
  python tools/fontawesome/subset.py --check    fail when html/font-awesome/ lacks an icon the code names, or is not what
                                                 a regeneration would write (standard library only; run by check_ratchets.sh)
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FULL_CSS = os.path.join(ROOT, "tools", "fontawesome", "full", "all.min.css")
FULL_FONTS = {
    "fa-solid-900.woff2": os.path.join(ROOT, "tools", "fontawesome", "full", "fa-solid-900.woff2"),
    "fa-regular-400.woff2": os.path.join(ROOT, "tools", "fontawesome", "full", "fa-regular-400.woff2"),
}
OUT_CSS = os.path.join(ROOT, "html", "font-awesome", "css", "all.min.css")
OUT_FONT_DIR = os.path.join(ROOT, "html", "font-awesome", "webfonts")

SCAN_ROOTS = ["code", "interface", "strings", "maps", "html", "tgui/packages", "config"]
SCAN_EXTS = (".dm", ".ts", ".tsx", ".js", ".html", ".json", ".scss", ".dmm", ".txt", ".yml", ".toml")
SKIP_DIRS = {"node_modules", "font-awesome", "changelogs", ".git"}
SKIP_FILES = {"font_awesome_icons.dm"}  # the generated FA_ICON_* list names every icon

# Icon names assembled at runtime, one entry per site, so nothing goes missing.
EXTRA_ICONS = {
    "chevron-up",  # tgui/packages/tgui/interfaces/deepquarry/PreferencesMenu/controls.tsx: `fa fa-chevron-${open ? 'up' : 'down'}`
    "chevron-down",
}

STRING_RE = re.compile(r"""["'`]([a-z0-9][a-z0-9-]*)["'`]""")
TOKEN_RE = re.compile(r"\bfa-([a-z0-9][a-z0-9-]*)")
MACRO_RE = re.compile(r"\bFA_ICON_([A-Z0-9_]+)")


def split_blocks(css):
    """Top-level blocks of a minified stylesheet: (prelude, body) pairs, '' prelude for the leading comment."""
    blocks = []
    i = 0
    n = len(css)
    while i < n:
        if css.startswith("/*", i):
            j = css.index("*/", i) + 2
            blocks.append((css[i:j], None))
            i = j
            continue
        if css[i] in "\r\n\t ":
            i += 1
            continue
        j = i
        depth = 0
        quote = None
        while j < n:
            c = css[j]
            if quote:
                if c == "\\":
                    j += 1
                elif c == quote:
                    quote = None
            elif c in "\"'":
                quote = c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        text = css[i : j + 1]
        k = text.index("{")
        blocks.append((text[:k], text[k + 1 : -1]))
        i = j + 1
    return blocks


def decode_fa(value):
    """The codepoints of a --fa value: "\\f0e7", "\\30 " (hex plus the terminating space), "\\!" (an escaped character)."""
    out = []
    i = 0
    while i < len(value):
        c = value[i]
        if c == "\\":
            m = re.match(r"([0-9a-fA-F]{1,6}) ?", value[i + 1 :])
            if m:
                out.append(int(m.group(1), 16))
                i += 1 + m.end()
            else:
                out.append(ord(value[i + 1]))
                i += 2
        else:
            out.append(ord(c))
            i += 1
    return out


def icon_rules(blocks):
    """(index, [names], codepoints) for every block that is a pure icon rule `.fa-a,.fa-b{--fa:"..."}`."""
    rules = []
    for index, (prelude, body) in enumerate(blocks):
        if body is None:
            continue
        m = re.fullmatch(r'--fa:"((?:[^"\\]|\\.)*)"', body)
        if not m:
            continue
        names = []
        for selector in prelude.split(","):
            sm = re.fullmatch(r"\.fa-([a-z0-9-]+)", selector.strip())
            if not sm:
                names = None
                break
            names.append(sm.group(1))
        if names:
            rules.append((index, names, decode_fa(m.group(1))))
    return rules


def referenced_icons(valid):
    """Every icon name in `valid` that the repository names."""
    found = set(EXTRA_ICONS)
    for root in SCAN_ROOTS:
        for directory, dirs, files in os.walk(os.path.join(ROOT, root)):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in files:
                if name in SKIP_FILES or not name.endswith(SCAN_EXTS):
                    continue
                try:
                    with open(os.path.join(directory, name), encoding="utf8", errors="ignore") as handle:
                        text = handle.read()
                except OSError:
                    continue
                for m in STRING_RE.finditer(text):
                    word = m.group(1)
                    found.add(word)
                    if word.endswith("-o"):
                        found.add(word[:-2])
                for m in TOKEN_RE.finditer(text):
                    found.add(m.group(1))
                for m in MACRO_RE.finditer(text):
                    found.add(m.group(1).lower().replace("_", "-"))
    return found & valid


def build_css(full_css):
    blocks = split_blocks(full_css)
    rules = icon_rules(blocks)
    valid = {name for _, names, _ in rules for name in names}
    needed = referenced_icons(valid)
    keep = {}
    codepoints = set()
    for index, names, cps in rules:
        kept = [n for n in names if n in needed]
        if kept:
            keep[index] = ".fa-" + ",.fa-".join(kept)
            codepoints.update(cps)
    parts = []
    for index, (prelude, body) in enumerate(blocks):
        if body is None:
            parts.append(prelude + "\n")
        elif index in keep:
            parts.append(keep[index] + "{" + body + "}")
        elif any(index == r[0] for r in rules):
            continue
        elif prelude.startswith("@font-face") and 'font-family:"FontAwesome"' in body:
            continue  # the Font Awesome 4 compatibility faces: nothing names that family
        else:
            parts.append(prelude + "{" + body + "}")
    return "".join(parts), needed, codepoints


def read(path):
    with open(path, encoding="utf8", newline="") as handle:
        return handle.read()


def write_fonts(codepoints):
    from fontTools import subset
    from fontTools.ttLib import TTFont

    os.makedirs(OUT_FONT_DIR, exist_ok=True)
    for name, source in FULL_FONTS.items():
        options = subset.Options()
        options.flavor = "woff2"
        options.layout_features = ["*"]
        options.notdef_outline = True
        options.name_IDs = ["*"]
        font = TTFont(source)
        subsetter = subset.Subsetter(options)
        subsetter.populate(unicodes=codepoints)
        subsetter.subset(font)
        font.flavor = "woff2"
        font.save(os.path.join(OUT_FONT_DIR, name))


def main():
    check = "--check" in sys.argv
    css, needed, codepoints = build_css(read(FULL_CSS))
    if check:
        if not os.path.exists(OUT_CSS):
            print("fontawesome: html/font-awesome/css/all.min.css is missing; run python tools/fontawesome/subset.py")
            return 1
        have = read(OUT_CSS)
        have_names = {n for _, names, _ in icon_rules(split_blocks(have)) for n in names}
        missing = sorted(needed - have_names)
        if missing:
            print("fontawesome: the code names icons the shipped stylesheet lacks: " + ", ".join(missing))
            print("  run: python tools/fontawesome/subset.py   (then commit html/font-awesome/)")
            return 1
        if have != css:
            print("fontawesome: html/font-awesome/css/all.min.css is not what tools/fontawesome/subset.py writes; rerun it")
            return 1
        print(f"fontawesome: {len(needed)} icons named, stylesheet current")
        return 0
    os.makedirs(os.path.dirname(OUT_CSS), exist_ok=True)
    with open(OUT_CSS, "w", encoding="utf8", newline="") as handle:
        handle.write(css)
    write_fonts(codepoints)
    print(f"fontawesome: {len(needed)} icons, {len(codepoints)} glyphs")
    for name in sorted(FULL_FONTS):
        print(f"  {name}: {os.path.getsize(os.path.join(OUT_FONT_DIR, name))} bytes")
    print(f"  all.min.css: {os.path.getsize(OUT_CSS)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
