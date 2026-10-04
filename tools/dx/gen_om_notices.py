"""Generates the notice types and the event mapping table for the om event -> notice / guard migration (G3).

    python tools/dx/gen_om_notices.py           # writes code/_generated/om_notices.dm and tools/dx/codemods/om_event_map.json
    python tools/dx/gen_om_notices.py --check   # CI: fails when either is stale

For every /datum/om/event type with at least one listener (a behaviour `handles`, an om_hook()/om_unhook() call, a
task interrupt, a cache rule or any other non-emit reference outside tests):
  - an after-fact event (not under /datum/om/event/before/) gets a generated `/datum/notice/<name>` with the event's
    payload vars as fields and a fill() in the event's New() argument order (doc/rewrite/reactions.md section 3);
  - a veto event (/datum/om/event/before/...) maps to a GUARD_* key (code/__defines/reactions.dm) when the decision
    table below names one, else to "op" (it becomes an operation's before_op) or "review".
The map records, per event: the target (notice type, guard key, op, review, delete), the payload fields, the emit
files, the listener files and whether an emit site reads the result (a notice returns nothing: such a site needs a
guard or a review). The A4 codemod reads it. Events with no listener are not generated: delete them with their emit
sites. Events already converted by hand (shoes_step_action, the spontaneous vore guards) are gone from the tree.
"""
import collections
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DM = os.path.join(ROOT, "code", "_generated", "om_notices.dm")
OUT_MAP = os.path.join(ROOT, "tools", "dx", "codemods", "om_event_map.json")

EVENT_PATH = re.compile(r"/datum/om/event/[A-Za-z0-9_/]+")
# Veto event -> guard key (G3 decision): the rest of before/* become an op's before_op ("op") or need review.
GUARDS = {
    "before/movable_pre_move": "GUARD_MOVE",
    "before/movable_z_changed": "GUARD_Z_CHANGE",
    "before/in_range_of_irradiation": "GUARD_IRRADIATE",
    "before/living_irradiate_effect": "GUARD_IRRADIATE",
    "before/living_injure": "GUARD_INJURE",
    "before/living_body_status": "GUARD_BODY_STATUS",
    "before/attackby": "GUARD_ATTACKBY",
    "before/attack_self": "GUARD_ATTACK_SELF",
    "before/attack_hand": "GUARD_ATTACK_HAND",
    "before/atom_tool_act": "GUARD_TOOL_ACT",
    "before/click_alt": "GUARD_CLICK_ALT",
}
# After-facts whose listeners mostly only clear references: relations do that now (delete the hook).
RELATION_CLEARED = {"qdeleting"}
# Veto events whose remaining listeners only watch: they get a notice twin too (the twin is published when the event is emitted, before the
# action, so a watcher hears it exactly when its om_hook did). The emit sites and the listeners that veto or accumulate stay as they are.
NOTIFY_BEFORE = {
    "before/in_range_of_irradiation": "in_range_of_irradiation",
    "before/movable_z_changed": "movable_z_changed",
    "before/living_status_sleep": "living_status_sleep",
    "before/atom_extinguish": "atom_extinguish",
    "before/living_turf_collision": "living_turf_collision",
    "before/belly_update_vore_fx": "belly_update_vore_fx",
    "before/atom_take_damage": "atom_take_damage",
    "before/attack_self": "attack_self",
    "before/click_alt": "click_alt",
    "before/movable_bump": "movable_bump",
    "before/robot_item_attack": "robot_item_attack",
    "before/attack_hand": "attack_hand",
    "before/item_pre_attack": "item_pre_attack",
    "before/attackby": "attackby",
}
# After-fact events only unit tests watch: they get a notice twin so a test observe()s it as production listeners do (om_hook is gone).
TEST_WATCHED = {
    "machinery_broken", "living_injury_explained", "living_death_final", "body_part_detached", "body_part_attached",
    "reagents_holder_reacted", "item_tool_acted", "tool_atom_acted", "unittest_data", "slot_inserted", "slot_removed",
}
# Base /datum/notice fields an event field may not shadow.
RESERVED = {"source", "data", "type", "parent_type", "vars", "tag", "pool_state", "pool_max_free", "holder", "target", "outcome", "cap", "activation", "op_key"}


def dm_files():
    for top, _, files in os.walk(os.path.join(ROOT, "code")):
        for f in files:
            if f.endswith(".dm"):
                path = os.path.join(top, f)
                yield path, os.path.relpath(path, ROOT).replace(os.sep, "/")


def scan():
    events = {}  # name -> {"vars": [...], "args": [...], "file": rel}
    refs = collections.defaultdict(lambda: collections.defaultdict(list))
    for path, rel in dm_files():
        if rel.startswith("code/_generated/"):
            continue
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
        current = None
        in_handles = False
        for no, line in enumerate(lines, 1):
            stripped = line.strip()
            m = re.match(r"^/datum/om/event/([A-Za-z0-9_/]+?)(/New\((.*)\)|/dispatch\(.*\))?\s*$", line)
            if m and "unit_tests" not in rel and "benchmarks" not in rel:
                name = m.group(1)
                ev = events.setdefault(name, {"vars": [], "args": None, "file": rel})
                if m.group(2) and m.group(2).startswith("/New("):
                    ev["args"] = [a.strip().split("=")[0].strip().split("/")[-1] for a in m.group(3).split(",") if a.strip()]
                    current = None
                elif not m.group(2):
                    current = name
                else:
                    current = None
                continue
            if current and line.startswith("\t"):
                vm = re.match(r"^\tvar/(?:[\w]+/)*(\w+)", line)
                if vm:
                    events[current]["vars"].append(vm.group(1))
                continue
            if line and not line[0].isspace():
                current = None
            if stripped.startswith("//"):
                continue
            for raw in EVENT_PATH.findall(line):
                name = raw[len("/datum/om/event/"):].rstrip("/")
                for suffix in ("/New", "/dispatch"):
                    if name.endswith(suffix):
                        name = name[: -len(suffix)]
                if "unit_tests" in rel or "benchmarks" in rel:
                    kind = "test"
                elif re.search(r"OM_EMIT|om_emit\(|om_wants\(|new /datum/om/event/", line):
                    kind = "emit"
                elif re.search(r"om_hook|om_unhook|om_hooked", line):
                    kind = "hook"
                elif "handles" in line or in_handles:
                    kind = "handles"
                else:
                    kind = "other"
                refs[name][kind].append("%s:%d" % (rel, no))
            if "handles = list(" in line and not line.rstrip().endswith(")"):
                in_handles = True
            elif in_handles and ")" in line:
                in_handles = False
    return events, refs


def reads_result(sites):
    for site in sites:
        rel, no = site.rsplit(":", 1)
        line = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read().split("\n")[int(no) - 1]
        if re.search(r"(=|\bif\s*\(|&|\breturn\b|==)\s*[!(]*\s*(OM_EMIT|om_emit)", line) or "== EVENT_VETO" in line:
            return True
    return False


def build():
    events, refs = scan()
    table = {}
    notices = []
    for name in sorted(events):
        if name in ("before", "next", "queued", "proc"):
            continue
        r = refs.get(name, {})
        listeners = r.get("hook", []) + r.get("handles", []) + r.get("other", [])
        emits = r.get("emit", [])
        ev = events[name]
        fields = ev["args"] if ev["args"] is not None else ev["vars"]
        # Files only (no line numbers), so an unrelated edit never makes the checked-in map stale.
        def files(sites):
            return sorted({site.rsplit(":", 1)[0] for site in sites})
        row = {"fields": fields, "emits": files(emits), "listeners": files(listeners), "tests": files(r.get("test", [])),
               "reads_result": reads_result(emits)}
        if not listeners and name not in NOTIFY_BEFORE and name not in TEST_WATCHED:
            row["target"] = "delete" if not r.get("test") else "review"
        elif name in NOTIFY_BEFORE:
            notice = "/datum/notice/" + NOTIFY_BEFORE[name]
            row["target"] = notice
            row["notice_fields"] = [f if f not in RESERVED else f + "_" for f in fields]
            row["note"] = "a veto event whose watchers use the notice twin; emit sites and vetoing listeners stay on the event"
            notices.append((notice, name, fields))
        elif name.startswith("before/"):
            row["target"] = GUARDS.get(name, "op" if name.split("/", 1)[1] in ("item_pre_attack", "robot_item_attack", "catch_throw") else "review")
        else:
            notice = "/datum/notice/" + name.replace("/", "_")
            row["target"] = notice
            row["notice_fields"] = [f if f not in RESERVED else f + "_" for f in fields]
            if name in RELATION_CLEARED:
                row["note"] = "most hooks only clear a reference: declare the relation and delete the hook"
            if row["reads_result"]:
                row["note"] = (row.get("note", "") + "; an emit site reads the result: review").lstrip("; ")
            notices.append((notice, name, fields))
        table["/datum/om/event/" + name] = row
    return table, notices


def render_dm(notices):
    out = ["// GENERATED by tools/dx/gen_om_notices.py: do not edit (CI checks freshness).",
           "// One notice per om event that has a listener (doc/rewrite/reactions.md section 3); the mapping table is",
           "// tools/dx/codemods/om_event_map.json. Fields are the event's payload, filled in its New() order.",
           ""]
    for notice, name, fields in notices:
        safe = [f if f not in RESERVED else f + "_" for f in fields]
        out.append("/// From /datum/om/event/%s." % name)
        out.append(notice)
        for f in safe:
            out.append("\tvar/%s" % f)
        out.append("")
        if safe:
            out.append("%s/fill(%s)" % (notice, ", ".join(safe)))
            for f in safe:
                out.append("\tsrc.%s = %s" % (f, f))
            out.append("")
    return "\n".join(out).rstrip() + "\n"


def main():
    table, notices = build()
    dm = render_dm(notices)
    js = json.dumps(table, indent=1, sort_keys=True) + "\n"
    if "--check" in sys.argv:
        stale = []
        for path, text in ((OUT_DM, dm), (OUT_MAP, js)):
            if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
                stale.append(os.path.relpath(path, ROOT))
        if stale:
            print("gen_om_notices: stale, run python tools/dx/gen_om_notices.py: " + ", ".join(stale))
            return 1
        return 0
    os.makedirs(os.path.dirname(OUT_MAP), exist_ok=True)
    with open(OUT_DM, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(dm)
    with open(OUT_MAP, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(js)
    counts = collections.Counter(row["target"] if not row["target"].startswith("/datum/notice/") else "notice" for row in table.values())
    print("gen_om_notices: %d events: %s" % (len(table), dict(counts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
