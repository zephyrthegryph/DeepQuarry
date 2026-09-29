"""sys_lint module: moving an item by hand next to the ownership call that adopts it (design review §7).

own_set()/own_add()/own_put() move the item into the holder as part of adopting it (and, with
dx-transfer, take it out of the user's hand, slot or container). Dropping it from the hand and
forceMove()-ing it in by hand around that call duplicates the transfer, and the two drift apart
(a missed unEquip, a stale hand overlay, an item left in two places):

    own_set(src, nameof(cell), held)                 // not user.drop_item(); held.forceMove(src); own_set(...)

Rule:
  dx_manual_transfer   a line with drop_item( / drop_from_inventory( / unEquip( / remove_from_mob( /
                       forceMove(src) / `loc = src` within NEAR lines of an own_set / own_add /
                       own_put call in the same proc.

Static limits: "near" is a line window inside one proc body, not data flow, so an unrelated drop
in the window counts (ALLOW it with `// ALLOW(sys_dx_manual_transfer): <reason>`). The baseline
(tools/ci/sys_baseline/dx_manual_transfer.txt) holds the legacy sites; target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "dx_manual_transfer": "let own_set()/own_add()/own_put() move the item (and take it from the hand); drop the manual drop/forceMove (design review §7)",
}

NEAR = 6
ADOPT = re.compile(r"(?<![\w./:])own_(?:set|add|put)\s*\(")
MANUAL = re.compile(r"(?<![\w/])(?:drop_item|drop_from_inventory|unEquip|remove_from_mob)\s*\("
                    r"|(?<![\w/])forceMove\(\s*src\s*\)"
                    r"|(?<![\w/])loc\s*=(?!=)\s*src\b(?!\s*\.)")


def scan_procs(procs_list):
    found = []
    for proc in procs_list:
        adopt_lines = [n for n, text in proc.lines() if ADOPT.search(text)]
        if not adopt_lines:
            continue
        for number, text in proc.lines():
            if MANUAL.search(text) and any(abs(number - a) <= NEAR for a in adopt_lines):
                found.append((proc.rel, number))
    return found


def scan(files):
    out = {rule: [] for rule in RULES}
    tree = dm.tree(files)
    relevant = {rel for rel, _l in files if ADOPT.search(tree.raw_text(rel))}
    out["dx_manual_transfer"] = scan_procs([p for p in tree.procs if p.rel in relevant])
    return out


FIXTURE = """
/obj/machinery/charger/proc/insert_cell(mob/user, obj/item/cell/C)
	if(!user.drop_item())
		return
	C.forceMove(src)
	own_set(src, nameof(cell), C)
	to_chat(user, "You insert [C].")

/obj/machinery/charger/proc/good_insert(mob/user, obj/item/cell/C)
	own_set(src, nameof(cell), C)
	to_chat(user, "You insert [C].")

/obj/machinery/charger/proc/far_away(mob/user, obj/item/cell/C)
	own_set(src, nameof(cell), C)
	sleep(1)
	sleep(1)
	sleep(1)
	sleep(1)
	sleep(1)
	sleep(1)
	sleep(1)
	user.drop_item()

/obj/machinery/charger/proc/no_adopt(mob/user, obj/item/I)
	user.unEquip(I)
	I.loc = src

/obj/machinery/charger/proc/loc_write(mob/user, obj/item/I)
	user.remove_from_mob(I)
	I.loc = src
	own_add(src, nameof(parts), I)
	if(I.loc == src)
		return
"""


def selftest():
    lines = FIXTURE.split("\n")
    got = sorted(n for _r, n in scan_procs(dm.procs([("x.dm", lines)])))

    def at(snippet, nth=0):
        return [k + 1 for k, line in enumerate(lines) if snippet in line][nth]
    assert got == sorted([at("if(!user.drop_item())"), at("C.forceMove(src)"),
                          at("user.remove_from_mob(I)"), at("I.loc = src", 1)]), got
    return "dx_manual_transfer"
