"""Actor forwarding lint (roadmap I3, doc/rewrite/interactions.md section 4).

The AI, cyborg and ghost capability adapters give every atom the hands
behaviour for free: a type sets `silicon_use` (SILICON_USE_*, ROBOT_USE_*)
instead of overriding attack_ai, attack_robot or attack_ghost just to call
attack_hand, attack_ai or tgui_interact. This lint rejects overrides whose whole
body is such a forward:

    /obj/foo/attack_ai(mob/user)       -> silicon_use = SILICON_USE_HAND
        return attack_hand(user)
    /obj/foo/attack_ai(mob/user)       -> silicon_use = SILICON_USE_UI
        tgui_interact(user)
    /obj/foo/attack_robot(mob/user)    -> silicon_use = ROBOT_USE_HAND
        attack_hand(user)
    /obj/foo/attack_robot(mob/user)    -> silicon_use = ROBOT_USE_HAND_ADJACENT
        if(Adjacent(user))
            attack_hand(user)
    /obj/foo/attack_robot(mob/user)    -> delete it: that is the default
        attack_ai(user)
    /obj/foo/attack_ghost(mob/user)    -> delete it: /obj/attack_ghost opens the UI
        tgui_interact(user)

A forward is still needed when an ancestor overrides the proc with different
behaviour (a digital valve under a manual one); those are in ALLOWLIST.

Usage:
    python tools/ci/actor_forwarding_lint.py
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

HEAD = re.compile(r"^(/[\w/]+)/(attack_ai|attack_robot|attack_ghost)\(([^)]*)\)\s*(?://.*)?$")


def arg_name(params):
    """`mob/living/user as mob` -> `user`."""
    params = re.sub(r"\s+as\s+\w+.*$", "", params.split(",")[0]).strip()
    return re.split(r"[/\s]", params)[-1] if params else "user"

# type/proc pairs that must forward because an ancestor overrides the proc
# with other behaviour, or that live in files another track owns. Must not grow.
ALLOWLIST = {
    "/obj/machinery/atmospherics/tvalve/digital/attack_ai",
    "/obj/machinery/atmospherics/valve/digital/attack_ai",
    "/obj/machinery/atmospherics/valve/shutoff/attack_ai",
    "/obj/machinery/light/flamp/attack_ai",
    "/obj/machinery/body_scanconsole/attack_ai",
    "/obj/machinery/clonepod/attack_ai",
    "/obj/machinery/computer/cloning/attack_ai",
    "/obj/machinery/computer/cryopod/attack_ai",
    "/obj/machinery/computer/med_data/attack_ai",
    "/obj/machinery/computer/pandemic/attack_ai",
    "/obj/machinery/computer/transhuman/designer/attack_ai",
    "/obj/machinery/computer/transhuman/resleeving/attack_ai",
    "/obj/machinery/sleep_console/attack_ai",
    "/obj/structure/medical_stand/attack_robot",
    "/obj/machinery/atmospherics/unary/cryo_cell/attack_ghost",
    "/obj/machinery/computer/pandemic/attack_ghost",
}


def forward_kind(proc, arg, body):
    """The forward this body is, or None if it does something else."""
    arg = re.escape(arg or "user")
    lines = [re.sub(r"\bsrc\.", "", line) for line in body]
    if lines and re.fullmatch(r"return(?: 0| 1| TRUE| FALSE)?", lines[-1]):
        lines = lines[:-1]
    if proc == "attack_ai":
        lines = [line for line in lines if line != "add_hiddenprint(%s)" % (arg.replace("\\", ""))]
    if len(lines) == 1:
        one = lines[0]
        if proc in ("attack_ai", "attack_robot") and re.fullmatch(r"(?:return )?attack_hand\((?:%s)?\)" % arg, one):
            return "attack_hand"
        if proc in ("attack_ai", "attack_ghost") and re.fullmatch(r"(?:return )?tgui_interact\(%s\)" % arg, one):
            return "tgui_interact"
        if proc == "attack_robot" and re.fullmatch(r"(?:return )?attack_ai\(%s\)" % arg, one):
            return "attack_ai"
    if proc == "attack_robot" and len(lines) == 2 and lines[0] == "if(Adjacent(%s))" % arg.replace("\\", "") \
            and re.fullmatch(r"(?:return )?attack_hand\(%s\)" % arg, lines[1]):
        return "adjacent attack_hand"
    return None


def scan(path, rel):
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().split("\n")
    i = 0
    while i < len(lines):
        match = HEAD.match(lines[i])
        if not match:
            i += 1
            continue
        start = i + 1
        body = []
        i += 1
        while i < len(lines) and (lines[i][:1] in ("\t", " ") or not lines[i].strip()):
            text = lines[i].strip()
            if text and not text.startswith("//"):
                body.append(re.sub(r"\s*//.*$", "", text))
            i += 1
        type_path, proc, params = match.groups()
        arg = arg_name(params)
        if type_path.endswith("/proc") or not body:
            continue
        kind = forward_kind(proc, arg, body)
        if kind and "%s/%s" % (type_path, proc) not in ALLOWLIST:
            yield "%s:%d: %s/%s only forwards to %s" % (rel, start, type_path, proc, kind)


def main():
    failures = []
    code = os.path.join(ROOT, "code")
    for directory, _, files in os.walk(code):
        for name in files:
            if not name.endswith(".dm"):
                continue
            path = os.path.join(directory, name)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            failures.extend(scan(path, rel))
    for failure in sorted(failures):
        print(failure)
    if failures:
        print("\nERROR: forwarding-only attack_ai/attack_robot/attack_ghost overrides. Set `silicon_use` "
              "(SILICON_USE_HAND, SILICON_USE_UI, ROBOT_USE_HAND, ROBOT_USE_HAND_ADJACENT) or delete the "
              "override; see tools/ci/actor_forwarding_lint.py.")
        return 1
    print("actor forwarding lint: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
