// Dynamic point-of-interest system for expedition sites.
//
// A POI is a code-built cluster of content (a guarded vault, a hostile nest, a
// survivor camp, a salvage field, a loot cache, a survey relay, a derelict
// outpost) stamped onto walkable floor at a chosen centre turf. Missions stamp
// the POI that carries their objective (vault -> relic, camp -> survivor pod);
// the controller scatters ambient POIs for flavour and reward density.
//
// Each POI dresses itself with biome-appropriate decoration and tier-rolled
// loot (see expedition_loot.dm) so two sites rarely look or pay out the same.
//
// stamp() returns the POI's "objective atom" when it has one (so a mission can
// track it), or null for ambient-only POIs.

/datum/expedition_poi
	/// Display name (used in logs / future map markers).
	var/name = "site of interest"
	/// Relative weight when the controller scatters ambient POIs.
	var/weight = 10
	/// Minimum site difficulty this POI may appear at when scattered.
	var/min_difficulty = EXP_DIFF_LOW

/datum/expedition_poi/proc/stamp(turf/center, datum/expedition_site/site)
	return null

// Walkable floors within `radius` of a centre, for placing sub-content.
// Biome-agnostic (cave rock, grass, station plating all count).
/datum/expedition_poi/proc/nearby_floors(turf/center, radius = 3)
	var/list/out = list()
	if(!isturf(center))
		return out
	for(var/turf/T in range(radius, center))
		if(expedition_is_walkable(T))
			out += T
	return out

// Scatter `count` tier-rolled loot items on floors near the centre. Each item
// rolls its own tier so a single cluster spans a range of qualities.
/datum/expedition_poi/proc/scatter_loot(turf/center, datum/expedition_site/site, count, radius = 3)
	var/list/spots = nearby_floors(center, radius)
	var/diff = site ? site.difficulty : EXP_DIFF_LOW
	var/size = site ? site.size : EXP_SIZE_SMALL
	for(var/i in 1 to count)
		if(!length(spots))
			break
		expedition_spawn_loot(pick_n_take(spots), expedition_roll_tier(diff, size))

// Biome-appropriate set-dressing near the centre, layered with the site's
// faction theming (resin for xenos, wreckage/oil for synths, camp grime for mercs).
/datum/expedition_poi/proc/decorate(turf/center, datum/expedition_site/site, radius = 4, count = 0)
	expedition_decorate(center, radius, site ? site.biome : null, count || rand(4, 9))
	if(site && site.faction != EXP_FACTION_FAUNA)
		expedition_faction_decorate(center, radius, site.faction, rand(2, 5))

// ---------------------------------------------------------------------------
// Vault — a relic plus a locked treasure safe, guarded and grisly. Returns the
// relic so a retrieval mission can track it.
// ---------------------------------------------------------------------------
/datum/expedition_poi/vault
	name = "sealed vault"
	weight = 6
	min_difficulty = EXP_DIFF_MED

/datum/expedition_poi/vault/stamp(turf/center, datum/expedition_site/site)
	var/obj/item/expedition_artifact/relic = new(center)
	var/list/spots = nearby_floors(center, 3)
	spots -= center
	// A cracked-open treasure safe for the high-value haul.
	if(length(spots))
		var/turf/safe_spot = pick_n_take(spots)
		var/obj/structure/closet/crate/secure/lootsafe/L = new(safe_spot)
		L.generate_loot()
	// Guards scale a touch with difficulty, and match the site's enemy faction.
	var/guards = (site && site.difficulty >= EXP_DIFF_HIGH) ? 3 : 2
	for(var/i in 1 to guards)
		if(!length(spots))
			break
		expedition_spawn_guard(pick_n_take(spots), site ? site.faction : EXP_FACTION_FAUNA, site ? site.difficulty : EXP_DIFF_LOW)
	decorate(center, site, 3, rand(5, 9))
	return relic

// ---------------------------------------------------------------------------
// Camp — a survivor stasis capsule, scattered supplies, and remains.
// Returns the capsule so a rescue mission can track it.
// ---------------------------------------------------------------------------
/datum/expedition_poi/camp
	name = "stranded camp"
	weight = 4
	min_difficulty = EXP_DIFF_LOW

/datum/expedition_poi/camp/stamp(turf/center, datum/expedition_site/site)
	var/obj/structure/expedition_survivor_pod/pod = new(center)
	var/list/spots = nearby_floors(center, 2)
	if(length(spots))
		new /obj/structure/closet/crate(pick_n_take(spots))
	scatter_loot(center, site, 3, 3)
	decorate(center, site, 3, rand(3, 6))
	return pod

// ---------------------------------------------------------------------------
// Nest — a knot of hostile fauna over a grisly lair. Ambient threat; drops a
// little loot among the remains.
// ---------------------------------------------------------------------------
/datum/expedition_poi/nest
	name = "fauna nest"
	weight = 12

/datum/expedition_poi/nest/stamp(turf/center, datum/expedition_site/site)
	var/list/spots = nearby_floors(center, 2)
	var/count = 3 + (site && site.size >= EXP_SIZE_LARGE ? 2 : 0)
	for(var/i in 1 to count)
		if(!length(spots))
			break
		expedition_spawn_guard(pick_n_take(spots), site ? site.faction : EXP_FACTION_FAUNA, site ? site.difficulty : EXP_DIFF_LOW)
	scatter_loot(center, site, 2, 2)
	decorate(center, site, 3, rand(5, 10))
	return null

// ---------------------------------------------------------------------------
// Cache — a loot crate (or two on bigger sites) of tier-rolled supplies.
// ---------------------------------------------------------------------------
/datum/expedition_poi/cache
	name = "supply cache"
	weight = 14

/datum/expedition_poi/cache/stamp(turf/center, datum/expedition_site/site)
	var/obj/structure/closet/crate/C = new(center)
	var/diff = site ? site.difficulty : EXP_DIFF_LOW
	var/size = site ? site.size : EXP_SIZE_SMALL
	var/rolls = 2 + size
	for(var/i in 1 to rolls)
		expedition_spawn_loot(null, expedition_roll_tier(diff, size), C)
	// Bigger sites get a second crate nearby.
	if(size >= EXP_SIZE_MEDIUM)
		var/list/spots = nearby_floors(center, 2)
		spots -= center
		if(length(spots))
			var/obj/structure/closet/crate/C2 = new(pick_n_take(spots))
			expedition_spawn_loot(null, expedition_roll_tier(diff, size), C2)
			expedition_spawn_loot(null, expedition_roll_tier(diff, size), C2)
	decorate(center, site, 3, rand(2, 5))
	return C

// ---------------------------------------------------------------------------
// Salvage field — scattered sellable salvage and wreckage across a wide radius.
// ---------------------------------------------------------------------------
/datum/expedition_poi/salvage_field
	name = "salvage field"
	weight = 8

/datum/expedition_poi/salvage_field/stamp(turf/center, datum/expedition_site/site)
	var/list/spots = nearby_floors(center, 4)
	var/list/pool = list(
		/obj/item/salvage/ruin/pirate,
		/obj/item/salvage/ruin/russian,
		/obj/item/salvage/ruin/nanotrasen,
		/obj/item/salvage/loot/syndicate,
	)
	var/count = 4 + (site && site.size >= EXP_SIZE_LARGE ? 3 : 0)
	for(var/i in 1 to count)
		if(!length(spots))
			break
		var/salvage_path = pick(pool)
		new salvage_path(pick_n_take(spots))
	scatter_loot(center, site, 2, 4)
	decorate(center, site, 4, rand(5, 10))
	return null

// ---------------------------------------------------------------------------
// Relay — an ambient survey marker with a little grime around it.
// ---------------------------------------------------------------------------
/datum/expedition_poi/relay
	name = "survey relay"
	weight = 6

/datum/expedition_poi/relay/stamp(turf/center, datum/expedition_site/site)
	. = new /obj/structure/expedition_survey_beacon(center)
	decorate(center, site, 2, rand(2, 4))

// ---------------------------------------------------------------------------
// Hive — a xenomorph infestation: resin-choked ground, an egg clutch, a nest, and
// a brood of xenos crowned by a praetorian/queen. Forces the XENO faction locally
// regardless of the site's rolled faction, so it always reads as a hive. Ambient
// threat (returns null) but a dense, dangerous one — gated to MED+ sites.
// ---------------------------------------------------------------------------
/datum/expedition_poi/hive
	name = "xenomorph hive"
	weight = 5
	min_difficulty = EXP_DIFF_MED

/datum/expedition_poi/hive/stamp(turf/center, datum/expedition_site/site)
	var/diff = site ? site.difficulty : EXP_DIFF_MED
	// Resin-infest the ground and seed a nest at the heart of it.
	for(var/turf/T in range(3, center))
		if(expedition_is_walkable(T) && prob(55))
			new /obj/effect/alien/weeds(T)
	new /obj/structure/bed/nest(center)

	var/list/spots = nearby_floors(center, 3)
	spots -= center
	// A clutch of eggs (a lurking ghost may hatch into one) and a little resin cover.
	for(var/i in 1 to rand(3, 5))
		if(!length(spots))
			break
		new /obj/structure/ghost_pod/automatic/xenomorph_egg(pick_n_take(spots))
	for(var/i in 1 to rand(1, 3))
		if(!length(spots))
			break
		new /obj/structure/alien/membrane(pick_n_take(spots))

	// The living brood: a knot of grunts plus the hive's elite.
	var/brood = 3 + (site && site.size >= EXP_SIZE_LARGE ? 2 : 0)
	for(var/i in 1 to brood)
		if(!length(spots))
			break
		expedition_spawn_guard(pick_n_take(spots), EXP_FACTION_XENO, diff)
	if(length(spots))
		expedition_spawn_boss(pick_n_take(spots), EXP_FACTION_XENO, diff)

	scatter_loot(center, site, 2, 3)
	decorate(center, site, 3, rand(3, 6))
	return null

// ---------------------------------------------------------------------------
// Outpost — a procedurally-built structure (rooms, corridors, doors, furnished
// interiors) stamped into the terrain, with loot/hostiles in its rooms and
// debris strewn around the entrances.
// ---------------------------------------------------------------------------
/datum/expedition_poi/outpost
	name = "derelict outpost"
	weight = 5
	min_difficulty = EXP_DIFF_LOW

/datum/expedition_poi/outpost/stamp(turf/center, datum/expedition_site/site)
	var/size = site ? site.size : EXP_SIZE_SMALL
	var/dim = 12 + size * 4
	var/datum/expedition_building/B = new()
	B.loot_difficulty = site ? site.difficulty : EXP_DIFF_LOW
	B.loot_size = size
	B.loot_biome = site ? site.biome : null
	if(!B.build(center, rand(dim - 2, dim + 4), rand(dim - 2, dim + 4)))
		qdel(B)
		return null
	for(var/list/c in B.room_centers)
		var/turf/rt = locate(c[1], c[2], center.z)
		if(!rt)
			continue
		if(prob(45))
			expedition_spawn_loot(rt, expedition_roll_tier(B.loot_difficulty, size))
		else if(prob(40))
			expedition_spawn_guard(rt, site ? site.faction : EXP_FACTION_FAUNA, site ? site.difficulty : EXP_DIFF_LOW)
	qdel(B)
	return null
