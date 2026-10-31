"""Move candidate checker. See move_candidates.sh for the rules."""
import os
import posixpath
import re
import subprocess
import sys

NEW_TREE = ("code/engine/", "code/library/", "code/domains/", "code/content/", "code/world/", "code/defines/", "code/_generated/")
# Old directory -> section 22 target. Anything not listed becomes code/content/<name>.
DOMAINS = {"power": "domains/power", "heat": "domains/heat", "ATMOSPHERICS": "domains/atmos", "body": "domains/body",
           "damage": "domains/damage", "combat_ai": "domains/ai", "life": "domains/life"}
OLD_FORMS = [
    ("Destroy()", re.compile(r"^\s*(?:[\w/]+/)?Destroy\(")),
    ("spawn", re.compile(r"\bspawn\s*\(")),
    ("sleep", re.compile(r"\bsleep\s*\(")),
    ("do_after", re.compile(r"\bdo_after\s*\(")),
    ("INVOKE_ASYNC", re.compile(r"\bINVOKE_ASYNC\b")),
    ("Initialize", re.compile(r"^\s*(?:[\w/]+/)?Initialize\(")),
    ("LateInitialize", re.compile(r"\bLateInitialize\b|\bINITIALIZE_HINT_LATELOAD\b")),
    ("Topic", re.compile(r"^\s*(?:[\w/]+/)?Topic\(")),
    ("flow_ask", re.compile(r"\bflow_ask\b")),
    ("CHANGE_", re.compile(r"\bCHANGE_\w+")),
]
NEW_DEF = re.compile(r"^\s*((?:/[\w/]+?)?/?)New\(")
TYPE_HEAD = re.compile(r"^\s*(/[A-Za-z_][\w/]*)\s*$")
ATOM_ROOTS = ("atom", "obj", "mob", "turf", "area")


def atom_new_override(lines):
    """A New() override on an atom type (atoms construct through Initialize). A plain datum's New() is its constructor
    (final_api section 6: 'a plain datum: New()'), /image and /client are not atoms, so those stay clean."""
    cur = ""
    for ln in lines:
        m = NEW_DEF.match(ln)
        if m:
            path = m.group(1).rstrip("/") if m.group(1) else ""
            if path.endswith("/proc"):
                path = path[:-5]
            owner = path if path else cur
            if owner.split("/")[1:2] and owner.split("/")[1] in ATOM_ROOTS:
                return True
            continue
        h = TYPE_HEAD.match(ln)
        if h:
            cur = h.group(1)
    return False


VERB_DEF = re.compile(r"^\s*(?:(/[\w/]+?)/verb/|verb/)(\w+)")
GRANTED_VERB = re.compile(r"\b(?:granted_verb|verb_entry)\(\s*(/[\w/]+)|\b(?:ability|driver)\s*=\s*(/[\w/]+/verb/\w+)")


def non_client_verb(lines, granted=(), path=""):
    """A verb declared on a type other than /client. final_api section 17: the verb set holds client, OOC and admin
    commands only; a /client/verb is that final form, anything else on a mob or datum is a gameplay ability (an op)."""
    cur = ""
    for i, ln in enumerate(lines):
        m = VERB_DEF.match(ln)
        if m:
            owner = m.group(1) or cur  # `verb/x` indented under a type block belongs to that block's type
            if m.group(2) in KEYBIND_VERBS.get(path, ()):
                continue
            category, hidden = "", False
            for nxt in lines[i + 1:i + 10]:
                c = re.search(r"set category\s*=\s*(\w+)", nxt)
                if c:
                    category = c.group(1)
                if re.search(r"set hidden\s*=\s*(?:1|TRUE)\b", nxt):
                    hidden = True
            if hidden or (category and FINAL_VERB_CATEGORY.search(category)):
                continue
            if owner + "/verb/" + m.group(2) in granted:
                continue  # granted_verb()/verb_entry() is the final form of a verb a type or a source hands out
            if owner.split("/")[1:2] != ["client"]:
                return True
            continue
        h = TYPE_HEAD.match(ln)
        if h:
            cur = h.group(1)
    return False


# lint_scopes.toml exempts these by path (unit tests, benchmarks, the vendored TGS DMAPI: they build and wait on the old forms
# on purpose), so a text match there is not an old form. Admin commands are verbs by design (final_api section 17).
OLDFORM_EXEMPT = ("code/tests/", "code/modules/unit_tests/", "code/modules/benchmarks/", "code/modules/tgs/")
# The controller base and the GLOB holder run before the kernel exists: Initialize() is their boot hook, and the holder's
# Destroy() deliberately never runs the parent chain (admin var-edit exploit). Neither has a declared replacement.
BOOT_HOLDERS = ("code/controllers/controller.dm", "code/controllers/globals.dm",
                # BYOND's own entry points, which have no replacement: /client/Topic and /client/Destroy are the href and logout hooks, the metrics
                # wrapper brackets /client/Topic, and /area/New() is where the maploader registers an area before any init chain exists.
                "code/modules/client/client procs.dm", "code/modules/metrics/metrics_capture.dm", "code/game/area/areas.dm",
                # the root of every datum's Destroy() chain, and the /world href hook
                "code/datums/datum.dm", "code/game/world.dm")
# Chat, OOC and input verbs a player types by name or binds to a key are the final form (final_api section 17, "client, OOC and
# admin commands"). An explicit list of files, never a pattern: a new verb file has to be added here on purpose.
OOC_VERB_FILES = (
    "code/modules/mob/say_old.dm", "code/modules/mob/typing_indicator.dm", "code/modules/examine/examine.dm",
    "code/modules/point/point.dm", "code/modules/mob/language/language_panel.dm", "code/modules/client/verbs/suicide.dm",
    "code/modules/mob/combat_mode.dm", "code/modules/mob/autowhisper.dm", "code/game/skincmd.dm",
    "code/modules/player_tips/player_tips_controller.dm",
)
# A verb is also final by what it is, never by the file it sits in: its category says it is an OOC, ghost or settings command, it is hidden (a
# keybind wrapper the client calls by name), or it is one of these named typed-command and keybind verbs of the core mobs.
FINAL_VERB_CATEGORY = re.compile(r"^(?:VERB_CAT_)?(?:OOC|GHOST|PREFERENCES)|_SETTINGS$")
KEYBIND_VERBS = {
    "code/modules/mob/mob.dm": {"mode", "memory", "add_memory", "stop_pulling", "face_direction"},
    "code/modules/mob/living/living.dm": {"pulled", "succumb", "toggle_afk", "resist", "lay_down", "open_private_notes"},
    "code/modules/mob/say.dm": {"me_verb_subtle_custom", "psay", "pme", "player_narrate"},
    "code/modules/multiz/movement.dm": {"up", "down", "climb_down"},
    "code/modules/nifsoft/software/13_soulcatcher.dm": {"nsay_brain", "nme_brain"},
}
VERB_EXEMPT = ("code/modules/admin/", "/admin_commands.dm", "/contract_admin.dm")

# A spawn/sleep/INVOKE_ASYNC/do_after line that carries an ALLOW(scheduler): <reason> annotation is a justified keep (the scheduler lint
# demands the reason: the kernel's own loop, a callee that blocks on a window). It is not an old form, so the line is blanked before the
# old-form patterns run. An annotation on a comment-only line covers the code line below it.
SCHEDULER_KEEP = re.compile(r"ALLOW\(scheduler[^)]*\)")


def blank_scheduler_keeps(text):
    raw = text.split("\n")
    for i, ln in enumerate(raw):
        if not SCHEDULER_KEEP.search(ln):
            continue
        code = ln.split("//")[0]
        if code.strip():
            raw[i] = "// " + ln.split("//", 1)[1] if "//" in ln else ""
        elif i + 1 < len(raw):
            raw[i + 1] = ""
    return "\n".join(raw)


# A raw input()/alert() call, or a verb whose arguments are BYOND's own pickers (`target as mob in view()`), is not a final form even when the verb is
# granted: a question is an asks() step or an open_request(). (Typed chat and OOC verbs are exempt by name, above.)
RAW_PROMPT = re.compile(r"(?<![\w.])(?:input|alert)\(")
VERB_PICKER_ARG = re.compile(r"^\s*(?:/[\w/]+?/verb/|verb/)\w+\([^)]*\bas\b[^)]*\bin\b")


ALLOW = re.compile(r"\bALLOW\(([^)]*)\)")
# doc/rewrite/migration_census.md kind M: an annotation naming one of these keeps a migration form, so the file is not done.
# Any other lint's ALLOW (scheduler, silent_catch, ownership, api, ...) is a justified keep and does not block a move.
MIGRATION_ALLOW = ("init", "base_vars", "stored_refs", "ref_text", "native_ref_write", "decl")


def migration_allow(text):
    for m in ALLOW.finditer(text):
        for name in m.group(1).split(","):
            if name.strip().split("/")[0] in MIGRATION_ALLOW:
                return True
    return False
TYPE_DEF = re.compile(r"^(/[A-Za-z_][\w/]*)\s*(?:\(|$)")
TYPE_REF = re.compile(r"/(?:obj|mob|turf|area|datum|atom)(?:/[A-Za-z_]\w*)+")
DATA_EXT = (".txt", ".json", ".tsv", ".csv", ".sha256sum", ".patch", ".toml")
SCRIPT_EXT = (".sh", ".py", ".ts", ".rs", ".js", ".cmd", ".ps1")


def run(args, cwd):
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, check=False).stdout.decode("utf-8", "replace")
    except OSError:
        return ""


def list_files(root):
    out = run(["git", "ls-files", "-z"], root)
    if out:
        return [p for p in out.split("\0") if p]
    found = []
    for d, _, names in os.walk(root):
        for n in names:
            found.append(os.path.relpath(os.path.join(d, n), root).replace(os.sep, "/"))
    return found


def read(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def target_of(rel):
    parts = rel.split("/")
    if parts[0] != "code" or len(parts) < 3 or rel.startswith(NEW_TREE):
        return None
    top = parts[1]
    if top == "game" and parts[2] == "objects" and len(parts) > 4:
        return "code/content/" + "/".join(parts[3:])  # doc section 22 M07: objects/{items,structures,effects} -> content/{items,structures,effects}
    if top in ("modules", "game", "datums") and len(parts) > 3:
        name = parts[2]
        layer = DOMAINS.get(name, "content/" + name)
        return "code/" + layer + "/" + "/".join(parts[3:])
    if top in DOMAINS:
        return "code/" + DOMAINS[top] + "/" + "/".join(parts[2:])
    return "code/content/" + "/".join(parts[1:])


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return [re.sub(r"//.*", "", ln) for ln in text.split("\n")]


SYSTEM_DEF = re.compile(r"^\s*SYSTEM_DEF\((\w+)\)")
SYSTEM_PROC = re.compile(r"^/datum/system/(\w+)/proc/")


INCLUDE = re.compile(r'^\s*#include\s+"([^"]+)"')


def relative_includes(root, dm):
    """{file: [note, ...]}: relative `#include "..."` lines in .dm files, resolved against the including file's directory
    (the .dme lists root-relative paths and is not scanned). A note lands on the included file and on the includer, since a move
    of either breaks the path; the note names the line to update."""
    present = set(dm)
    notes = {}
    for g in dm:
        for n, ln in enumerate(strip_comments(read(root, g)), 1):
            m = INCLUDE.match(ln)
            if not m:
                continue
            h = posixpath.normpath(posixpath.join(posixpath.dirname(g), m.group(1).replace("\\", "/")))
            if h not in present:
                continue
            notes.setdefault(h, []).append("relinc:%s:%d" % (g, n))
            notes.setdefault(g, []).append("relinc:%s:%d" % (g, n))
    return notes


def references(root, files):
    """(kind, reference) pairs from baselines and tool sources."""
    refs = []
    pat = re.compile(r"\bcode/[\w./\-]+")
    for rel in files:
        kind = None
        if rel == "tools/dm-health/baseline.json":
            kind = "baseline"
        elif rel.startswith("tools/ci/") and rel != "tools/ci/lint_scopes.toml":
            if rel.endswith(SCRIPT_EXT):
                kind = "toolref"
            elif rel.endswith(DATA_EXT) or "/" in rel[len("tools/ci/"):]:
                kind = "baseline"
        elif rel.startswith(("tools/analyze/src/", "tools/build/")) and rel.endswith(SCRIPT_EXT):
            kind = "toolref"
        if kind is None:
            continue
        for m in set(pat.findall(read(root, rel))):
            ref = m.rstrip(".,;:'\"")
            # A bare domain-level directory (code/modules/, code/modules/clothing/) is a mention, not a file reference: moving the
            # domain is what the lint_scopes commit follows. A file or a deeper directory names specific files.
            if not ref.endswith(".dm") and len(ref.rstrip("/").split("/")) < 4:
                continue
            refs.append((kind, ref))
    return refs


def main(argv):
    root = None
    summary = False
    only = None
    paths = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--root":
            i += 1
            root = argv[i]
        elif a == "--summary":
            summary = True
        elif a == "--clean":
            only = "clean"
        elif a == "--dirty":
            only = "dirty"
        elif a.startswith("-"):
            print("move_candidates: unknown flag " + a, file=sys.stderr)
            return 2
        else:
            paths.append(a.rstrip("/"))
        i += 1
    if root is None:
        root = run(["git", "rev-parse", "--show-toplevel"], ".").strip() or "."
    files = list_files(root)
    dm = [f for f in files if f.endswith(".dm")]
    old = [f for f in dm if target_of(f) is not None]
    if paths:
        old = [f for f in old if any(f == p or f.startswith(p + "/") for p in paths)]
    refs = references(root, files)
    relinc = relative_includes(root, dm)
    content_types = set()
    for f in dm:
        if f.startswith("code/content/"):
            for ln in strip_comments(read(root, f)):
                m = TYPE_DEF.match(ln)
                if m:
                    content_types.add(m.group(1))
    granted = set()
    for f in dm:
        text = read(root, f)
        if "granted_verb" in text or "verb_entry" in text or "ability" in text or "driver" in text:
            for ln in strip_comments(text):
                for a, b in GRANTED_VERB.findall(ln):
                    granted.add(a or b)
    rows = []
    for f in sorted(old):
        why = []
        for kind, ref in refs:
            if f == ref or f.startswith(ref if ref.endswith("/") else ref + "/"):
                why.append(kind + ":" + ref)
        text = read(root, f)
        if migration_allow(text):
            why.append("allow")
        lines = strip_comments(blank_scheduler_keeps(text))
        exempt = f.startswith(OLDFORM_EXEMPT) or f in BOOT_HOLDERS
        for label, rx in ([] if exempt else OLD_FORMS):
            if any(rx.search(ln) for ln in lines):
                why.append("oldform:" + label)
        if not exempt and f not in OOC_VERB_FILES and not any(v in f for v in VERB_EXEMPT) and non_client_verb(lines, granted, f):
            why.append("oldform:verb")
        if not exempt and f not in OOC_VERB_FILES and not any(v in f for v in VERB_EXEMPT) and any(RAW_PROMPT.search(ln) or VERB_PICKER_ARG.match(ln) for ln in lines):
            why.append("oldform:raw_prompt")
        if not exempt and atom_new_override(lines):
            why.append("oldform:New() override")
        if "/__defines/" in f:
            why.append("defines")
        target = target_of(f)
        note = ""
        if target and target.startswith(("code/library/", "code/domains/", "code/engine/")):
            hit = sorted({t for ln in lines for t in TYPE_REF.findall(ln) if t in content_types})
            if hit:
                note = "layering:" + ",".join(hit[:3])
        if f in relinc:
            note = (note + " " + ",".join(dict.fromkeys(relinc[f]))).strip()
        reason = ";".join(dict.fromkeys(why))
        rows.append(("dirty" if why else "clean", f, target or "-", (reason + " " + note).strip()))
    # system_boundary B3: a proc defined on /datum/system/X must sit in the folder of the file that declares X (SYSTEM_DEF(X)).
    # A file that defines such procs stays dirty while the declaring file is in the old tree and is not itself moving clean.
    owner = {}
    for f in dm:
        for ln in strip_comments(read(root, f)):
            m = SYSTEM_DEF.match(ln)
            if m:
                owner.setdefault(m.group(1), f)
    state = {r[1]: r[0] for r in rows}
    for i, (st, f, target, reason) in enumerate(rows):
        hit = []
        for ln in strip_comments(read(root, f)):
            m = SYSTEM_PROC.match(ln)
            if m and m.group(1) in owner and owner[m.group(1)] != f:
                o = owner[m.group(1)]
                if target_of(o) is not None and state.get(o, "dirty") == "dirty":
                    hit.append("systemowner:" + o)
        if hit:
            rows[i] = ("dirty", f, target, (";".join(dict.fromkeys(hit)) + " " + reason).strip())
    if summary:
        agg = {}
        for state, f, _, _ in rows:
            parts = f.split("/")
            d = "/".join(parts[:3]) if len(parts) > 3 else "/".join(parts[:-1])
            c = agg.setdefault(d, [0, 0])
            c[0 if state == "clean" else 1] += 1
        for d, (c, x) in sorted(agg.items(), key=lambda kv: -kv[1][0]):
            print("%5d clean %5d dirty  %s" % (c, x, d))
        return 0
    for row in rows:
        if only is None or row[0] == only:
            print("\t".join(row))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
