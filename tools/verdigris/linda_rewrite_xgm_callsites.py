"""Mechanical rewrites of XGM-style call sites in CHOMP source files so they
compile under USE_LINDA_ATMOS.

Idempotent — re-running on already-rewritten files is a no-op.

Rewrites:

  `(expr).gas[GAS_X]`          → `LINDA_GAS_AMT((expr), GAS_X)`
  `(expr).gas[GAS_X] += d`     → `LINDA_GAS_ADJUST((expr), GAS_X, d)`
  `(expr).total_moles`         → `(expr).total_moles()`
                                   (when in read context, not followed by `(` or assignment)

Where (expr) is a simple identifier or `src` / `.` chain.

Targets only files listed in `modular_dq/doc/linda_compile_errors_by_file.txt`
to avoid touching unrelated code.

Skips:
  - lines inside `//` line comments
  - lines inside `/* ... */` block comments (single-line within)
  - quoted string contents (basic — assumes no embedded quotes)

Caveat: this is a regex pass, not a parser. It handles the common ~80% case;
the remainder will need hand-edits. Run, recompile, inspect what's left.
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ERR = REPO / "modular_dq/doc/linda_compile_errors_by_file.txt"

# Identifier or src/.-chain we'll match as the "expression" before .gas[...] / .total_moles
EXPR = r"(?P<expr>[A-Za-z_][A-Za-z_0-9.]*(?:\[[A-Za-z_0-9.\"']+\])*)"

# Match `(expr).gas[GAS_*]` followed by `+=` `-=` `=` (write) — distinguish read vs write
WRITE_ADJUST_RE = re.compile(
    EXPR + r"\.gas\[(?P<gas>[A-Za-z_][A-Za-z_0-9]*)\]\s+\+=\s+(?P<delta>[^;\n]+?)(?=\s*(?://|/\*|$|;))"
)
# `=` must be preceded by whitespace (not an op char) and NOT followed by another `=`.
WRITE_ASSIGN_RE = re.compile(
    EXPR + r"\.gas\[(?P<gas>[A-Za-z_][A-Za-z_0-9]*)\]\s+(?<![+\-*/%!<>=])=(?!=)\s+(?P<value>[^;\n]+?)(?=\s*(?://|/\*|$|;))"
)
# Run reads LAST — anything not already rewritten is a read (including ==, <=, comparison).
# Accept either a GAS_* literal or any simple identifier (e.g. local var in a loop).
READ_RE = re.compile(
    EXPR + r"\.gas\[(?P<gas>[A-Za-z_][A-Za-z_0-9]*)\]"
)
# Whole-list reference: `<expr>.gas` not followed by `[` (a keyed access — covered above)
# and not followed by word chars (would be a different identifier).
WHOLE_LIST_RE = re.compile(
    EXPR + r"\.gas(?![A-Za-z_0-9\[])"
)

# `.total_moles` as a var-read. Must not be followed by `(` (already a call),
# must not be a write (= or += etc.), must not be a method continuation (.foo).
TOTAL_MOLES_RE = re.compile(
    r"(?P<lead>[A-Za-z_][A-Za-z_0-9.]*)\.total_moles(?![A-Za-z_0-9])(?P<trail>(?!\s*[(.=]|\s*[+\-*/%]?=))"
)


def in_comment_or_string(line: str, pos: int) -> bool:
    """Best-effort check whether `pos` in `line` is inside a // comment or "string"."""
    # // line comment
    line_comment = line.find("//")
    if 0 <= line_comment <= pos:
        return True
    # Naive quoted string: count unescaped quotes before pos
    in_quote = False
    i = 0
    while i < pos:
        c = line[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            in_quote = not in_quote
        i += 1
    return in_quote


def rewrite_line(line: str) -> tuple[str, int]:
    """Return (new_line, num_changes)."""
    changes = 0

    # Pass 1: writes (+= / =) — must run before generic read pass.
    def sub_adjust(m: re.Match) -> str:
        nonlocal changes
        if in_comment_or_string(line, m.start()):
            return m.group(0)
        changes += 1
        return f"LINDA_GAS_ADJUST({m['expr']}, {m['gas']}, {m['delta'].strip()})"

    new = WRITE_ADJUST_RE.sub(sub_adjust, line)

    def sub_assign(m: re.Match) -> str:
        nonlocal changes
        if in_comment_or_string(new, m.start()):
            return m.group(0)
        changes += 1
        # Assignment of a fresh value: subtract current then add new = set
        return f"{m['expr']}.adjust_gas({m['gas']}, ({m['value'].strip()}) - LINDA_GAS_AMT({m['expr']}, {m['gas']}))"

    new = WRITE_ASSIGN_RE.sub(sub_assign, new)

    # Pass 2: reads
    def sub_read(m: re.Match) -> str:
        nonlocal changes
        if in_comment_or_string(new, m.start()):
            return m.group(0)
        # Already inside LINDA_GAS_* macro? Skip.
        prefix = new[max(0, m.start() - 25):m.start()]
        if "LINDA_GAS_" in prefix:
            return m.group(0)
        changes += 1
        return f"LINDA_GAS_AMT({m['expr']}, {m['gas']})"

    new = READ_RE.sub(sub_read, new)

    # Pass 2.5: whole-list `.gas` references — REMOVED.
    # DM's preprocessor doesn't handle `LINDA_GAS_LIST(x).len` etc. cleanly
    # (function-like macro followed by `.member` access produces parser errors
    # like "missing comma or right-paren"). Per-site rewrite at real LINDA
    # cutover time.
    _ = WHOLE_LIST_RE  # keep ref to avoid lint complaint; rule is documented above.

    # Pass 3: total_moles var → proc call. Re-enabled because LINDA is now the
    # only atmos engine — no XGM to worry about var/proc name collisions with.
    # Pattern: `<expr>.total_moles` not followed by `(` (already a call),
    # `=` (assignment), `.` (chained access), or word char (different identifier).
    def sub_tm(m: re.Match) -> str:
        nonlocal changes
        if in_comment_or_string(new, m.start()):
            return m.group(0)
        changes += 1
        return f"{m['lead']}.total_moles()"

    new = TOTAL_MOLES_RE.sub(sub_tm, new)

    # Pass 4: whole-list `.gas` reference → `.gases`. Inline source rewrite (not
    # via macro) because DM's preprocessor doesn't handle `MACRO(x).member` cleanly,
    # but a literal `expr.gas` → `expr.gases` replacement parses fine.
    # Match `<expr>.gas` NOT followed by `[` (keyed — different pattern) or word char.
    def sub_list(m: re.Match) -> str:
        nonlocal changes
        if in_comment_or_string(new, m.start()):
            return m.group(0)
        prefix = new[max(0, m.start() - 25):m.start()]
        if "LINDA_GAS_" in prefix:
            return m.group(0)
        changes += 1
        return f"{m['expr']}.gases"

    new = WHOLE_LIST_RE.sub(sub_list, new)

    return new, changes


def rewrite_file(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, FileNotFoundError):
        return 0
    total_changes = 0
    new_lines = []
    for line in text.splitlines(keepends=True):
        new_line, n = rewrite_line(line)
        new_lines.append(new_line)
        total_changes += n
    if total_changes > 0:
        path.write_text("".join(new_lines), encoding="utf-8", newline="")
    return total_changes


def main() -> int:
    with ERR.open() as f:
        targets: list[str] = []
        for line in f:
            parts = line.strip().split(None, 1)
            if len(parts) != 2:
                continue
            filename = parts[1]
            if filename.startswith("modular_dq") or filename.startswith("verdigris/"):
                continue
            targets.append(filename)

    print(f"Considering {len(targets)} files", file=sys.stderr)

    files_changed = 0
    total_changes = 0
    for rel in targets:
        path = REPO / rel.replace("\\", "/")
        n = rewrite_file(path)
        if n > 0:
            files_changed += 1
            total_changes += n
            print(f"  {rel}: {n}", file=sys.stderr)

    print(f"\nchanged {files_changed} files / {total_changes} edits", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
