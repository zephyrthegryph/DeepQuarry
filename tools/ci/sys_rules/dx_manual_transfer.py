"""sys_lint module: hand-rolled transfers the one-call own_set / own_add / own_put replaces.

doc/rewrite/ownership.md §1.3a, code/datums/ownership/transfer.dm. Giving an owned var a movable
that is somewhere else is one call:

    own_set(src, "beaker", W, user = user)

It checks that the item can leave its hand, equip slot, storage or holder and enter this one,
releases it (HUD, dropped(), storage bookkeeping), moves it in and adopts it. The old sequence took
it out by hand (`drop_item()` / `drop_from_inventory()` / `unEquip()` / `remove_from_mob()` /
`remove_from_storage()`), moved it (`forceMove(src)`), then adopted it, with no check that the drop
worked. Target: 0 (the baseline is empty).

    manual_transfer    an own_* call within a few lines of a take-out call in the same proc
    manual_move_adopt  `X.forceMove(H)` right before `own_*(H, "var", X)` (own_set moves it itself;
                       `into = TRUE` for a loose thing off a turf)
"""
import re

RULES = {
    "manual_transfer": "own_set/own_add/own_put(holder, \"var\", item, user = user): one call takes it out of the hand, slot or storage (ownership.md §1.3a)",
    "manual_move_adopt": "own_set/own_add/own_put(holder, \"var\", item, into = TRUE) moves it in itself (ownership.md §1.3a)",
}

TAKE_OUT = re.compile(r"\b(drop_item|drop_from_inventory|unEquip|remove_from_mob|drop_l_hand|drop_r_hand|drop_active_hand|remove_from_storage)\s*\(")
OWN = re.compile(r"\bown_(?:set|add|put)\s*\(\s*([\w.]+)\s*,\s*[^,()]+\s*,\s*(?:[^,()]+,\s*)?([\w.]+)\s*[,)]")
MOVE = re.compile(r"([\w.]+)\s*\??\.\s*forceMove\s*\(\s*([\w.]+)\s*\)|([\w.]+)\.loc\s*=\s*([\w.]+)\s*$")

BEFORE = 5  # lines looked at before an own_* call
AFTER = 2   # and after it (the take-out written second)

EXEMPT_PREFIXES = (
    "code/datums/ownership/",
    "code/datums/containment/",
)


def _holder(name):
    return "src" if name in ("src", "") else name


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        if rel.startswith(EXEMPT_PREFIXES):
            continue
        code = [line.split("//", 1)[0] for line in lines]
        for i, text in enumerate(code):
            match = OWN.search(text)
            if not match:
                continue
            holder, value = _holder(match.group(1)), match.group(2)
            took = False
            moved = False
            for j in range(i - 1, max(-1, i - BEFORE - 1), -1):
                if code[j].startswith("/"):
                    break  # the proc header: another proc above
                if TAKE_OUT.search(code[j]):
                    took = True
                for move in MOVE.finditer(code[j]):
                    what = move.group(1) or move.group(3)
                    where = _holder(move.group(2) or move.group(4))
                    if what == value and where == holder:
                        moved = True
            for j in range(i + 1, min(len(code), i + AFTER + 1)):
                if code[j].startswith("/"):
                    break
                if TAKE_OUT.search(code[j]):
                    took = True
            if took:
                out["manual_transfer"].append((rel, i + 1))
            elif moved:
                out["manual_move_adopt"].append((rel, i + 1))
    return out
