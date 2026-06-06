"""One-shot: strip all USE_LINDA_ATMOS gating from vorestation.dme.

After this script runs:
  * Every `#ifdef USE_LINDA_ATMOS \n <includes> \n #endif`  →  the includes are unconditional.
  * Every `#ifndef USE_LINDA_ATMOS \n <includes> \n #endif` →  the entire block (XGM/ZAS) is deleted.
  * Adjacent `// DQEdit` comment markers explaining the gates are removed.

LINDA becomes the only atmos engine. XGM and ZAS source files remain on disk
(untouched) but are no longer compiled into the build. They can be deleted in
a follow-up commit if desired.

Idempotent: re-running is a no-op once gating is gone.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DME = REPO / "vorestation.dme"


def strip_gates(text: str) -> str:
    """Process the DME line by line, collapsing or removing gate blocks."""
    lines = text.splitlines(keepends=False)
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # `#ifdef USE_LINDA_ATMOS` — keep contents, drop the directive lines.
        if stripped == "#ifdef USE_LINDA_ATMOS":
            # Pop any immediately-preceding `// DQEdit` or `// LINDA atmos` comment block.
            while out and out[-1].lstrip().startswith("//") and (
                "DQEdit" in out[-1] or "LINDA" in out[-1] or "atmos" in out[-1].lower()
                or "Phase" in out[-1] or "atmospherics_linda" in out[-1]
            ):
                out.pop()
            # Skip the `#ifdef` line itself.
            i += 1
            # Copy through until matching `#endif`.
            depth = 1
            while i < len(lines) and depth > 0:
                inner = lines[i]
                ins = inner.strip()
                if ins.startswith("#ifdef") or ins.startswith("#ifndef") or ins.startswith("#if"):
                    depth += 1
                    out.append(inner)
                elif ins == "#endif":
                    depth -= 1
                    if depth > 0:
                        out.append(inner)
                else:
                    out.append(inner)
                i += 1
            continue

        # `#ifndef USE_LINDA_ATMOS` — DROP entire block (XGM/ZAS code is excluded).
        if stripped == "#ifndef USE_LINDA_ATMOS":
            # Pop any preceding DQEdit/comment markers explaining the gate.
            while out and out[-1].lstrip().startswith("//") and (
                "DQEdit" in out[-1] or "LINDA" in out[-1] or "atmos" in out[-1].lower()
                or "XGM" in out[-1] or "ZAS" in out[-1] or "Phase" in out[-1]
            ):
                out.pop()
            # Skip until matching #endif (and the #endif itself).
            i += 1
            depth = 1
            while i < len(lines) and depth > 0:
                ins = lines[i].strip()
                if ins.startswith("#ifdef") or ins.startswith("#ifndef") or ins.startswith("#if"):
                    depth += 1
                elif ins == "#endif":
                    depth -= 1
                i += 1
            continue

        out.append(line)
        i += 1

    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def main() -> int:
    text = DME.read_text(encoding="utf-8")
    new_text = strip_gates(text)
    if new_text == text:
        print("vorestation.dme already ungated", file=sys.stderr)
        return 0
    DME.write_text(new_text, encoding="utf-8", newline="")
    before = len(text.splitlines())
    after = len(new_text.splitlines())
    print(f"vorestation.dme: {before} -> {after} lines ({before - after} removed)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
