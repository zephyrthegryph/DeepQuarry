// Quarry layer persistence.
//
// When the last player leaves a quarry layer, instead of hard-deleting the
// z and rebuilding from procgen on next entry, we serialize the z to a JSON
// file under data/quarry_snapshots/ keyed by depth. The next time a player
// descends to that depth we LoadMaps the snapshot back, re-cache elevator
// references, and spawn fresh mobs from the layer's config.
//
// Why depth-keyed and not seed-keyed: this fork's quarry treats "depth N"
// as a single semantic location for a round — every player who descends
// to N lands on the same z. Two snapshots at the same depth would never
// both be wanted, so depth is a stable enough key.
//
// Serialization model: piggybacks on the codebase's existing per-atom
// /datum/proc/serialize framework (code/modules/persistence/serialize.dm).
// Each saved layer is a JSON document with one entry per (x,y) tile that
// differs from the freshly-generated baseline:
//   { "tiles": [
//       { "x": 12, "y": 34,
//         "turf": { "type": "...", <vars_to_save fields> },
//         "contents": [ { "type": "...", ... }, ... ] },
//       ...
//   ] }
// We don't snapshot the full 65536-tile grid — only tiles that hold
// movables (dropped loot, decorations, scaffolds) and tiles whose turf
// type or saved vars differ from a freshly-generated layer. The mineable-
// wall tiles that the player turned into floor tiles count via the turf-
// type diff. The result is small (kilobytes for a typical played-out
// layer, not megabytes).
//
// What survives a snapshot/restore round-trip:
//   - Turf type changes (mined-out walls become floors, ChangeTurf'd
//     elevator floor / walls / doors are kept).
//   - Non-mob movable atoms (dropped loot, decorations, scaffolds, the
//     elevator panels). Per-atom vars are limited to
//     /atom/vars_to_save() unless the type overrides — for the quarry
//     this is enough since the meaningful content is items at locations,
//     not items in unusual states.
//
// What does NOT survive (re-spawned from the layer config on restore):
//   - Hostile mobs. Any /mob/living on the z is qdel'd before snapshot
//     so the saved doc only contains static contents. After restore we
//     walk the layer config's mob_table and spawn fresh mobs on random
//     floor tiles, identical to the first-time generation pass. Mobs
//     carry too much per-instance state (AI controllers, signal
//     subscriptions, active targets) to round-trip cleanly via
//     vars_to_save; cheaper to respawn than to chase the bugs.

#define QUARRY_SNAPSHOT_DIR "data/quarry_snapshots/"

// Atoms we don't include in the snapshot, even when present on the tile.
// Mobs are stripped pre-save (covered separately); these are atoms
// that have refs the snapshot can't carry, or that get re-created on
// restore from a different code path. The elevator panels / doors /
// lights ARE serialized: restore no longer re-carves them, and we
// want the snapshot's copy to be authoritative.
/proc/_quarry_skip_in_snapshot(atom/movable/AM)
	if(ismob(AM))
		return TRUE
	if(istype(AM, /obj/effect/landmark))
		return TRUE
	// Lighting overlays are runtime-only.
	if(istype(AM, /atom/movable/lighting_overlay))
		return TRUE
	return FALSE


// Snapshot file path for a given depth.
/proc/_quarry_snapshot_path(depth)
	return "[QUARRY_SNAPSHOT_DIR][depth].json"


// Strip mobs from the z, then walk it tile-by-tile and serialize the
// non-default ones to a JSON file. Returns TRUE on success.
/datum/controller/subsystem/quarry/proc/snapshot_layer(depth, z)
	if(!isnum(depth) || !isnum(z) || z < 1)
		return FALSE
	// Strip mobs first. Last-player-left has already cleared minds; any
	// mob found here is an NPC, qdel it. Skip live-mind mobs entirely
	// so a player teleporting onto the z mid-strip doesn't get qdel'd.
	// Yields only above 95% tick usage in batches of 4 rows.
	var/strip_batch = 0
	for(var/y in 1 to QUARRY_LAYER_SIZE)
		for(var/x in 1 to QUARRY_LAYER_SIZE)
			var/turf/T = locate(x, y, z)
			if(!isturf(T))
				continue
			for(var/mob/M in T)
				if(istype(M, /mob/observer))
					continue
				if(istype(M, /mob/living))
					var/mob/living/LM = M
					if(LM.mind)
						continue
				qdel(M)
		strip_batch++
		if(strip_batch >= 4)
			strip_batch = 0
			CHECK_TICK_HIGH_PRIORITY

	// Make sure the dir exists. text2file with empty payload to a
	// `.keep` sentinel is the idiomatic mkdir-equivalent in DM.
	if(!fexists(QUARRY_SNAPSHOT_DIR))
		text2file("", "[QUARRY_SNAPSHOT_DIR].keep")

	// Walk every tile. CHECK_TICK_HIGH_PRIORITY every few columns —
	// yields only above 95% tick usage so the snapshot gets most of
	// each MC tick instead of giving it up at the default 80% threshold.
	// Without this, a busy server stretched the snapshot pass to
	// minutes by burning a full MC cycle on every yield.
	var/list/tiles = list()
	var/col_batch = 0
	for(var/x in 1 to QUARRY_LAYER_SIZE)
		for(var/y in 1 to QUARRY_LAYER_SIZE)
			var/turf/T = locate(x, y, z)
			if(!isturf(T))
				continue
			var/list/tile_doc = _quarry_serialize_tile(T)
			if(tile_doc)
				tiles += list(tile_doc)
		col_batch++
		if(col_batch >= 4)
			col_batch = 0
			CHECK_TICK_HIGH_PRIORITY

	// Save the feature roll + goal progress so restore rebuilds the
	// same goals (with the same in-flight progress) rather than
	// re-rolling. Without this a player who descended once, made
	// progress, came back to the surface, then re-descended would
	// see a different set of goals every time.
	var/list/feature_types_out = list()
	var/list/goals_out = list()
	var/datum/quarry_layer/L = layers["[depth]"]
	if(L)
		for(var/feat_type in L.feature_types)
			feature_types_out += "[feat_type]"
		for(var/datum/quarry_goal/G as anything in L.goals)
			if(!G)
				continue
			var/list/entry = list(
				"type" = "[G.type]",
				"name" = G.name,
				"description" = G.description,
				"target" = G.target,
				"progress" = G.progress,
			)
			var/list/extra = G.serialize_extra()
			if(islist(extra))
				for(var/k in extra)
					entry[k] = extra[k]
			goals_out += list(entry)

	var/list/doc = list(
		"version" = 2,
		"depth" = depth,
		"tiles" = tiles,
		"feature_types" = feature_types_out,
		"goals" = goals_out,
		"danger" = L?.danger || 0,
		"last_danger_wave" = L?.last_danger_wave || 0,
		"archetype" = (L?.archetype ? "[L.archetype.type]" : null),
	)
	var/path = _quarry_snapshot_path(depth)
	if(fexists(path))
		fdel(path)
	text2file(json_encode(doc), path)
	if(!fexists(path))
		log_game("SSquarry: snapshot for depth [depth] failed to write to [path]")
		return FALSE
	log_game("SSquarry: snapshot for depth [depth]: [length(tiles)] tiles, [length(feature_types_out)] features, [length(goals_out)] goals written to [path]")
	return TRUE


// Serialize one tile if it has anything worth saving — either a turf
// type that isn't the layer's baseline (a /turf/simulated/mineral/cave/quarry
// wall is the default; a non-default turf such as /turf/simulated/floor
// from a mined wall, or an elevator wall/floor, IS worth saving), or
// movables on it. Returns null for "nothing to save here" so the caller
// can skip the tile entirely.
/proc/_quarry_serialize_tile(turf/T)
	var/list/movables = list()
	for(var/atom/movable/AM in T)
		if(_quarry_skip_in_snapshot(AM))
			continue
		movables += list(AM.serialize())

	var/turf_type_path = "[T.type]"
	// Baseline: the freshly-generated quarry layer leaves walls as
	// /turf/simulated/mineral/cave/quarry. Anything else is a player
	// or generation modification we want to preserve.
	var/is_baseline = (turf_type_path == "/turf/simulated/mineral/cave/quarry")
	if(is_baseline && !length(movables))
		return null

	var/list/tile = list("x" = T.x, "y" = T.y)
	if(!is_baseline)
		tile["turf"] = T.serialize()
	if(length(movables))
		tile["contents"] = movables
	return tile


// Returns TRUE if a snapshot exists on disk for this depth.
/datum/controller/subsystem/quarry/proc/has_snapshot(depth)
	return fexists(_quarry_snapshot_path(depth))


// Overwrite a depth's snapshot file with an (already json-shaped) doc.
// Used to patch persisted goal progress (e.g. crediting a freight
// delivery to a layer that has since unloaded). No-op if no snapshot dir.
/datum/controller/subsystem/quarry/proc/write_snapshot_doc(depth, list/doc)
	if(!islist(doc))
		return FALSE
	var/path = _quarry_snapshot_path(depth)
	if(fexists(path))
		fdel(path)
	text2file(json_encode(doc), path)
	return fexists(path)


// Read and json_decode the snapshot document for a depth. Returns
// null if the file is missing or unreadable. Caller is responsible
// for inspecting the shape it wants — read_snapshot_goals/etc are
// thin wrappers around this.
/datum/controller/subsystem/quarry/proc/read_snapshot_doc(depth)
	var/path = _quarry_snapshot_path(depth)
	if(!fexists(path))
		return null
	var/list/doc
	try
		doc = json_decode(file2text(path))
	catch
		return null
	return doc


// Read just the goals list out of a snapshot without restoring the
// layer. Used by the elevator UI so depths that have been visited and
// unloaded still display their goal progress (the layer record is
// gone from .layers, but the JSON on disk has everything we need).
// Returns null if no snapshot exists or it's malformed.
/datum/controller/subsystem/quarry/proc/read_snapshot_goals(depth)
	var/path = _quarry_snapshot_path(depth)
	if(!fexists(path))
		return null
	var/list/doc
	try
		doc = json_decode(file2text(path))
	catch
		return null
	if(!islist(doc) || !islist(doc["goals"]))
		return null
	return doc["goals"]


// Returns the snapshot's feature_types list (as typepaths) if it has
// one, else null. Used by ensure_layer to honor a pre-rolled feature
// set when a partial snapshot exists — see preroll_layer.
/datum/controller/subsystem/quarry/proc/read_snapshot_feature_types(depth)
	var/path = _quarry_snapshot_path(depth)
	if(!fexists(path))
		return null
	var/list/doc
	try
		doc = json_decode(file2text(path))
	catch
		return null
	if(!islist(doc) || !islist(doc["feature_types"]))
		return null
	var/list/out = list()
	for(var/s in doc["feature_types"])
		var/p = text2path(s)
		if(ispath(p, /datum/quarry_feature))
			out += p
	return out


// Resolve the archetype named in a snapshot to its singleton instance,
// or null if the snapshot predates archetypes / names an unknown type.
/datum/controller/subsystem/quarry/proc/read_snapshot_archetype(depth)
	var/list/doc = read_snapshot_doc(depth)
	if(!islist(doc))
		return null
	return archetype_by_type(doc["archetype"])


// TRUE if a snapshot exists but contains no tile data — i.e. it was
// written by preroll_layer to publish goal data to the UI before the
// layer is actually generated.
/datum/controller/subsystem/quarry/proc/is_partial_snapshot(depth)
	var/path = _quarry_snapshot_path(depth)
	if(!fexists(path))
		return FALSE
	var/list/doc
	try
		doc = json_decode(file2text(path))
	catch
		return FALSE
	if(!islist(doc))
		return FALSE
	var/list/tiles = doc["tiles"]
	return !islist(tiles) || !length(tiles)


// Roll a layer's features + goals up front and write a partial
// snapshot containing just feature_types and the goal previews. No
// world tiles are allocated — the actual /turf/simulated/floor cave
// is built later, when ensure_layer fires on dispatch.
//
// The partial snapshot lets the elevator UI display real goal names
// and progress (always 0/N at this stage) for the deepest unlocked
// depth before the player has ever visited it. When the player does
// dispatch, ensure_layer detects the partial snapshot, reads the
// feature_types, deletes the file, and calls generate_layer with the
// preserved feature set so the goals shown in the UI match what the
// player actually finds underground.
//
// Idempotent: re-rolls and overwrites if called twice.
// `avoid_archetype` (optional): a typepath the archetype roll should skip
// if possible — passed by the rolling frontier so a re-roll changes the
// floor type rather than repeating the current candidate.
/datum/controller/subsystem/quarry/proc/preroll_layer(depth, avoid_archetype = null)
	var/datum/quarry_layer_config/cfg = select_config(depth)
	if(!cfg)
		return FALSE
	// Build features + goals on a throwaway layer record so
	// build_goals has something to attach to. The archetype is rolled
	// here too — re-rolling preroll is exactly how the frontier "drifts"
	// across archetypes, not just feature sets.
	var/datum/quarry_layer/preview = new(depth)
	var/datum/quarry_floor_archetype/arch = select_archetype(depth, avoid_archetype)
	preview.archetype = arch
	preview.feature_types = _quarry_roll_feature_types(cfg)
	var/list/aggregated = _quarry_aggregate_features(preview.feature_types, preview)
	// The preview goals are the archetype's objective; discard feature goals.
	for(var/datum/quarry_goal/FG as anything in aggregated["goals"])
		qdel(FG)
	preview.goals = arch ? arch.build_goals(preview) : list()
	var/list/feature_types_out = list()
	for(var/feat_type in preview.feature_types)
		feature_types_out += "[feat_type]"
	var/list/goals_out = list()
	for(var/datum/quarry_goal/G as anything in preview.goals)
		if(!G)
			continue
		goals_out += list(list(
			"type" = "[G.type]",
			"name" = G.name,
			"description" = G.description,
			"target" = G.target,
			"progress" = 0,
		))
	var/list/doc = list(
		"version" = 2,
		"depth" = depth,
		"tiles" = list(),  // empty -> partial; ensure_layer routes to generate_layer
		"feature_types" = feature_types_out,
		"goals" = goals_out,
		"archetype" = (arch ? "[arch.type]" : null),
	)
	if(!fexists(QUARRY_SNAPSHOT_DIR))
		text2file("", "[QUARRY_SNAPSHOT_DIR].keep")
	var/path = _quarry_snapshot_path(depth)
	if(fexists(path))
		fdel(path)
	text2file(json_encode(doc), path)
	qdel(preview)
	return TRUE


// Rebuild a layer from snapshot without re-running procgen.
//
// Allocates a fresh z via the substrate template (every tile starts as
// the baseline /turf/simulated/mineral/cave/quarry wall), applies the
// snapshot's tile diffs to recreate every non-baseline turf and its
// contents — including the elevator footprint, doors, panels, and any
// player-modified tiles — then re-spawns hostile mobs from the layer
// config. Mobs are excluded from the snapshot intentionally (too much
// per-instance state to round-trip), so a fresh spawn pass keeps the
// layer dangerous on return visits.
//
// Returns the new /datum/quarry_layer on success, null on failure
// (caller can fall back to a clean generate_layer).
/datum/controller/subsystem/quarry/proc/restore_layer(depth)
	var/path = _quarry_snapshot_path(depth)
	if(!fexists(path))
		return null

	var/datum/quarry_layer_config/cfg = select_config(depth)
	if(!cfg)
		log_game("SSquarry: restore_layer: no config for depth [depth]")
		return null

	var/list/doc
	try
		doc = json_decode(file2text(path))
	catch
		log_game("SSquarry: snapshot for depth [depth] is unreadable")
		return null
	if(!islist(doc) || !islist(doc["tiles"]))
		log_game("SSquarry: snapshot for depth [depth] is malformed")
		return null

	var/_rl0 = world.timeofday
	var/datum/map_template/quarry_layer/template = new
	// Use the z load_new_z actually allocated (never re-read world.maxz
	// after it — that's racy across the load's yields).
	var/new_z = template.load_new_z()
	if(!new_z)
		log_game("SSquarry: restore_layer: load_new_z failed for depth [depth]")
		return null
	// Refresh atmos vertical-adjacency for the restored layer's z-level (multi-z
	// atmos — see SSair.build_multiz_atmos_levels).
	SSair.build_multiz_atmos_levels()
	var/_rl1 = world.timeofday

	// Apply snapshot tile diffs. Each entry sets the turf type (if
	// non-baseline) and instantiates each saved movable on the tile.
	//
	// Input validation: snapshot JSON files live on disk under
	// data/quarry_snapshots/ and are reloaded across rounds. Without
	// bounds + type-path validation, anyone with write access to that
	// directory could craft a snapshot that instantiates arbitrary turf
	// or object types when the layer reloads. Guard rails:
	//   * x/y must be in-bounds integers (1..QUARRY_LAYER_SIZE)
	//   * turf_path must be a /turf/simulated subtype (no /turf/admin or
	//     non-turf paths)
	//   * atom_data["type"] must resolve to a /atom/movable subtype
	var/applied_turfs = 0
	var/applied_movables = 0
	var/rejected_tiles = 0
	var/rejected_movables = 0
	for(var/list/tile in doc["tiles"])
		if(!islist(tile))
			rejected_tiles++
			continue
		var/raw_x = tile["x"]
		var/raw_y = tile["y"]
		if(!isnum(raw_x) || !isnum(raw_y))
			rejected_tiles++
			continue
		var/x = round(raw_x)
		var/y = round(raw_y)
		if(x < 1 || x > QUARRY_LAYER_SIZE || y < 1 || y > QUARRY_LAYER_SIZE)
			rejected_tiles++
			continue
		var/turf/T = locate(x, y, new_z)
		if(!isturf(T))
			continue
		var/list/turf_data = tile["turf"]
		if(islist(turf_data))
			var/raw_turf_type = turf_data["type"]
			var/turf_path = istext(raw_turf_type) ? text2path(raw_turf_type) : null
			if(turf_path && ispath(turf_path, /turf/simulated) && turf_path != T.type)
				T = T.ChangeTurf(turf_path)
			if(isturf(T))
				T.deserialize(turf_data)
				applied_turfs++
		var/list/contents_data = tile["contents"]
		if(islist(contents_data))
			for(var/list/atom_data in contents_data)
				if(!islist(atom_data))
					rejected_movables++
					continue
				var/raw_atom_type = atom_data["type"]
				var/atom_path = istext(raw_atom_type) ? text2path(raw_atom_type) : null
				if(!ispath(atom_path, /atom/movable))
					rejected_movables++
					continue
				try
					list_to_object(atom_data, T)
					applied_movables++
				catch(var/exception/E)
					log_game("SSquarry: restore: list_to_object failed for [atom_data["type"]] at ([T.x],[T.y]): [E.name]")
					continue
	if(rejected_tiles || rejected_movables)
		log_game("SSquarry: restore: rejected [rejected_tiles] tile(s) + [rejected_movables] movable(s) for depth [depth] due to bounds/type validation")
	var/_rl2 = world.timeofday

	var/list/bay_tiles = _quarry_recache_elevator_from_restore(new_z, depth)
	if(!length(bay_tiles))
		log_game("SSquarry: restore_layer: could not locate elevator bay on restored z [new_z] for depth [depth]")
		return null
	var/_rl3 = world.timeofday

	// Build the layer record before aggregating features, so feature
	// build_goals can reference it.
	var/datum/quarry_layer/L = new(depth)
	L.z = new_z
	L.config = cfg
	// Restore the floor archetype (null for pre-archetype / unknown).
	L.archetype = archetype_by_type(doc["archetype"])

	// Restore the feature set. v2+ snapshots embed it; older v1
	// snapshots lose feature identity and have to re-roll. Re-rolling
	// changes the goal list but keeps the layer playable.
	var/list/saved_feature_strings = doc["feature_types"]
	if(islist(saved_feature_strings) && length(saved_feature_strings))
		for(var/s in saved_feature_strings)
			var/feat_path = text2path(s)
			if(ispath(feat_path, /datum/quarry_feature))
				L.feature_types += feat_path
	if(!length(L.feature_types))
		L.feature_types = _quarry_roll_feature_types(cfg)

	var/list/aggregated = _quarry_aggregate_features(L.feature_types, L)
	var/list/mob_table = aggregated["mob_table"]
	var/extra_mob_spawns = aggregated["extra_mob_spawns"]
	// The floor's goals are its archetype's objective; discard feature goals.
	for(var/datum/quarry_goal/FG as anything in aggregated["goals"])
		qdel(FG)
	L.goals = L.archetype ? L.archetype.build_goals(L) : list()

	// Restore persisted danger state (defaults to 0 for partial
	// snapshots written by preroll_layer).
	L.danger = doc["danger"] || 0
	L.last_danger_wave = doc["last_danger_wave"] || 0

	// Apply persisted goal progress + per-subtype extras. Match by goal
	// type + name (build_goals only emits one goal per feature so this
	// is unambiguous within a layer).
	var/list/saved_goals = doc["goals"]
	if(islist(saved_goals))
		for(var/list/saved in saved_goals)
			if(!islist(saved))
				continue
			var/saved_type = saved["type"]
			var/saved_name = saved["name"]
			var/saved_progress = saved["progress"]
			for(var/datum/quarry_goal/G as anything in L.goals)
				if("[G.type]" == saved_type && G.name == saved_name)
					G.progress = saved_progress
					G.deserialize_extra(saved)
					break

	var/total_mob_count = cfg.mob_count + extra_mob_spawns
	var/list/effective_mob_table = length(mob_table) ? mob_table : cfg.default_mob_table
	if(total_mob_count > 0 && length(effective_mob_table))
		var/list/floor_candidates = list()
		for(var/turf/simulated/floor/F in block(locate(1, 1, new_z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, new_z)))
			if(F in bay_tiles)
				continue
			if(length(F.contents))
				continue
			// Player-built safe rooms (with powered APC) are spawn-safe.
			if(_quarry_tile_is_safe(F))
				continue
			floor_candidates += F
		var/spawned = 0
		while(spawned < total_mob_count && length(floor_candidates))
			var/turf/F = pick(floor_candidates)
			floor_candidates -= F
			var/mob_type = pickweight(effective_mob_table)
			if(mob_type)
				new mob_type(F)
			spawned++
	var/_rl4 = world.timeofday

	L.loaded = TRUE
	// Re-apply idempotent ambient setup (air/light/runtime state isn't
	// snapshotted). Placed objective structures round-trip via the tile
	// diffs, so on_layer_generated is deliberately NOT re-run here.
	if(L.archetype)
		L.archetype.apply_environment(L)

	log_game("BENCH: restore_layer phases (depth [depth]) load_new_z=[(_rl1-_rl0)/10]s overlay=[(_rl2-_rl1)/10]s recache=[(_rl3-_rl2)/10]s mobs=[(_rl4-_rl3)/10]s [applied_turfs] turfs, [applied_movables] atoms features=[length(L.feature_types)] goals=[length(L.goals)]")
	return L


// Walk a restored z to find the three lift airlock doors and the bay
// tiles south of them. The carve geometry guarantees the bay is the
// 3x3 floor block one tile south of the centre door, so we can
// reconstruct it by locating the doors. Wires the bay + doors into
// SSquarry.elevator so dispatch/summon work.
/datum/controller/subsystem/quarry/proc/_quarry_recache_elevator_from_restore(z, depth)
	if(!elevator)
		return list()
	// Count what's actually on the z so we can tell whether the
	// snapshot's doors landed at all (vs landed on a wrong z, vs
	// were silently rejected by list_to_object).
	var/total_doors_world = 0
	var/total_doors_this_z = 0
	for(var/obj/machinery/door/airlock/lift/AD in world)
		total_doors_world++
		if(AD.z == z)
			total_doors_this_z++
	var/list/lift_doors = list()
	// Walk the z's turfs then peek into each turf's contents. The
	// idiomatic SS13 pattern; a single-line `for(var/obj/X in block(...))`
	// looks similar but silently iterates the turf list and finds zero
	// objs because the block() list contents are turfs, not objs.
	for(var/turf/T as anything in block(locate(1, 1, z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, z)))
		for(var/obj/machinery/door/airlock/lift/D in T)
			lift_doors += D
	if(length(lift_doors) < 3)
		// Diagnostic: where ARE the doors on this z, if any?
		for(var/obj/machinery/door/airlock/lift/AD in world)
			if(AD.z == z)
				log_game("SSquarry: recache: lift door on z [z] at ([AD.x], [AD.y]), loc=[AD.loc], type=[AD.type]")
		log_game("SSquarry: recache: only [length(lift_doors)] lift doors in z [z] block (this_z=[total_doors_this_z], world=[total_doors_world]), need 3")
		return list()
	// Pick the centre door (the middle x of the three colinear doors).
	sortTim(lift_doors, GLOBAL_PROC_REF(cmp_atom_x_asc))
	var/obj/machinery/door/airlock/lift/center_door = lift_doors[2]
	if(!center_door)
		return list()
	var/turf/door_tile = get_turf(center_door)
	if(!isturf(door_tile))
		return list()
	var/cx = door_tile.x
	var/cy = door_tile.y - 2  // bay centre is 2 tiles south of the centre door
	var/list/bay = list()
	for(var/dy in -1 to 1)
		for(var/dx in -1 to 1)
			var/turf/T = locate(cx + dx, cy + dy, z)
			if(isturf(T))
				bay += T
	if(length(bay) != 9)
		return list()
	elevator.layer_bays["[depth]"] = bay
	elevator.doors["[depth]"] = lift_doors
	return bay


/proc/cmp_atom_x_asc(atom/a, atom/b)
	return a.x - b.x


// Clear all on-disk snapshots. Called at world init so a fresh round
// starts with no leftover snapshot files.
/datum/controller/subsystem/quarry/proc/clear_all_snapshots()
	if(!fexists(QUARRY_SNAPSHOT_DIR))
		return
	for(var/fname in flist(QUARRY_SNAPSHOT_DIR))
		var/full = "[QUARRY_SNAPSHOT_DIR][fname]"
		if(fname == ".keep")
			continue
		fdel(full)


#undef QUARRY_SNAPSHOT_DIR
