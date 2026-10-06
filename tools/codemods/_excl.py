"""The hand-conversion list the items/structures codemods share (tools/codemods/exclusions.txt)."""
import os

_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "exclusions.txt")


def excluded(codemod):
    """{subject: reason} for one codemod's lines."""
    out = {}
    if not os.path.exists(_PATH):
        return out
    with open(_PATH, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2 and parts[0] == codemod:
                out[parts[1]] = parts[2] if len(parts) > 2 else "excluded"
    return out
