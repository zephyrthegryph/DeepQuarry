"""One declared loot system (doc/rewrite/systems.md section 8).

Loot is declared with DECLARE_LOOT (code/__defines/loot.dm) and rolled by loot_spawn() /
loot_search() (code/datums/loot/loot.dm). The old shapes are rejected:

  item_to_spawn      - an item_to_spawn() override or call (the per-type roll proc).
  loot_table_datum   - the second loot system: /datum/loot_table, loot_table_type, loot_reward().
  random_spawn_list  - hand-rolled spawn logic on a random spawner: any proc defined on an
                       /obj/random type, or a spawn list var (spawn_types / to_spawn / possible_* /
                       items / *_loot = list(...)) on a type in a map-resolved family.
"""
import re

RULES = {
    "item_to_spawn": "declare the table with DECLARE_LOOT(path, LOOT_TABLE(...)) (systems.md §8)",
    "loot_table_datum": "searchable tiers are DECLARE_LOOT(/loot/..., LOOT_UNCOMMON/RARE/...) + loot_search() (systems.md §8)",
    "random_spawn_list": "spawn lists and roll logic belong in DECLARE_LOOT (LOOT_TABLE/SET/SUB/HOOK), not procs or list vars (systems.md §8)",
}

ITEM_TO_SPAWN = re.compile(r"\bitem_to_spawn\b")
LOOT_TABLE = re.compile(r"/datum/loot_table\b|\bloot_table_type\b|\bloot_reward\s*\(")
RANDOM_PROC = re.compile(r"^/obj/random(_multi)?(/[\w/]*)?/(proc/|verb/)?\w+\(")
TYPE_LINE = re.compile(r"^(/[\w/]+)\s*(//.*)?$")
SPAWN_LIST_VAR = re.compile(r"^\t(var/(list/)?)?(spawn_types|to_spawn|possible_\w+|items|\w+_loot)\s*=\s*list\(")
RESOLVER = re.compile(r"^MAP_RESOLVER\((/[\w/]+),")


def _in_family(path, roots):
    while path:
        if path in roots:
            return True
        cut = path.rfind("/")
        if cut <= 0:
            return False
        path = path[:cut]
    return False


def scan(files):
    out = {rule: [] for rule in RULES}
    roots = {"/obj/random"}
    for rel, lines in files:
        for line in lines:
            m = RESOLVER.match(line)
            if m:
                roots.add(m.group(1))
    for rel, lines in files:
        cur = None
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if ITEM_TO_SPAWN.search(code):
                out["item_to_spawn"].append((rel, number))
            if LOOT_TABLE.search(code):
                out["loot_table_datum"].append((rel, number))
            if RANDOM_PROC.match(code):
                out["random_spawn_list"].append((rel, number))
            m = TYPE_LINE.match(line)
            if m:
                cur = m.group(1)
                continue
            if line and not line[0].isspace():
                cur = None
                continue
            if cur and SPAWN_LIST_VAR.match(code) and _in_family(cur, roots):
                out["random_spawn_list"].append((rel, number))
    return out
