// Enemy-faction system for expedition sites.
//
// Every site rolls (or a mission pins) one EXP_FACTION_* that themes the hostiles
// guarding it — wild fauna, a xenomorph brood, rogue synthetics, or hostile
// mercenaries. POIs and combat objectives don't hardcode mob types anymore; they
// pull grunts from the site's faction via expedition_spawn_guard() and bosses via
// expedition_faction_boss(), so each launch faces a coherent, themed threat.
//
// Rosters scale with the site's difficulty band; the boss is the elite an
// "eliminate_boss" / "siege" objective slays.

// Human-readable threat descriptor (site name suffix + console readout).
/proc/expedition_faction_name(faction)
	switch(faction)
		if(EXP_FACTION_XENO)
			return "xenomorph infestation"
		if(EXP_FACTION_SYNTH)
			return "rogue synthetics"
		if(EXP_FACTION_MERC)
			return "hostile mercenaries"
	return "hostile wildlife"

// Roll a faction for a new site. Fauna dominates at low difficulty; the hostile
// outfits open up as difficulty climbs. Values (not keys) are numeric, so we
// weight by repetition + pick() rather than pickweight (numeric keys are illegal).
/proc/expedition_pick_faction(difficulty)
	var/list/pool
	switch(difficulty)
		if(EXP_DIFF_LOW)
			pool = list(EXP_FACTION_FAUNA, EXP_FACTION_FAUNA, EXP_FACTION_FAUNA, EXP_FACTION_FAUNA, EXP_FACTION_FAUNA,
				EXP_FACTION_XENO, EXP_FACTION_SYNTH, EXP_FACTION_MERC)
		if(EXP_DIFF_MED)
			pool = list(EXP_FACTION_FAUNA, EXP_FACTION_FAUNA, EXP_FACTION_FAUNA,
				EXP_FACTION_XENO, EXP_FACTION_XENO, EXP_FACTION_SYNTH, EXP_FACTION_SYNTH,
				EXP_FACTION_MERC, EXP_FACTION_MERC)
		else
			pool = list(EXP_FACTION_FAUNA, EXP_FACTION_FAUNA,
				EXP_FACTION_XENO, EXP_FACTION_XENO, EXP_FACTION_XENO,
				EXP_FACTION_SYNTH, EXP_FACTION_SYNTH, EXP_FACTION_SYNTH,
				EXP_FACTION_MERC, EXP_FACTION_MERC, EXP_FACTION_MERC)
	return pick(pool)

// The grunt roster per faction per difficulty band: [EXP_FACTION_*][EXP_DIFF_*].
GLOBAL_LIST_INIT(expedition_hostile_pools, list(
	list( // EXP_FACTION_FAUNA
		list(/mob/living/simple_mob/animal/space/carp, /mob/living/simple_mob/animal/giant_spider),
		list(/mob/living/simple_mob/animal/giant_spider, /mob/living/simple_mob/animal/sif/leech),
		list(/mob/living/simple_mob/animal/space/shark, /mob/living/simple_mob/animal/sif/leech),
	),
	list( // EXP_FACTION_XENO
		list(/mob/living/simple_mob/animal/space/alien/drone),
		list(/mob/living/simple_mob/animal/space/alien/drone, /mob/living/simple_mob/animal/space/alien/hunterling),
		list(/mob/living/simple_mob/animal/space/alien/hunterling, /mob/living/simple_mob/animal/space/alien/hunterlisk, /mob/living/simple_mob/animal/space/alien/sentinel),
	),
	list( // EXP_FACTION_SYNTH
		list(/mob/living/simple_mob/mechanical/viscerator, /mob/living/simple_mob/mechanical/combat_drone/lesser),
		list(/mob/living/simple_mob/mechanical/combat_drone, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/basic),
		list(/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong, /mob/living/simple_mob/mechanical/hivebot/tank),
	),
	list( // EXP_FACTION_MERC
		list(/mob/living/simple_mob/humanoid/merc/melee/poi, /mob/living/simple_mob/humanoid/merc/ranged/poi),
		list(/mob/living/simple_mob/humanoid/merc/melee/sword/poi, /mob/living/simple_mob/humanoid/merc/ranged/smg/poi, /mob/living/simple_mob/humanoid/merc/ranged/rifle/poi),
		list(/mob/living/simple_mob/humanoid/merc/ranged/rifle/mag/poi, /mob/living/simple_mob/humanoid/merc/ranged/laser/poi, /mob/living/simple_mob/humanoid/merc/ranged/technician/poi),
	),
))

/// Index into the per-faction tables; unknown factions fall back to fauna.
#define EXP_FACTION_INDEX(faction) ((faction == EXP_FACTION_XENO || faction == EXP_FACTION_SYNTH || faction == EXP_FACTION_MERC) ? faction : EXP_FACTION_FAUNA)

// The grunt roster for a faction at a difficulty band. Used by missions/POIs/the
// controller for every ambient and objective hostile spawn. Shared: read-only.
/proc/expedition_hostile_pool(difficulty, faction = EXP_FACTION_FAUNA)
	var/list/by_difficulty = GLOB.expedition_hostile_pools[EXP_FACTION_INDEX(faction)]
	return by_difficulty[(difficulty == EXP_DIFF_LOW || difficulty == EXP_DIFF_MED) ? difficulty : EXP_DIFF_HIGH]

// The elite a faction fields. Bigger threats at higher difficulty where it matters.
/proc/expedition_faction_boss(faction, difficulty = EXP_DIFF_MED)
	switch(faction)
		if(EXP_FACTION_XENO)
			return (difficulty >= EXP_DIFF_HIGH) ? /mob/living/simple_mob/animal/space/alien/queen : /mob/living/simple_mob/animal/space/alien/sentinel/praetorian
		if(EXP_FACTION_SYNTH)
			return /mob/living/simple_mob/mechanical/hivebot/support/commander
		if(EXP_FACTION_MERC)
			return /mob/living/simple_mob/humanoid/merc/ranged/sniper
	return /mob/living/simple_mob/animal/sif/savik

// One-line threat briefing for the mission board / active readout.
/proc/expedition_faction_brief(faction)
	switch(faction)
		if(EXP_FACTION_XENO)
			return "A xenomorph brood has infested the site."
		if(EXP_FACTION_SYNTH)
			return "Rogue synthetics hold the site."
		if(EXP_FACTION_MERC)
			return "A mercenary company has dug in at the site."
	return "Hostile wildlife has claimed the site."

// Reward multiplier — tougher factions pay a threat premium.
/proc/expedition_faction_danger(faction)
	switch(faction)
		if(EXP_FACTION_XENO)
			return 1.25
		if(EXP_FACTION_SYNTH)
			return 1.3
		if(EXP_FACTION_MERC)
			return 1.4
	return 1.0

// Themed kill-loot a grunt may drop (path = drop-chance %), per EXP_FACTION_*. Appended to each
// spawned guard's simple_mob loot_list, so the spoils match who you're fighting.
GLOBAL_LIST_INIT(expedition_faction_loot_pools, list(
	list(/obj/random/awayloot = 12), // EXP_FACTION_FAUNA
	list(/obj/random/awayloot = 20, /obj/item/aliencoin/basic = 12), // EXP_FACTION_XENO
	list(/obj/random/powercell = 30, /obj/random/tech_supply = 22, /obj/random/tool = 18), // EXP_FACTION_SYNTH
	list(/obj/random/contraband = 28, /obj/random/cash/big = 22), // EXP_FACTION_MERC
))

/// The faction's kill-loot pool (shared, read-only).
/proc/expedition_faction_loot_pool(faction)
	return GLOB.expedition_faction_loot_pools[EXP_FACTION_INDEX(faction)]

// The prize the faction's elite is guaranteed to be guarding.
/proc/expedition_faction_boss_loot(faction)
	switch(faction)
		if(EXP_FACTION_XENO)
			return /obj/item/capture_crystal/great
		if(EXP_FACTION_SYNTH)
			return /obj/item/cell/void
		if(EXP_FACTION_MERC)
			return /obj/item/aliencoin/gold
	return /obj/item/aliencoin/silver

// Faction set-dressing pool (cheap decals / props), layered over biome decor, per EXP_FACTION_*.
GLOBAL_LIST_INIT(expedition_faction_decor_pools, list(
	null, // EXP_FACTION_FAUNA: fauna leans on the biome's own decor
	list( // EXP_FACTION_XENO
		/obj/effect/alien/weeds = 10,
		/obj/effect/decal/cleanable/blood = 5,
		/obj/structure/alien/membrane = 2,
	),
	list( // EXP_FACTION_SYNTH
		/obj/effect/decal/cleanable/blood/oil = 8,
		/obj/effect/decal/remains/robot = 5,
		/obj/effect/decal/mecha_wreckage = 3,
	),
	list( // EXP_FACTION_MERC
		/obj/effect/decal/cleanable/dirt = 8,
		/obj/effect/decal/cleanable/blood = 5,
		/obj/effect/decal/remains/human = 3,
	),
))

/// The faction's decor pool (shared, read-only), or null.
/proc/expedition_faction_decor_pool(faction)
	return GLOB.expedition_faction_decor_pools[EXP_FACTION_INDEX(faction)]

// Scatter `count` faction props on walkable floors near a centre. No-op for fauna.
/proc/expedition_faction_decorate(turf/center, radius, faction, count)
	if(!isturf(center))
		return
	var/list/pool = expedition_faction_decor_pool(faction)
	if(!length(pool))
		return
	var/list/spots = list()
	for(var/turf/T in range(radius, center))
		if(expedition_is_walkable(T))
			spots += T
	for(var/i in 1 to count)
		if(!length(spots))
			break
		var/turf/T = pick_n_take(spots)
		var/dtype = pickweight(pool)
		new dtype(T)

// Spawn a single faction-appropriate grunt on `T`, seeded with themed kill-loot.
// Returns the new mob (or null).
/proc/expedition_spawn_guard(turf/T, faction = EXP_FACTION_FAUNA, difficulty = EXP_DIFF_LOW)
	if(!isturf(T))
		return null
	var/list/pool = expedition_hostile_pool(difficulty, faction)
	if(!length(pool))
		return null
	var/mob_path = pick(pool)
	var/mob/M = new mob_path(T)
	var/mob/living/simple_mob/SM = M
	if(istype(SM))
		var/list/fl = expedition_faction_loot_pool(faction)
		SM.loot_list = SM.loot_list ? SM.loot_list.Copy() : list()
		for(var/p in fl)
			SM.loot_list[p] = fl[p]
	return M

// Spawn the faction's elite, guarding a guaranteed reward. Returns the boss.
/proc/expedition_spawn_boss(turf/T, faction = EXP_FACTION_FAUNA, difficulty = EXP_DIFF_MED)
	if(!isturf(T))
		return null
	var/boss_path = expedition_faction_boss(faction, difficulty)
	var/mob/M = new boss_path(T)
	var/mob/living/simple_mob/SM = M
	if(istype(SM))
		SM.loot_list = SM.loot_list ? SM.loot_list.Copy() : list()
		SM.loot_list[expedition_faction_boss_loot(faction)] = 100
	return M

#undef EXP_FACTION_INDEX
