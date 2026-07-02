// Expedition objectives — the composable goals a mission is built from.
//
// A mission owns one or more objectives; the mission is a success once all its
// REQUIRED objectives are complete, and pays bonus rewards for any optional
// objectives also finished. Each objective:
//   * populate(site)      — spawns its content into the generated site.
//   * check()             — cheap poll (run on the SSexpedition tick); advances
//                           progress and flips state to COMPLETE / FAILED.
//   * objective_text()    — the console line.
//
// The taxonomy below spans combat, fetch-and-return, rescue, exploration,
// interaction, demolition, and hold-the-line defence so missions can mix them.

/datum/expedition_objective
	/// Console label.
	var/name = "Objective"
	/// Required for mission success, or an optional bonus.
	var/required = TRUE
	/// EXP_OBJ_* state.
	var/state = EXP_OBJ_INCOMPLETE
	/// Extra rewards if this (optional) objective is completed.
	var/bonus_points = 0
	var/bonus_cash = 0
	/// Back-reference to the site.
	var/datum/expedition_site/site
	/// Atoms this objective spawned / tracks.
	var/list/tracked
	/// Progress / target for the console readout.
	var/progress = 0
	var/target = 1

/datum/expedition_objective/New(_required = TRUE)
	required = _required
	tracked = list()

/datum/expedition_objective/Destroy()
	site = null
	tracked = null
	return ..()

/datum/expedition_objective/proc/populate(datum/expedition_site/S)
	site = S

/datum/expedition_objective/proc/check()
	return state

/datum/expedition_objective/proc/objective_text()
	return name

/datum/expedition_objective/proc/progress_text()
	if(target > 1)
		return "[clamp(progress, 0, target)] / [target]"
	return state == EXP_OBJ_COMPLETE ? "Done" : "Pending"

// Shared helpers -------------------------------------------------------------

/datum/expedition_objective/proc/count_returned(typepath)
	var/obj/machinery/computer/expedition/con = site?.origin_console
	return con ? con.count_on_pad(typepath) : 0

/datum/expedition_objective/proc/count_alive()
	var/n = 0
	for(var/mob/living/L in tracked)
		if(!QDELETED(L) && L.stat != DEAD)
			n++
	return n

// (Hostile rosters live in expedition_faction.dm — expedition_hostile_pool(difficulty, faction).)

// ===========================================================================
// COMBAT
// ===========================================================================

// Eliminate every hostile spawned across the site.
/datum/expedition_objective/eliminate_all
	name = "Eliminate hostiles"

/datum/expedition_objective/eliminate_all/populate(datum/expedition_site/S)
	..()
	target = 4 + S.difficulty * 2
	for(var/i in 1 to target)
		var/turf/T = S.random_floor()
		if(!T)
			continue
		var/mob/guard = expedition_spawn_guard(T, S.faction, S.difficulty)
		if(guard)
			tracked += guard

/datum/expedition_objective/eliminate_all/check()
	var/alive = count_alive()
	progress = target - alive
	if(alive <= 0)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/eliminate_all/objective_text()
	return "Eliminate all hostiles"

// Slay a single elite creature.
/datum/expedition_objective/eliminate_boss
	name = "Slay the elite"

/datum/expedition_objective/eliminate_boss/populate(datum/expedition_site/S)
	..()
	target = 1
	var/turf/T = S.random_floor()
	if(T)
		tracked += expedition_spawn_boss(T, S.faction, S.difficulty)

/datum/expedition_objective/eliminate_boss/check()
	if(count_alive() <= 0)
		progress = 1
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/eliminate_boss/objective_text()
	return "Slay the elite creature"

// Build a derelict structure and clear the hostiles holed up inside it.
/datum/expedition_objective/clear_structure
	name = "Clear the structure"

/datum/expedition_objective/clear_structure/populate(datum/expedition_site/S)
	..()
	var/turf/center = S.random_floor()
	if(!center)
		state = EXP_OBJ_COMPLETE // nothing to clear
		return
	var/datum/expedition_building/B = new()
	B.loot_difficulty = S.difficulty
	B.loot_size = S.size
	B.loot_biome = S.biome
	var/dim = 14 + S.size * 4
	if(!B.build(center, rand(dim - 2, dim + 4), rand(dim - 2, dim + 4)))
		qdel(B)
		state = EXP_OBJ_COMPLETE
		return
	for(var/list/c in B.room_centers)
		var/turf/rt = locate(c[1], c[2], center.z)
		if(!rt)
			continue
		if(prob(60))
			var/mob/guard = expedition_spawn_guard(rt, S.faction, S.difficulty)
			if(guard)
				tracked += guard
		if(prob(50))
			expedition_spawn_loot(rt, expedition_roll_tier(S.difficulty, S.size))
	if(!length(tracked) && length(B.room_centers))
		var/list/c = B.room_centers[1]
		var/turf/rt = locate(c[1], c[2], center.z)
		if(rt)
			var/mob/guard = expedition_spawn_guard(rt, S.faction, S.difficulty)
			if(guard)
				tracked += guard
	target = max(1, length(tracked))
	qdel(B)

/datum/expedition_objective/clear_structure/check()
	if(state == EXP_OBJ_COMPLETE)
		return state
	var/alive = count_alive()
	progress = target - alive
	if(alive <= 0)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/clear_structure/objective_text()
	return "Breach and clear the derelict structure"

// ===========================================================================
// FETCH & RETURN
// ===========================================================================

// Recover a precursor relic from a guarded vault and bring it to the pad.
/datum/expedition_objective/retrieve
	name = "Recover the artifact"

/datum/expedition_objective/retrieve/populate(datum/expedition_site/S)
	..()
	target = 1
	var/turf/T = S.random_floor()
	if(!T)
		return
	var/datum/expedition_poi/vault/V = new()
	var/obj/item/expedition_artifact/relic = V.stamp(T, S)
	if(relic)
		tracked += relic

/datum/expedition_objective/retrieve/check()
	if(count_returned(/obj/item/expedition_artifact) >= 1)
		progress = 1
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/retrieve/objective_text()
	return "Return the precursor relic to the launch pad"

// Recover a quota of scattered salvage.
/datum/expedition_objective/collect
	name = "Recover salvage"

/datum/expedition_objective/collect/populate(datum/expedition_site/S)
	..()
	target = 3 + S.difficulty + (S.size - 1)
	var/list/pool = list(
		/obj/item/salvage/ruin/pirate,
		/obj/item/salvage/ruin/russian,
		/obj/item/salvage/ruin/nanotrasen,
		/obj/item/salvage/loot/syndicate,
	)
	for(var/i in 1 to target)
		var/turf/T = S.random_floor()
		if(!T)
			continue
		var/salvage_path = pick(pool)
		new salvage_path(T)

/datum/expedition_objective/collect/check()
	progress = count_returned(/obj/item/salvage)
	if(progress >= target)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/collect/objective_text()
	return "Return [target] pieces of salvage to the launch pad"

// ===========================================================================
// RESCUE
// ===========================================================================

// Recover a stranded surveyor's stasis capsule.
/datum/expedition_objective/rescue
	name = "Rescue the surveyor"

/datum/expedition_objective/rescue/populate(datum/expedition_site/S)
	..()
	target = 1
	var/turf/T = S.random_floor()
	if(!T)
		return
	var/datum/expedition_poi/camp/C = new()
	var/obj/structure/expedition_survivor_pod/pod = C.stamp(T, S)
	if(pod)
		tracked += pod

/datum/expedition_objective/rescue/check()
	if(count_returned(/obj/structure/expedition_survivor_pod) >= 1)
		progress = 1
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/rescue/objective_text()
	return "Return the stasis capsule to the launch pad"

// ===========================================================================
// EXPLORATION
// ===========================================================================

// Record readings from a set of survey markers.
/datum/expedition_objective/survey
	name = "Survey the site"

/datum/expedition_objective/survey/populate(datum/expedition_site/S)
	..()
	target = 3 + S.difficulty + (S.size - 1)
	for(var/i in 1 to target)
		var/turf/T = S.random_floor()
		if(!T)
			continue
		tracked += new /obj/structure/expedition_survey_beacon(T)

/datum/expedition_objective/survey/check()
	var/done = 0
	for(var/obj/structure/expedition_survey_beacon/B in tracked)
		if(!QDELETED(B) && B.scanned)
			done++
	progress = done
	if(done >= target)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/survey/objective_text()
	return "Record readings from all [target] survey markers"

// Reach a waypoint planted at a far corner of the site.
/datum/expedition_objective/reach
	name = "Reach the waypoint"
	var/obj/structure/expedition_marker/marker

/datum/expedition_objective/reach/populate(datum/expedition_site/S)
	..()
	target = 1
	// Pick the farthest of a few candidates from the landing point.
	var/turf/best = null
	var/best_dist = -1
	for(var/i in 1 to 8)
		var/turf/T = S.random_floor()
		if(!T)
			continue
		var/d = S.landing ? get_dist(T, S.landing) : 0
		if(d > best_dist)
			best_dist = d
			best = T
	if(best)
		marker = new(best)
		tracked += marker

/datum/expedition_objective/reach/check()
	if(QDELETED(marker) || !site)
		return state
	for(var/mob/living/L in site.participants)
		if(QDELETED(L) || L.stat == DEAD)
			continue
		if(get_dist(L, marker) <= 2)
			progress = 1
			state = EXP_OBJ_COMPLETE
			break
	return state

/datum/expedition_objective/reach/objective_text()
	return "Reach the marked waypoint"

// ===========================================================================
// ENGINEERING
// ===========================================================================

// Commission a real derelict thermoelectric engine: a full TEG + circulators +
// burn chamber bay (engine_sme.dmm) is stamped onto the site. The crew must do
// the genuine engine setup — fuel the burn chamber, ignite, run the cooling
// loop — until the generator produces power. Completion polls the generator's
// effective_gen, so it only finishes if the engine is actually running.
/datum/expedition_objective/commission_engine
	name = "Commission the engine"
	/// Power output (watts) the generator must reach to count as commissioned.
	var/power_threshold = 50000
	/// Generators found in the stamped engine bay.
	var/list/generators

/datum/expedition_objective/commission_engine/populate(datum/expedition_site/S)
	..()
	target = 1
	generators = list()
	var/datum/map_template/expedition_engine/template = new()
	if(template.width <= 0 || template.height <= 0)
		return
	var/turf/anchor = S.landing || S.random_floor()
	if(!anchor)
		return
	var/cx = clamp(anchor.x - round(template.width / 2), 2, world.maxx - template.width - 1)
	var/cy = clamp(anchor.y - round(template.height / 2), 2, world.maxy - template.height - 1)
	var/turf/corner = locate(cx, cy, S.z_level)
	if(!corner || !template.load(corner))
		return
	for(var/turf/T in template.get_affected_turfs(corner))
		var/obj/machinery/power/generator/G = locate(/obj/machinery/power/generator) in T
		if(G)
			generators += G

/datum/expedition_objective/commission_engine/check()
	for(var/obj/machinery/power/generator/G in generators)
		if(!QDELETED(G) && G.effective_gen >= power_threshold)
			progress = 1
			state = EXP_OBJ_COMPLETE
			break
	return state

/datum/expedition_objective/commission_engine/objective_text()
	return "Commission the derelict engine — bring its generator online ([round(power_threshold / 1000)] kW)"

// ===========================================================================
// DEMOLITION
// ===========================================================================

// Rig and bring down an unstable structure (timed hand interaction).
/datum/expedition_objective/destroy
	name = "Demolish the target"
	var/obj/structure/expedition_demo_target/target_obj

/datum/expedition_objective/destroy/populate(datum/expedition_site/S)
	..()
	target = 1
	var/turf/T = S.random_floor()
	if(!T)
		return
	target_obj = new(T)
	tracked += target_obj
	for(var/turf/G in range(2, T))
		if(G == T || !expedition_is_walkable(G))
			continue
		if(prob(25))
			expedition_spawn_guard(G, S.faction, S.difficulty)

/datum/expedition_objective/destroy/check()
	if(QDELETED(target_obj))
		progress = 1
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/destroy/objective_text()
	return "Demolish the unstable structure"

// ===========================================================================
// DEFENCE
// ===========================================================================

// Hold the site against escalating waves for a duration. Pauses if the crew
// isn't present, so it can't tick down while nobody's aboard.
/datum/expedition_objective/survive
	name = "Hold position"
	var/hold_time = 90 SECONDS
	var/started_at = 0
	var/last_wave = 0
	var/wave_interval = 12 SECONDS

/datum/expedition_objective/survive/populate(datum/expedition_site/S)
	..()
	hold_time = (60 + S.difficulty * 30) SECONDS
	target = round(hold_time / 10)

/datum/expedition_objective/survive/check()
	if(!site || !players_present())
		return state
	if(!started_at)
		started_at = world.time
	if(world.time >= last_wave + wave_interval)
		spawn_wave()
		last_wave = world.time
	var/elapsed = world.time - started_at
	progress = round(elapsed / 10)
	if(elapsed >= hold_time)
		state = EXP_OBJ_COMPLETE
	return state

/datum/expedition_objective/survive/proc/players_present()
	for(var/mob/M in GLOB.player_list)
		if(M.z == site.z_level)
			return TRUE
	return FALSE

/datum/expedition_objective/survive/proc/spawn_wave()
	var/turf/anchor = null
	for(var/mob/living/L in site.participants)
		if(!QDELETED(L) && L.z == site.z_level)
			anchor = get_turf(L)
			break
	if(!anchor)
		anchor = site.landing
	if(!anchor)
		return
	var/list/spots = list()
	for(var/turf/T in range(6, anchor))
		if(expedition_is_walkable(T))
			spots += T
	if(!length(spots))
		return
	for(var/i in 1 to 2 + site.difficulty)
		expedition_spawn_guard(pick(spots), site.faction, site.difficulty)

/datum/expedition_objective/survive/objective_text()
	return "Hold the site for [round(hold_time / 10)] seconds"
