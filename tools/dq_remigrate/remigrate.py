#!/usr/bin/env python3
"""DM-aware re-application of the dq_*() var-rename migration.

Previous attempt: bulk regex over .dm files. It corrupted hundreds of
string literals, comments, and type-paths.

This script does it correctly by walking source text in a single pass
with a state machine that classifies each position as code, string,
comment, or type-path. Only identifiers in real code positions are
rewritten; strings and comments are emitted unchanged.

Substitution rules (see VARS below for the full set):
  parachute            (read)  -> dq_get_parachute(src)
  obj.parachute        (read)  -> dq_get_parachute(obj)
  parachute = X        (write) -> dq_set_parachute(src, X)
  obj.parachute = X    (write) -> dq_set_parachute(obj, X)
  obj.parachute = initial(parachute) (clear) -> dq_clear_parachute(obj)

Skipped positions:
  - Inside "..." double-quoted strings (but bracketed [code] inside
    them is rewritten as code).
  - Inside '...' single-quoted icon literals.
  - Inside // line comments.
  - Inside /* block comments */.
  - Inside DM type-paths /foo/bar (any slash-separated path).
  - At declaration sites `var/<id>` (the declaration target).

Usage:
  python3 tools/dq_remigrate/remigrate.py file1.dm [file2.dm ...]
  python3 tools/dq_remigrate/remigrate.py --dry-run file.dm
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

VARS: dict[str, dict[str, str]] = {
    "parachute":         {"get": "dq_get_parachute",         "set": "dq_set_parachute",         "clear": "dq_clear_parachute"},
    "cloaked":           {"get": "dq_get_cloaked",           "set": "dq_set_cloaked",           "clear": "dq_clear_cloaked"},
    "hovering":          {"get": "dq_get_hovering",          "set": "dq_set_hovering",          "clear": "dq_clear_hovering"},
    "softfall":          {"get": "dq_get_softfall",          "set": "dq_set_softfall",          "clear": "dq_clear_softfall"},
    "parachuting":       {"get": "dq_get_parachuting",       "set": "dq_set_parachuting",       "clear": "dq_clear_parachuting"},
    "moved_recently":    {"get": "dq_get_moved_recently",    "set": "dq_set_moved_recently",    "clear": "dq_clear_moved_recently"},
    "blood_color":       {"get": "dq_get_blood_color",       "set": "dq_set_blood_color",       "clear": "dq_clear_blood_color"},
    "was_bloodied":      {"get": "dq_get_was_bloodied",      "set": "dq_set_was_bloodied",      "clear": "dq_clear_was_bloodied"},
    "fluorescent":       {"get": "dq_get_fluorescent",       "set": "dq_set_fluorescent",       "clear": "dq_clear_fluorescent"},
    "belly_cycles":      {"get": "dq_get_belly_cycles",      "set": "dq_set_belly_cycles",      "clear": "dq_clear_belly_cycles"},
    "cloaked_selfimage": {"get": "dq_get_cloaked_selfimage", "set": "dq_set_cloaked_selfimage", "clear": "dq_clear_cloaked_selfimage"},
    "chat_color":        {"get": "dq_get_chat_color",        "set": "dq_set_chat_color",        "clear": "dq_clear_chat_color"},
    "viewing_alt_appearances": {"get": "dq_get_viewing_alt_appearances", "set": "dq_set_viewing_alt_appearances", "clear": "dq_clear_viewing_alt_appearances"},
    "catalogue_delay":   {"get": "dq_get_catalogue_delay",   "set": "dq_set_catalogue_delay",   "clear": "dq_clear_catalogue_delay"},
}

# Match `[owner.]ident` (owner may use `?.`).
TOKEN_RE = re.compile(
    r"(?P<owner>[A-Za-z_][A-Za-z0-9_]*)(?P<safe_nav>\?)?\.\s*"
    r"(?P<ident_dotted>[A-Za-z_][A-Za-z0-9_]*)"
    r"|"
    r"(?P<ident_bare>[A-Za-z_][A-Za-z0-9_]*)"
)

# Declarations look like `var/<ident>` or `var/list/<ident>` or `var/<type>/<ident>`.
DECL_RE = re.compile(r"(?:^|[\s\t,(])var(?:/[A-Za-z_][A-Za-z0-9_]*)*/$")

INITIAL_RE_CACHE: dict[str, re.Pattern] = {}


def _initial_re(ident: str) -> re.Pattern:
    if ident not in INITIAL_RE_CACHE:
        INITIAL_RE_CACHE[ident] = re.compile(
            rf"^initial\s*\(\s*{re.escape(ident)}\s*\)$"
        )
    return INITIAL_RE_CACHE[ident]


def process(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    # Stack of context flags so bracketed code inside strings nests cleanly.
    # State 'string' means we're inside a "..." (non-code). When we hit `[`
    # we switch back to 'code' inside; `]` pops back to 'string'.
    contexts: list[str] = ["code"]

    def in_code() -> bool:
        return contexts[-1] == "code"

    while i < n:
        c = text[i]
        # Line comment (only in code).
        if in_code() and c == "/" and i + 1 < n and text[i + 1] == "/":
            nl = text.find("\n", i)
            end = nl if nl != -1 else n
            out.append(text[i:end])
            i = end
            continue
        # Block comment.
        if in_code() and c == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            end = end + 2 if end != -1 else n
            out.append(text[i:end])
            i = end
            continue
        # Single-quoted icon literal.
        if in_code() and c == "'":
            j = i + 1
            while j < n and text[j] != "'":
                if text[j] == "\\" and j + 1 < n:
                    j += 2
                else:
                    j += 1
            j = min(j + 1, n)
            out.append(text[i:j])
            i = j
            continue
        # Double-quoted string opens.
        if in_code() and c == '"':
            out.append(c)
            i += 1
            contexts.append("string")
            continue
        # Inside a string.
        if not in_code():
            if c == "\\" and i + 1 < n:
                out.append(text[i : i + 2])
                i += 2
                continue
            if c == '"':
                out.append(c)
                i += 1
                contexts.pop()
                continue
            if c == "[":
                # Bracketed code interpolation.
                out.append(c)
                i += 1
                contexts.append("code")
                continue
            if c == "\n":
                # Unterminated string — bail out of the string state.
                out.append(c)
                i += 1
                if contexts[-1] == "string":
                    contexts.pop()
                continue
            out.append(c)
            i += 1
            continue
        # Closing bracket of interpolation.
        if in_code() and c == "]" and len(contexts) > 1 and contexts[-2] == "string":
            out.append(c)
            i += 1
            contexts.pop()
            continue
        # Type-path: `/ident(/ident)*` when `/` is not a division op.
        if c == "/":
            prev = text[i - 1] if i > 0 else "\n"
            is_typepath = not (prev.isalnum() or prev == "_" or prev == ")" or prev == "]")
            if not is_typepath:
                # Check for `var/`, `proc/`, `verb/` keyword preceding `/`.
                lookback = text[max(0, i - 8) : i]
                if re.search(r"(?:^|\W)(?:var|proc|verb)$", lookback):
                    is_typepath = True
            if is_typepath:
                j = i
                while j < n and text[j] == "/":
                    j += 1
                    while j < n and (text[j].isalnum() or text[j] == "_"):
                        j += 1
                out.append(text[i:j])
                i = j
                continue
        # Identifier (possibly with leading `owner.`).
        if c.isalpha() or c == "_":
            m = TOKEN_RE.match(text, i)
            if m and m.start() == i:
                ident = m.group("ident_dotted") or m.group("ident_bare")
                owner = m.group("owner")  # None if bare
                if ident not in VARS:
                    out.append(m.group(0))
                    i = m.end()
                    continue
                # Declaration site?
                # For declarations, the dotted form is impossible — owner
                # is always None. Check lookback for var/.../`.
                lookback = text[max(0, i - 96) : i]
                if owner is None and DECL_RE.search(lookback):
                    out.append(m.group(0))
                    i = m.end()
                    continue
                helper = VARS[ident]
                owner_expr = owner if owner else "src"
                # Look ahead: read vs write.
                j = m.end()
                while j < n and text[j] in " \t":
                    j += 1
                is_write = (
                    j < n
                    and text[j] == "="
                    and (j + 1 >= n or text[j + 1] != "=")
                )
                if is_write:
                    val_text, val_end = _consume_value(text, j + 1, contexts[-1])
                    if _initial_re(ident).match(val_text):
                        out.append(f"{helper['clear']}({owner_expr})")
                    else:
                        out.append(f"{helper['set']}({owner_expr}, {val_text})")
                    i = val_end
                else:
                    out.append(f"{helper['get']}({owner_expr})")
                    i = m.end()
                continue
        out.append(c)
        i += 1
    return "".join(out)


def _consume_value(text: str, start: int, ctx: str) -> tuple[str, int]:
    """Walk a value expression on the RHS of `=`. Returns (text, end_index).

    Handles balanced parens/brackets and string literals inside the value.
    Stops at a top-level newline, `;`, or start of a `//`/`/*` comment.
    """
    n = len(text)
    i = start
    depth = 0
    in_str = False
    while i < n:
        ch = text[i]
        if in_str:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == "'":
            # icon literal, skip to closing quote
            j = i + 1
            while j < n and text[j] != "'":
                if text[j] == "\\" and j + 1 < n:
                    j += 2
                else:
                    j += 1
            i = min(j + 1, n)
            continue
        # Top-level inline comment ends the value.
        if depth == 0 and ch == "/" and i + 1 < n and text[i + 1] in "/*":
            break
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and ch in "\n;":
            break
        i += 1
    return text[start:i].strip(), i


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    for path in args.files:
        if not path.exists() or path.is_dir():
            continue
        original = path.read_text()
        rewritten = process(original)
        if rewritten == original:
            continue
        if args.dry_run:
            print(f"WOULD modify: {path}")
        else:
            path.write_text(rewritten)
            print(f"modified: {path}")


if __name__ == "__main__":
    main()
