"""Emag lint (doc/rewrite/systems.md section 13).

`emag_act` counts the old emag pattern, which is deleted:
  * any `emag_act` (an override, a call, or the base proc coming back);
  * a direct call of a declared emag effect (`on_emag(...)`, `x.on_emag(...)`) that bypasses
    emag_target(): the gate, the emagged field and the message live there. Proc definitions,
    PROC_REF(on_emag) and `..()` inside an override are not calls;
  * `used_uses` / `uses -=` bookkeeping around an emag outside the card (the card's spend()).
Declare the effect with DECLARE_EMAG / DECLARE_EMAG_REPEATABLE (code/__defines/sys_emag.dm) and
emag anything else with emag_target(target, charges, user, source).
"""
import re

RULES = {
    "emag_act": "DECLARE_EMAG(type, PROC_REF(on_emag), msg) + emag_target() "
                "(code/__defines/sys_emag.dm, doc/rewrite/systems.md section 13)",
}

OLD = re.compile(r"\bemag_act\b")
DIRECT = re.compile(r"(?<![\w/])(?:[\w\].]+\.)?on_emag\s*\(")
DEF = re.compile(r"^\s*/[\w/]+/(?:proc/)?on_emag\s*\(")
CARD = "code/game/objects/items/weapons/id cards/cards.dm"
BOOKKEEP = re.compile(r"\bused_uses\b")


def scan(files):
    out = {"emag_act": []}
    for rel, lines in files:
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if OLD.search(code):
                out["emag_act"].append((rel, number))
                continue
            if "on_emag" in code and not DEF.match(code):
                stripped = code.replace("PROC_REF(on_emag)", "")
                if DIRECT.search(stripped):
                    out["emag_act"].append((rel, number))
                    continue
            if rel != CARD and BOOKKEEP.search(code):
                out["emag_act"].append((rel, number))
    return out
