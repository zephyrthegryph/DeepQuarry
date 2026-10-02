"""Mob presentation is reactive (doc/rewrite/reactions.md "Generated reads", living_systems.dm).

The HUD, sight and canmove passes of /mob/living are on_change() reactions whose reads are declared by hand (published
keys) and generated from what their procs read (code/_generated/reads.dm). Nothing refreshes them by hand.

Rules (every one must reach 0):

  presentation_call   A call of a HUD or sight pass (life_hud*(), life_vision*()) or of the deleted
                      refresh_vision() from content: anything but another HUD / sight proc (a proc whose own name
                      starts with life_hud / life_vision, or one of the reaction handlers). Write the input through its
                      setter or publish the key that covers it (MOB_KEY_VIEW, MOB_KEY_HUD_FLAGS, ...).
"""
import re

RULES = {
    "presentation_call": "write the input through its setter or PUBLISH_CHANGE the key that covers it (MOB_KEY_*); "
                         "the HUD / sight reactions run by themselves (living_systems.dm)",
}

CALL = re.compile(r"(?<![\w/])(?:[\w\]\)]+\.)?(life_hud\w*|life_vision\w*|refresh_vision)\s*\(")
PROC_DEF = re.compile(r"^/[\w/]*?/(?:(?:proc|verb)/)?(\w+)\s*\(")
# Questions about the passes, not passes.
QUERIES = ("_wanted", "_idle", "_rewake_delay")
# Procs that are part of the passes themselves: they may call each other.
OWNERS = re.compile(r"^(?:life_hud|life_vision)")


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        if rel.startswith("code/_generated/"):
            continue
        proc = None
        for number, line in enumerate(lines, 1):
            if line and not line[0].isspace():
                m = PROC_DEF.match(line)
                proc = m.group(1) if m else None
                continue
            code = line.split("//", 1)[0]
            m = CALL.search(code)
            if not m or m.group(1).endswith(QUERIES):
                continue
            if proc and OWNERS.match(proc):
                continue
            out["presentation_call"].append((rel, number))
    return out
