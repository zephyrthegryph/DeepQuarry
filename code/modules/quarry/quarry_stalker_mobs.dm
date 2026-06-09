// Per-biome stalker mobs.
//
// One subtype per quarry tier. Each is a buffed version of an
// existing simple_mob — same AI and behavior, scaled HP and damage.
// The stalker event picks the appropriate subtype for the layer's
// depth band and spawns one of them far from any player.
//
// The parent mob types do all the heavy lifting (AI, sprite, vore
// hooks, faction). We only override stat vars and the name so a
// player examining the corpse knows what they fought.

// --- Shallows: depth 1-5 -----------------------------------------------
// Light-tier hunter. Rats are the resident pest; the elder rat is
// just bigger and meaner.
/mob/living/simple_mob/vore/aggressive/rat/quarry_stalker
	name = "elder cave rat"
	desc = "A grizzled rat the size of a small dog. Its eyes track you with disturbing intelligence."
	maxHealth = 90
	health = 90
	melee_damage_lower = 6
	melee_damage_upper = 14
	// First mob wired to the move framework. Heavy bite gives the
	// stalker a telegraphed special that doubles its damage on a
	// successful land — see /datum/quarry_mob_move/test_heavy_bite.
	quarry_move_pool = list(/datum/quarry_mob_move/test_heavy_bite)


// --- Midmines: depth 6-10 ---------------------------------------------
// Spiders take over here. A tunneler with hardened chitin.
/mob/living/simple_mob/animal/giant_spider/tunneler/cave/quarry_stalker
	name = "armored tunneler"
	desc = "A tunneler spider with hardened, dark chitin plates fused across its carapace."
	maxHealth = 160
	health = 160
	melee_damage_lower = 8
	melee_damage_upper = 18


// --- Deeps: depth 11-15 -----------------------------------------------
// Cave stalker territory. Apex pounce predator already strong; we
// just make it tougher.
/mob/living/simple_mob/vore/stalker/quarry_stalker
	name = "scarred stalker"
	desc = "A cave stalker covered in old wounds and fresh scars. The fangs are longer than most."
	maxHealth = 220
	health = 220
	melee_damage_lower = 6
	melee_damage_upper = 16


// --- Abyss: depth 16-20 -----------------------------------------------
// Oregrubs go from pest to predator. A queen-class grub.
/mob/living/simple_mob/vore/oregrub/quarry_stalker
	name = "oregrub matriarch"
	desc = "An oregrub grown obscenely large on a diet of rare minerals. Its mandibles glitter."
	maxHealth = 300
	health = 300
	melee_damage_lower = 10
	melee_damage_upper = 22


// --- Core: depth 21-25 ------------------------------------------------
// Top tier. A stalker even the other stalkers fear.
/mob/living/simple_mob/vore/stalker/quarry_stalker_core
	name = "core stalker"
	desc = "Larger than any cave stalker you've seen, its hide shot through with crystalline blue veins. It moves with terrible purpose."
	maxHealth = 450
	health = 450
	melee_damage_lower = 14
	melee_damage_upper = 28


// --- Roster lookup ----------------------------------------------------
//
// Stalker spawner picks one of these based on layer depth. Returns
// null for unmapped depths (e.g. surface) so the event no-ops.
/proc/quarry_stalker_type_for_depth(depth)
	if(depth >= 21)
		return /mob/living/simple_mob/vore/stalker/quarry_stalker_core
	if(depth >= 16)
		return /mob/living/simple_mob/vore/oregrub/quarry_stalker
	if(depth >= 11)
		return /mob/living/simple_mob/vore/stalker/quarry_stalker
	if(depth >= 6)
		return /mob/living/simple_mob/animal/giant_spider/tunneler/cave/quarry_stalker
	if(depth >= 1)
		return /mob/living/simple_mob/vore/aggressive/rat/quarry_stalker
	return null
