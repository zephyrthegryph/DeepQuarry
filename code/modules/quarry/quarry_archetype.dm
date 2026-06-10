// Floor archetypes.
//
// An archetype is the *kind* of floor a quarry layer is: what its
// objective is and what it takes to clear it (and thereby unlock the
// next depth). It is orthogonal to /datum/quarry_layer_config, which
// owns the biome/ore/mob *content*. A generated layer has both: a config
// (what it's made of) and an archetype (what you have to do there).
//
// A floor is cleared purely by completing its archetype's objective —
// there is no generic "stabilise some quota" gate. Each archetype owns
// an is_cleared(layer) predicate: a "lava" floor clears by cooling the
// vents, a "siege" floor by holding out a timer, a "hive" floor by
// destroying the cores, and so on. Feature rolls still place the layer's
// ore/mob/decoration *content*, but their goals are not the gate.
//
// Selection rides the rolling frontier (see quarry_controller.dm):
// each preroll picks an archetype via select_archetype(depth), so the
// stratum "drifting" under the bore changes archetype as well as content
// until a crew locks it in or descends.
//
// Archetype instances are shared singletons (one per subtype, built at
// SSquarry init like configs/events). They hold no per-layer state — all
// mutable state lives on the /datum/quarry_layer they operate on.

/datum/quarry_floor_archetype
	/// Human-readable name shown on the elevator card.
	var/name = "Unstable Stratum"
	/// One-line description / objective summary for the UI.
	var/desc = "An unstable stratum."
	/// Family tag for the wheel's anti-repeat: two floors of the same
	/// family won't normally generate back-to-back. Keep families coarse
	/// (a handful total) so spacing actually spreads departments out.
	var/family = "extraction"
	/// Depth-band weights, same "N" / "N-M" / "N+" syntax as configs.
	/// Empty/none means the archetype never rolls. See weight_at.
	var/list/depth_weights

/// Selection weight at a depth, or 0 if it doesn't apply. First matching
/// range key wins; mirrors /datum/quarry_layer_config/weight_at.
/datum/quarry_floor_archetype/proc/weight_at(depth)
	for(var/key in depth_weights)
		if(range_contains(key, depth))
			return depth_weights[key]
	return 0

/// Build and return this archetype's objective goals for layer L. Called
/// at generation and preroll. These goals ARE the floor's clear
/// condition. Default: none. Override per archetype.
/datum/quarry_floor_archetype/proc/build_goals(datum/quarry_layer/L)
	return list()

/// One-time environmental setup on a freshly *generated* layer: paint
/// hazards, place objective structures, spawn hive cores, etc. Runs once
/// in generate_layer after content placement, before L.loaded. NOT run on
/// restore (placed turfs/structures round-trip via the snapshot). Default
/// no-op.
/datum/quarry_floor_archetype/proc/on_layer_generated(datum/quarry_layer/L)
	return

/// Idempotent ambient setup, run on BOTH generate and restore (ambient
/// air / lighting / runtime state isn't snapshotted, so it must be
/// re-established each load). Default no-op.
/datum/quarry_floor_archetype/proc/apply_environment(datum/quarry_layer/L)
	return

/// Per-SSquarry-tick effect while the floor is occupied and not yet
/// cleared — the hazard's ongoing pressure (extra danger, ambient harm).
/// `seconds` is the subsystem wait in seconds. Default no-op.
/datum/quarry_floor_archetype/proc/ambient_tick(datum/quarry_layer/L, seconds)
	return

/// The clear predicate. TRUE when the floor's objective is complete and
/// the next depth should unlock. Every objective goal on the layer must
/// be individually satisfied — there is no partial / percentage gate.
/datum/quarry_floor_archetype/proc/is_cleared(datum/quarry_layer/L)
	if(!L)
		return FALSE
	if(!length(L.goals))
		return TRUE
	for(var/datum/quarry_goal/G as anything in L.goals)
		if(!G)
			continue
		if(!G.is_satisfied())
			return FALSE
	return TRUE


// === SSquarry: archetype roster + selection ==========================

/datum/controller/subsystem/quarry
	/// All concrete archetype instances, one per subtype. Built at init.
	var/list/archetypes = list()
	/// Family of the most recently *committed* (generated) frontier floor,
	/// used to space families across consecutive descents. Null until the
	/// first floor commits.
	var/last_committed_family = null

/datum/controller/subsystem/quarry/proc/init_archetypes()
	archetypes = list()
	for(var/atype in subtypesof(/datum/quarry_floor_archetype))
		archetypes += new atype
	if(!length(archetypes))
		log_game("SSquarry: no /datum/quarry_floor_archetype subtypes found; floors will have no objective.")

/// A safe fallback archetype (Freight Quota — doable at any depth), used
/// when selection fails or a snapshot names an unknown archetype type.
/datum/controller/subsystem/quarry/proc/default_archetype()
	for(var/datum/quarry_floor_archetype/A as anything in archetypes)
		if(istype(A, /datum/quarry_floor_archetype/resource))
			return A
	return null

/// Resolve an archetype typepath string back to its singleton instance.
/datum/controller/subsystem/quarry/proc/archetype_by_type(type_str)
	if(!istext(type_str))
		return null
	var/p = text2path(type_str)
	if(!ispath(p, /datum/quarry_floor_archetype))
		return null
	for(var/datum/quarry_floor_archetype/A as anything in archetypes)
		if(A.type == p)
			return A
	return null

/// Pick an archetype for a depth. Every fifth depth is a forced siege
/// gate (the "hold the shaft" milestone). Otherwise weighted-random
/// across eligible archetypes, with the previously-committed family
/// heavily downweighted so families don't repeat back-to-back. Returns
/// the default archetype if nothing else is eligible.
// `avoid_type` (optional): an archetype typepath to skip if any other
// option is eligible — used by the rolling frontier so a re-roll visibly
// changes the floor type instead of landing on the same one again.
/datum/controller/subsystem/quarry/proc/select_archetype(depth, avoid_type = null)
	if(depth > 0 && (depth % 5 == 0))
		for(var/datum/quarry_floor_archetype/A as anything in archetypes)
			if(istype(A, /datum/quarry_floor_archetype/siege))
				return A
	// Build the weighted pool, excluding the avoided type. If that leaves
	// nothing (it was the only option), retry without the exclusion.
	var/list/weighted = _weighted_archetypes(depth, avoid_type)
	if(!length(weighted))
		weighted = _weighted_archetypes(depth, null)
	if(!length(weighted))
		return default_archetype()
	return pickweight(weighted)

/datum/controller/subsystem/quarry/proc/_weighted_archetypes(depth, avoid_type)
	var/list/weighted = list()
	for(var/datum/quarry_floor_archetype/A as anything in archetypes)
		if(avoid_type && A.type == avoid_type)
			continue
		var/w = A.weight_at(depth)
		if(w <= 0)
			continue
		// Soft anti-repeat: downweight (don't exclude) the last family so
		// a depth where only one family is eligible can't dead-end.
		if(last_committed_family && A.family == last_committed_family)
			w = max(1, round(w * 0.15))
		weighted[A] = w
	return weighted


// === SSquarry: sustained-goal + ambient driver =======================

/// Per-SS-tick driver for time-based goals and archetype ambient hazard.
/// For each loaded, occupied layer: tick every goal's on_layer_tick, run
/// the archetype's ambient pressure, then recompute the unlock state once
/// (a survive-timer or power goal can complete purely on time). Empty
/// layers are skipped — siege timers and power output only count while a
/// crew is actually present.
/datum/controller/subsystem/quarry/proc/tick_layer_goals()
	var/seconds = wait / 10
	for(var/key in layers)
		var/datum/quarry_layer/L = layers[key]
		if(!L?.loaded || L.unloading)
			continue
		if(is_layer_empty(L.z))
			continue
		var/progressed = FALSE
		for(var/datum/quarry_goal/G as anything in L.goals)
			if(!G)
				continue
			var/before = G.progress
			G.on_layer_tick(L, seconds)
			if(G.progress != before)
				progressed = TRUE
		if(L.archetype)
			L.archetype.ambient_tick(L, seconds)
		if(progressed)
			recompute_unlocked_depth()


/// Credit an objective resolution (gas fissure sealed, hive core killed,
/// outpost lit, ...) to the matching neutralize goal on the layer that
/// owns z. Called by /obj/structure/quarry_objective when resolved.
/datum/controller/subsystem/quarry/proc/on_layer_objective(z, tag)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(!L || !length(L.goals))
		return
	for(var/datum/quarry_goal/G as anything in L.goals)
		G.on_objective_resolved(tag)
	recompute_unlocked_depth()


/// The depth of the currently-active freight order, or 0 if none. The
/// only reachable, uncleared Freight Quota floor is the one at the
/// frontier gate (deeper floors aren't reachable; shallower ones are
/// already cleared), so the active order is unlocked_depth iff its
/// archetype is the resource (Freight Quota) type — checked live if the
/// layer is loaded, else from its snapshot. Used by the surface freight
/// terminal to decide what a shipment counts toward.
/datum/controller/subsystem/quarry/proc/active_freight_depth()
	var/depth = unlocked_depth
	var/datum/quarry_layer/L = layers["[depth]"]
	var/datum/quarry_floor_archetype/arch = L?.loaded ? L.archetype : read_snapshot_archetype(depth)
	return istype(arch, /datum/quarry_floor_archetype/resource) ? depth : 0

/// Progress/target of a depth's freight order as list("progress", "target"),
/// or null if it has no delivery goal. Reads the live layer if loaded,
/// else the snapshot. For the terminal's status display.
/datum/controller/subsystem/quarry/proc/freight_order_progress(depth)
	var/datum/quarry_layer/L = layers["[depth]"]
	if(L?.loaded)
		for(var/datum/quarry_goal/deliver_resource/G in L.goals)
			return list("progress" = G.progress, "target" = G.target)
		return null
	var/list/goals = read_snapshot_goals(depth)
	if(!islist(goals))
		return null
	for(var/list/g in goals)
		if(islist(g) && g["type"] == "/datum/quarry_goal/deliver_resource")
			return list("progress" = g["progress"] || 0, "target" = g["target"] || 0)
	return null

/// Credit a freight shipment of `count` ore units to the layer at `depth`.
/// Called by the surface freight terminal when Cargo ships ore off. If the
/// layer is loaded, credits its live delivery goal and re-checks the
/// unlock normally; if it has since unloaded, patches the persisted goal
/// progress in its snapshot and advances the frontier directly when the
/// order completes the gate.
/datum/controller/subsystem/quarry/proc/on_layer_delivery(depth, count)
	if(!isnum(count) || count <= 0)
		return
	var/datum/quarry_layer/L = layers["[depth]"]
	if(L?.loaded)
		for(var/datum/quarry_goal/G as anything in L.goals)
			G.on_delivery(count)
		recompute_unlocked_depth()
		return
	credit_snapshot_delivery(depth, count)

/// Credit a delivery to an unloaded layer's snapshot. Bumps the persisted
/// deliver_resource progress; if that satisfies every goal in the snapshot
/// and this is the frontier gate depth, advances unlocked_depth so the
/// next descent opens even though the floor itself isn't loaded.
/datum/controller/subsystem/quarry/proc/credit_snapshot_delivery(depth, count)
	var/list/doc = read_snapshot_doc(depth)
	if(!islist(doc) || !islist(doc["goals"]))
		return
	var/changed = FALSE
	for(var/list/g in doc["goals"])
		if(!islist(g) || g["type"] != "/datum/quarry_goal/deliver_resource")
			continue
		var/target = g["target"] || 0
		g["progress"] = min(target, (g["progress"] || 0) + count)
		changed = TRUE
	if(!changed)
		return
	write_snapshot_doc(depth, doc)
	if(depth != unlocked_depth)
		return
	// Advance the frontier only if every goal in the snapshot is satisfied.
	for(var/list/g in doc["goals"])
		if(islist(g) && (g["progress"] || 0) < (g["target"] || 0))
			return
	unlocked_depth++
	if(!has_snapshot(unlocked_depth))
		preroll_layer(unlocked_depth)
	begin_frontier_roll()
