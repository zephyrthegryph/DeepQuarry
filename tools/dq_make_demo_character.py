#!/usr/bin/env python3
"""Add a demo character to a preferences.json: linked palette slots, skin colour, a tail, ears and markings.

    python tools/dq_make_demo_character.py <preferences.json> [--slot N] [--name "Demo Palette"] [--write]

Without --write it only prints what it would do. It adds a character to an EMPTY slot and never overwrites one;
with --write it keeps a copy at <preferences.json>.bak-demo first. Style and marking names are read from the
sprite accessory sources of the checkout it runs from, so run it from a checkout matching the server, with the
server stopped or the player logged out (a running server rewrites the file from memory).
"""
import argparse
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PALETTE = {
    "palette_primary": "#c98f6b",
    "palette_secondary": "#3a2a4d",
    "palette_tertiary": "#d9a441",
    "palette_extra1": "#e8e4da",
    "palette_extra2": "#23303f",
}
LINKS = {
    "skin_color": "primary",
    "hair_color": "secondary",
    "facial_color": "secondary",
    "grad_color": "tertiary",
    "eyes_color": "tertiary",
    "tail_color1": "primary",
    "tail_color2": "secondary",
    "tail_color3": "tertiary",
    "ears_color1": "primary",
    "ears_color2": "secondary",
    "ears_color3": "tertiary",
    "wing_color1": "primary",
    "wing_color2": "secondary",
    "wing_color3": "tertiary",
}


def accessory_names(glob, base):
    """The name of each direct `/datum/sprite_accessory/<base>/x`, in file order."""
    names = []
    for path in sorted(ROOT.glob(glob)):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in re.finditer(rf'^/datum/sprite_accessory/{base}/\w+\r?\n\s*name = "([^"]+)"', text, re.M):
            names.append(match[1])
    return names


def build(name):
    tails = accessory_names("code/**/*tail*.dm", "tail")
    ears = accessory_names("code/**/*ear*.dm", "ears")
    if not tails or not ears:
        sys.exit("no tail or ear styles found in this checkout")
    character = {
        "real_name": name,
        "species": "Human",
        "hair_style_name": "Average Joe",
        "facial_style_name": "Shaved",
        "tail_style": tails[0],
        "ear_style": ears[0],
        "palette_linked": True,
        **PALETTE,
        **LINKS,
    }
    return character


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("save", type=Path)
    parser.add_argument("--slot", type=int)
    parser.add_argument("--name", default="Demo Palette")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    data = json.loads(args.save.read_text(encoding="utf-8"))
    slot = args.slot or next(n for n in range(1, 100) if not data.get(f"character{n}"))
    key = f"character{slot}"
    if data.get(key):
        sys.exit(f"{key} already holds a character; pick an empty slot")
    character = build(args.name)
    print(f"{key}: {json.dumps(character, indent=1)}")
    if not args.write:
        print("dry run: pass --write to add it")
        return
    shutil.copy2(args.save, str(args.save) + ".bak-demo")
    data[key] = character
    args.save.write_text(json.dumps(data, indent=1), encoding="utf-8")
    print(f"wrote {key} to {args.save}")


if __name__ == "__main__":
    main()
