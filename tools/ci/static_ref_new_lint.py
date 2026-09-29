#!/usr/bin/env python3
"""Flags `new` values assigned into vars declared DECLARE_REF(..., STATIC).

A STATIC var holds a round-long singleton/flyweight and is never cleared or deleted.
Putting a freshly `new`ed per-owner object in one means nothing owns it: it is dropped
without qdel() when the var is overwritten, and every om_handle() to it then reports
HANDLE TARGET COLLECTED WITHOUT QDEL (the per-mob species copy bug). Declare such a var
OWNED/HELD instead, or route it through an owning setter (see adopt_species()).

Ratchet: existing sites are baselined by file:var; new ones fail.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CODE = ROOT / "code"
DECL = re.compile(r'DECLARE_REF\([^,]+,\s*"([A-Za-z_]\w*)",\s*STATIC\b')
# file (posix, relative to repo) : var -- pre-existing sites, burn down, never add.
BASELINE = {
	"code/controllers/subsystems/shuttles.dm:shuttle",
	"code/game/objects/items/weapons/storage/uplink_kits.dm:pack",
	"code/modules/body/factors.dm:rules",
	"code/modules/blob2/overmind/overmind.dm:blob_type",
	"code/modules/blob2/core_chunk.dm:blob_type",
	"code/modules/contracts/medical_trial.dm:profile",
	"code/datums/rules/binding.dm:table",
	"code/game/machinery/frame.dm:frame_type",
	"code/modules/lore_codex/codex_tree.dm:home",
	"code/modules/mob/living/silicon/ai/ai.dm:selected_sprite",
	"code/modules/mob/living/silicon/robot/robot.dm:sprite_datum",
	"code/modules/research/tg/disks.dm:stored_research_static",
	"code/modules/research/research_service.dm:error_design",
	"code/modules/research/research_service.dm:error_node",
	"code/game/objects/effects/chem/chemsmoke.dm:targetTurfs",
	"code/game/objects/effects/chem/chemsmoke.dm:wallList",
}

def main():
	files = list(CODE.rglob("*.dm"))
	names = set()
	texts = {}
	for f in files:
		t = f.read_text(encoding="utf-8", errors="replace")
		texts[f] = t
		names.update(DECL.findall(t))
	if not names:
		print("static_ref_new_lint: no STATIC declarations found?")
		return 1
	assign = re.compile(r'^\s*(?:[\w()]+\.)?(' + "|".join(sorted(names)) + r')\s*=\s*new\b', re.M)
	bad = []
	for f, t in texts.items():
		rel = f.relative_to(ROOT).as_posix()
		for m in assign.finditer(t):
			if f"{rel}:{m.group(1)}" in BASELINE:
				continue
			line = t.count("\n", 0, m.start()) + 1
			bad.append(f"{rel}:{line}: `new` assigned into STATIC var `{m.group(1)}` -- declare it OWNED/HELD or use an owning setter")
	for b in bad:
		print(b)
	if bad:
		return 1
	print("static_ref_new_lint: clean")
	return 0

if __name__ == "__main__":
	sys.exit(main())
