// Subsystem that owns the dynamic deep-quarry layers.
//
// Lifecycle of a layer:
//   ensure_layer(N) -> allocates a fresh Z, loads the empty stone template
//   onto it, runs the cave generator, carves the elevator bay, places
//   decorations and mobs, returns the /datum/quarry_layer record.
//   unload_layer(N) -> snapshots the layer to disk and turfs it to space.
//
// The elevator is the sole way in and out — no ladders or escape ropes.
//
// "Same depth, same layer" is emergent: ensure_layer is idempotent on
// loaded layers, so concurrent or staggered descents to depth N all land
// on whatever layer is currently loaded at depth N. If none exists, the
// caller generates a fresh one.
//
// Procedural layers are 256x256, matching the surface station's size. The
// substrate template (deep_quarry_layer.dmm) covers the full Z with a
// 1-tile bedrock perimeter and a mineable cave interior. The cave gen
// operates on the full 256x256 — generation takes 30-60s per layer with
// per-cell yields. Layers are generated on demand when the elevator is
// sent to a depth that hasn't been generated yet; the elevator's
// travel_to blocks on ensure_layer with doors closed.
//
// QUARRY_LAYER_SIZE is defined in quarry_defines.dm so the unit tests
// can reference it — that file is hoisted before _unit_tests.dm in the
// DME.

SUBSYSTEM_DEF(quarry)
	name = "Deep Quarry"
	wait = 30 SECONDS
	flags = SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	// Indexed by "[depth]" string key.
	var/list/layers = list()

	// Per-depth re-entrancy guard: set to depth while ensure_layer is generating.
	var/list/generating = list()

	// All concrete /datum/quarry_layer_config instances. Built once at
	// Initialize from subtypesof(); select_config picks across them.
	var/list/configs = list()

	// The freight elevator. One per round, owned by SSquarry. Created at
	// Initialize before the surface map's landmarks scan for it.
	var/datum/quarry_elevator/elevator

	// The deepest depth a player has ever set foot on this round. Monotonic.
	// Bumped by the surface elevator panel when the player picks
	// "descend further". Starts at 0 so the surface panel's first descent
	// goes to depth 1, generated on demand.
	var/deepest_visited = 0
	// The deepest depth the elevator may travel to. Bumped when the
	// previous depth's stabilization goal hits its unlock threshold.
	// Starts at 1: depth 1 is unconditionally reachable so a fresh
	// round always has a first destination.
	var/unlocked_depth = 1

/datum/controller/subsystem/quarry/Initialize()
	// Wipe any leftover snapshots from a prior round before anything
	// else touches the layer system. Snapshots are per-round artefacts
	// so a restart should always start clean.
	clear_all_snapshots()

	// Create the elevator before scanning the map. Landmarks on the entrance
	// map register their bays/doors with the elevator during their own
	// Initialize, and that may run before or after SSquarry depending on
	// init order — both directions are covered by us doing a fallback scan
	// at the end of this proc.
	elevator = new

	// Fallback scan for the elevator anchor: if the landmark's Initialize ran
	// before SSquarry's, our elevator.surface_bay would have been written
	// against a nil elevator. Re-do it here so it lands correctly.
	if(!length(elevator.surface_bay))
		for(var/obj/effect/landmark/quarry_elevator_anchor/A in world)
			var/turf/center = get_turf(A)
			if(!isturf(center))
				continue
			var/list/bay = list()
			for(var/dy in -1 to 1)
				for(var/dx in -1 to 1)
					var/turf/T = locate(center.x + dx, center.y + dy, center.z)
					if(isturf(T))
						bay += T
			elevator.surface_bay = bay
			var/list/surface_doors = list()
			for(var/turf/T as anything in bay)
				for(var/dir in GLOB.cardinal)
					var/turf/neighbor = get_step(T, dir)
					for(var/obj/machinery/door/airlock/lift/D in neighbor)
						if(!(D in surface_doors))
							surface_doors += D
			elevator.doors["0"] = surface_doors
			break
	if(!length(elevator.surface_bay))
		log_game("SSquarry: no elevator surface anchor found; elevator will be inert.")
	else
		// Car starts on the surface. Open the doors so players can board.
		elevator.open_doors_at(0)

	// Instantiate all layer configs.
	for(var/cfg_type in subtypesof(/datum/quarry_layer_config))
		configs += new cfg_type
	if(!length(configs))
		log_game("SSquarry: no /datum/quarry_layer_config subtypes found; layers will fail to generate.")

	// Instantiate all runtime cave events.
	init_events()

	// Carve cave network into the surface map around the hand-authored
	// rooms. The .dmm fills the area outside the room with mineable cave
	// walls; this gen punches walkable passages through them and tags
	// some walls as ore-bearing. The room/elevator structure (stonebricks,
	// concrete, elevator walls/floor) is non-mineral so it's left alone.
	generate_surface()

	// No pregen of layer 1 — the elevator's travel_to handles generation
	// on demand. The first "descend further" press from the surface
	// panel takes ~15s while the player waits inside the bay; the doors
	// stay closed until the layer is ready.
	//
	// We DO pre-roll the depth-1 feature set + goals so the elevator UI
	// shows the real quest list before anyone descends. The full world
	// gen still happens on first dispatch; the preroll just publishes
	// a goals-only snapshot for UI consumption.
	if(!has_snapshot(1))
		preroll_layer(1)

	// One-shot memory profile dump. Wait a few seconds for the world to
	// settle (atoms, atmos, lighting all finished initializing), then
	// count types and log to game.log.
	spawn(50)	// 5 seconds
		quarry_profile_atoms()

	return SS_INIT_SUCCESS

// Run the surface-biome cave generator on Z=1. Selected config has
// depth_weights = {"0": 100} so it picks deterministically.
/datum/controller/subsystem/quarry/proc/generate_surface()
	var/datum/quarry_layer_config/cfg = select_config(0)
	if(!cfg)
		log_game("SSquarry: no surface config; skipping surface gen")
		return

	// The surface .dmm's "b" tile is already /turf/simulated/mineral/cave/quarry,
	// matching the default config wall_turf. No ChangeTurf pass needed.
	new /datum/random_map/automata/cave_system/quarry(cfg, 1, 1, 1, world.maxx, world.maxy)

	// Roll features for the surface biome and place each as veins or
	// pools. Pass a throwaway layer so build_goals can be called (the
	// goals themselves are discarded — surface doesn't participate in
	// stabilization).
	var/datum/quarry_layer/throwaway = new(0)
	var/list/feature_types = _quarry_roll_feature_types(cfg)
	var/list/aggregated = _quarry_aggregate_features(feature_types, throwaway)
	var/list/instances = aggregated["instances"]
	if(length(instances))
		var/list/walls = list()
		var/list/floors = list()
		for(var/turf/simulated/T in block(locate(1, 1, 1), locate(world.maxx, world.maxy, 1)))
			if(istype(T, /turf/simulated/mineral))
				var/turf/simulated/mineral/M = T
				if(M.density && !M.mineral && !M.ignore_mapgen && !M.ignore_oregen)
					walls += M
			else if(istype(T, /turf/simulated/floor))
				floors += T
		for(var/datum/quarry_feature/F as anything in instances)
			if(F.placement_type == "pool")
				_quarry_place_pool_feature(F, floors)
			else if(length(F.ore_contributions))
				_quarry_place_wall_feature(F, walls)
	qdel(throwaway)

// Elevator stops at every depth a player has reached. Surface panel
// uses this as its "send to N" target. Returns null if no depth has
// been visited yet.
/datum/controller/subsystem/quarry/proc/deepest_elevator_stop()
	if(deepest_visited < 1)
		return null
	return deepest_visited


// Re-evaluate unlocked_depth based on aggregate goal completion. The
// deepest reachable depth advances by one for each consecutive
// stabilised layer starting from depth 1. A layer is "stabilised"
// when at least QUARRY_STABILITY_THRESHOLD% of its goals are
// individually satisfied — see layer_stability_percent.
//
// Idempotent. Call after every goal-progress event.
/datum/controller/subsystem/quarry/proc/recompute_unlocked_depth()
	while(TRUE)
		var/datum/quarry_layer/L = layers["[unlocked_depth]"]
		if(!L?.loaded)
			return
		if(layer_stability_percent(L) < QUARRY_STABILITY_THRESHOLD)
			return
		unlocked_depth++
		// Pre-roll the newly-frontier depth's features and goals so the
		// elevator UI can show them before anyone descends. The partial
		// snapshot is consumed by ensure_layer on first dispatch.
		if(!has_snapshot(unlocked_depth))
			preroll_layer(unlocked_depth)


// Returns the aggregate stability of a layer as a 0..100 integer.
// Mean of per-goal percent_complete across all goals on the layer —
// each goal is clamped 0..100 individually so over-mining one
// resource can't carry an under-mined one. A layer with no goals is
// treated as fully stable so a config whose rolled features all
// returned empty goal lists doesn't soft-lock the round.
/datum/controller/subsystem/quarry/proc/layer_stability_percent(datum/quarry_layer/L)
	if(!L)
		return 0
	var/total = length(L.goals)
	if(total <= 0)
		return 100
	var/sum_percent = 0
	for(var/datum/quarry_goal/G as anything in L.goals)
		if(!G)
			continue
		sum_percent += G.percent_complete()
	return round(sum_percent / total)

// Returns a /datum/quarry_layer_config picked weighted-randomly from all
// configs whose weight_at(depth) is non-zero. Returns null if none apply.
/datum/controller/subsystem/quarry/proc/select_config(depth)
	var/list/weighted = list()
	for(var/datum/quarry_layer_config/cfg in configs)
		var/w = cfg.weight_at(depth)
		if(w > 0)
			weighted[cfg] = w
	if(!length(weighted))
		return null
	return pickweight(weighted)

/datum/controller/subsystem/quarry/fire()
	tick_layer_danger()
	tick_layer_events()
	unload_empty_layers()

// Sweep loaded layers and unload any that have no live players on them.
// Called periodically from fire(). Layers already mid-unload are
// skipped so the async wipe can finish without being re-triggered.
/datum/controller/subsystem/quarry/proc/unload_empty_layers()
	// Snapshot the keys: unload_layer can mutate the list when the
	// async tail finishes.
	var/list/keys = layers.Copy()
	for(var/key in keys)
		var/datum/quarry_layer/L = layers[key]
		if(!L?.loaded || L.unloading)
			continue
		// Skip any depth the elevator is in the middle of dispatching
		// to — without this guard, the sweep snapshots+wipes the layer
		// between the elevator's ensure_layer call and its bay_at()
		// check, leaving the player staring at "the shaft groans."
		if(elevator?.pending_arrivals?[key])
			continue
		if(is_layer_empty(L.z))
			unload_layer(L.depth)

/datum/controller/subsystem/quarry/proc/get_layer(depth)
	return layers["[depth]"]

// Returns the /datum/quarry_layer for the given depth, creating + generating
// it if it does not currently exist or has been unloaded.
//
// Idempotent and safe to call from multiple ladder-click handlers. If a
// concurrent caller is already generating this depth, this caller waits
// up to ~10 seconds for the result.
//
// Restore-vs-generate: if a snapshot exists on disk (the layer was
// previously visited and unloaded), restore_layer reconstructs it.
// Otherwise generate_layer runs the full procgen path. Either way the
// result is cached in layers[key].
/datum/controller/subsystem/quarry/proc/ensure_layer(depth)
	var/key = "[depth]"
	var/datum/quarry_layer/existing = layers[key]
	if(existing?.loaded && !existing.unloading)
		return existing

	// Wait out a concurrent generation OR a concurrent unload of this
	// depth. Either way we want the slot truly free before we (re)build,
	// because building on a stale slot has the OLD unload's async tail
	// stomping the NEW layer's record when it finishes, and worse, has
	// the wipe pass potentially touching tiles the new player is on.
	//
	// No timeout: wait as long as it takes. The wipe yields per row via
	// CHECK_TICK and is bounded by the world being responsive enough to
	// run it. Capping the wait used to time out and let the new build
	// race the wipe — that's the bug we're avoiding.
	while(TRUE)
		existing = layers[key]
		if(!generating[key] && (!existing || (!existing.unloading && !existing.loaded)))
			break
		if(existing?.loaded && !existing.unloading)
			return existing
		sleep(2)

	// Re-check after the wait.
	existing = layers[key]
	if(existing?.loaded && !existing.unloading)
		return existing

	generating[key] = TRUE
	var/datum/quarry_layer/L = null
	if(has_snapshot(depth))
		// Partial snapshot = preroll_layer output. Goal previews are in
		// the file, but no tiles have been generated yet. Honor the
		// rolled feature set so what the player sees underground
		// matches the goals the UI promised.
		if(is_partial_snapshot(depth))
			var/list/preset = read_snapshot_feature_types(depth)
			var/path = _quarry_snapshot_path(depth)
			if(fexists(path))
				fdel(path)
			L = generate_layer(depth, preset)
		else
			L = restore_layer(depth)
			if(!L)
				log_game("SSquarry: restore_layer failed for depth [depth]; falling back to generate_layer")
	if(!L)
		L = generate_layer(depth)
	generating -= key

	if(L)
		layers[key] = L
	return L

// Allocates a Z, loads the empty stone template, applies a biome config,
// runs the cave generator, marks ores, scatters decorations, spawns mobs,
// and places the escape ladder and the down-ladder. Returns the layer
// record on success, null on failure.
/datum/controller/subsystem/quarry/proc/generate_layer(depth, list/preset_feature_types = null)
	var/datum/quarry_layer_config/cfg = select_config(depth)
	if(!cfg)
		log_game("SSquarry: no applicable config for depth [depth]; refusing to generate")
		return null

	var/_tl0 = world.timeofday
	var/datum/map_template/quarry_layer/template = new
	if(!template.load_new_z())
		log_game("SSquarry: failed to load_new_z for depth [depth]")
		return null
	var/new_z = world.maxz
	// The quarry digs the live map into additional z-levels at runtime, so refresh
	// the atmos vertical-adjacency table to cover the new level (multi-z atmos —
	// see SSair.build_multiz_atmos_levels). Vertical gas flow then follows turf
	// density: sealed rock blocks it, an open shaft passes it.
	SSair.build_multiz_atmos_levels()
	var/_tl1 = world.timeofday

	// Carve the cave (cave_system/quarry logs its own apply/icon timings).
	new /datum/random_map/automata/cave_system/quarry(cfg, 1, 1, new_z, QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE)
	var/_tl2 = world.timeofday

	// Build the biome map: each tile gets assigned a biome based on a
	// smooth noise field. Empty roster falls back to single-biome
	// behavior (every tile = config wall_turf).
	var/list/biome_map = null
	if(length(cfg.biome_roster))
		biome_map = _quarry_build_biome_map(depth, cfg.biome_roster, 1, 1, QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE)

	// Single block pass: repaint walls with the per-biome wall_turf
	// (when a biome map exists) AND bucket walls/floors at the same
	// time, instead of walking 65k tiles twice. ChangeTurf swaps the
	// reference in place, so reading `T` after the call still works
	// for the bucket assignment.
	var/list/floor_candidates = list()
	var/list/wall_candidates = list()
	for(var/turf/simulated/mineral/T in block(locate(1, 1, new_z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, new_z)))
		if(T.density)
			if(biome_map)
				var/datum/quarry_biome/B = _quarry_biome_at(biome_map, T)
				if(B?.wall_turf && T.type != B.wall_turf)
					T = T.ChangeTurf(B.wall_turf)
			wall_candidates += T
		else
			floor_candidates += T
	var/_tl3 = world.timeofday
	if(length(floor_candidates) < 2)
		log_game("SSquarry: generator produced fewer than 2 floor tiles at depth [depth]")
		return null

	var/list/bay_tiles = carve_elevator_room(new_z, depth, floor_candidates, wall_candidates)
	if(!length(bay_tiles))
		log_game("SSquarry: failed to carve elevator room at depth [depth]")
		return null
	elevator.layer_bays["[depth]"] = bay_tiles
	var/_tl4 = world.timeofday

	// Build the layer record up front so the rolled features' build_goals
	// can attach goals to it. Features are pure data (no runtime hooks)
	// so the order of operations is: roll → aggregate → place → build.
	var/datum/quarry_layer/L = new(depth)
	L.z = new_z
	L.config = cfg
	// Pre-rolled features from a partial snapshot take precedence so
	// the UI's goal preview matches what actually gets placed below.
	L.feature_types = length(preset_feature_types) ? preset_feature_types : _quarry_roll_feature_types(cfg)
	var/list/aggregated = _quarry_aggregate_features(L.feature_types, L)
	var/list/instances = aggregated["instances"]
	var/list/mob_table = aggregated["mob_table"]
	var/list/decoration_table = aggregated["decoration_table"]
	var/extra_mob_spawns = aggregated["extra_mob_spawns"]
	var/extra_decoration_density = aggregated["extra_decoration_density"]
	L.goals = aggregated["goals"]

	// Resource placement: each feature draws its own veins. Wall
	// features mark mineral walls with their ore; pool features
	// ChangeTurf a connected floor cluster to their pool_turf so the
	// upstream /obj/machinery/pump can extract reagents from it.
	// Mob-only / decoration-only features have no placement step —
	// their contributions are aggregated separately and applied via
	// the spawn passes below.
	for(var/datum/quarry_feature/F as anything in instances)
		if(F.placement_type == "pool")
			_quarry_place_pool_feature(F, floor_candidates)
		else if(length(F.ore_contributions))
			_quarry_place_wall_feature(F, wall_candidates)
	var/_tl5 = world.timeofday

	if(!length(floor_candidates))
		log_game("SSquarry: no floor tiles remain after elevator carve at depth [depth]")
		return null

	var/total_deco_density = cfg.decoration_density + extra_decoration_density
	if(total_deco_density > 0 && (length(decoration_table) || biome_map))
		for(var/turf/T as anything in floor_candidates)
			if(!prob(total_deco_density))
				continue
			// Same biome-priority rule as mob spawning: biome's deco
			// table wins at this tile if it has one, otherwise the
			// aggregated feature table.
			var/list/effective_deco = decoration_table
			if(biome_map)
				var/datum/quarry_biome/B = _quarry_biome_at(biome_map, T)
				if(B && length(B.decoration_contributions))
					effective_deco = B.decoration_contributions
			if(!length(effective_deco))
				continue
			var/deco_type = pickweight(effective_deco)
			if(deco_type)
				new deco_type(T)
	var/_tl6 = world.timeofday

	var/total_mob_count = cfg.mob_count + extra_mob_spawns
	// Fallback table when no biome-specific table applies at the
	// picked tile. Feature-aggregated table takes priority, then the
	// cfg's default_mob_table.
	var/list/fallback_mob_table = length(mob_table) ? mob_table : cfg.default_mob_table
	if(total_mob_count > 0 && (length(fallback_mob_table) || biome_map))
		var/spawned = 0
		var/list/spawn_candidates = floor_candidates.Copy()
		while(spawned < total_mob_count && length(spawn_candidates))
			var/turf/T = pick(spawn_candidates)
			spawn_candidates -= T
			if(_quarry_tile_is_safe(T))
				continue
			// Prefer the biome's mob table at this specific tile. If
			// the biome has none, fall back to the layer-wide table.
			var/list/effective_table = fallback_mob_table
			if(biome_map)
				var/datum/quarry_biome/B = _quarry_biome_at(biome_map, T)
				if(B && length(B.mob_contributions))
					effective_table = B.mob_contributions
			if(!length(effective_table))
				spawned++
				continue
			var/mob_type = pickweight(effective_table)
			if(mob_type)
				new mob_type(T)
			spawned++
	var/_tl7 = world.timeofday

	L.loaded = TRUE
	log_game("BENCH: generate_layer phases (depth [depth]) load_new_z=[(_tl1-_tl0)/10]s cave=[(_tl2-_tl1)/10]s bucket=[(_tl3-_tl2)/10]s carve=[(_tl4-_tl3)/10]s ore=[(_tl5-_tl4)/10]s deco=[(_tl6-_tl5)/10]s mobs=[(_tl7-_tl6)/10]s features=[length(L.feature_types)] goals=[length(L.goals)]")
	return L

// Carves a 3x3 elevator room out of the cave at a depth-deterministic
// location. Same depth always gets the same elevator coordinates so a
// snapshot's interior matches a re-generated layer's elevator placement
// and the persistence overlay doesn't clash with the freshly-placed
// elevator bay.
//
// Returns the 3x3 bay tiles in row-major order (matching surface bay).
// Mutates floor_candidates and wall_candidates in place to remove any
// tiles that the elevator footprint or approach corridor consumed.
/datum/controller/subsystem/quarry/proc/carve_elevator_room(z, depth, list/floor_candidates, list/wall_candidates)
	// Pick center deterministically from depth so restored layers land
	// their elevator on the same tiles the snapshot was taken from.
	// Each depth gets a stable (cx, cy) within the valid carve window
	// (3..MAX-2 on x, 3..MAX-5 on y so the 5x5 footprint and the
	// 3-tile north approach corridor both fit inside the map).
	var/list/elev_xy = _quarry_elevator_xy_for(depth)
	var/cx = elev_xy[1]
	var/cy = elev_xy[2]

	// Wall ring: perimeter of 5x5 centered on (cx, cy). The full north
	// edge (3 wall tiles at dy=2) becomes three lift airlocks, matching
	// the 3-door entry on the surface.
	for(var/dx in -2 to 2)
		for(var/dy in -2 to 2)
			var/tx = cx + dx
			var/ty = cy + dy
			// Skip the interior (3x3).
			if(abs(dx) <= 1 && abs(dy) <= 1)
				continue
			var/turf/T = locate(tx, ty, z)
			if(!isturf(T))
				continue
			floor_candidates -= T
			wall_candidates -= T
			// North row's 3 interior columns get doors; the two NW/NE
			// corners stay as walls.
			if(abs(dx) <= 1 && dy == 2)
				T = T.ChangeTurf(/turf/simulated/floor/tiled/dark)
				new /obj/machinery/door/airlock/lift(T)
				continue
			T.ChangeTurf(/turf/simulated/wall/elevator)

	// Interior 3x3: force dark tiled floor, collect into bay list in
	// row-major order (top row first, x ascending).
	var/list/bay = list()
	for(var/dy in -1 to 1)
		for(var/dx in -1 to 1)
			var/turf/T = locate(cx + dx, cy + dy, z)
			if(!isturf(T))
				continue
			floor_candidates -= T
			wall_candidates -= T
			T = T.ChangeTurf(/turf/simulated/floor/tiled/dark)
			bay += T

	if(length(bay) != 9)
		return list()

	// Carve a 3-tile-deep approach corridor north of the door so the
	// elevator is reachable without immediately needing a pickaxe. The
	// corridor is (cx-1..cx+1, cy+3..cy+5), plus an extra single tile at
	// (cx-2, cy+3) for the exterior call-button on the NW corner wall.
	for(var/dx in -1 to 1)
		for(var/dy in 3 to 5)
			var/turf/T = locate(cx + dx, cy + dy, z)
			if(!isturf(T))
				continue
			if(istype(T, /turf/simulated/mineral))
				var/turf/simulated/mineral/M = T
				if(M.density)
					M.make_floor()
				floor_candidates -= M
				wall_candidates -= M

	// Extra tile at (cx-2, cy+3) so the NW-corner exterior call button is
	// reachable. The button mounts visually onto the wall at (cx-2, cy+2)
	// (the elevator's NW corner wall).
	var/turf/exterior_panel_tile = locate(cx - 2, cy + 3, z)
	if(istype(exterior_panel_tile, /turf/simulated/mineral))
		var/turf/simulated/mineral/M = exterior_panel_tile
		if(M.density)
			M.make_floor()
		floor_candidates -= M
		wall_candidates -= M

	// Find the three doors we just placed; cache them in elevator.doors.
	var/list/this_layer_doors = list()
	for(var/dx in -1 to 1)
		var/turf/door_tile = locate(cx + dx, cy + 2, z)
		for(var/obj/machinery/door/airlock/lift/D in door_tile)
			this_layer_doors += D
	elevator.doors["[depth]"] = this_layer_doors

	// Interior call button on the elevator's south wall, reachable from
	// inside the bay. Used to send the elevator to the surface. Same tile
	// also gets a south-facing light fixture (visually pinned to the
	// south wall) to match the surface elevator's lighting.
	var/turf/south_panel_tile = locate(cx, cy - 1, z)
	if(isturf(south_panel_tile))
		var/obj/structure/quarry_elevator_panel/interior = new(south_panel_tile)
		interior.depth = depth
		interior.dir = SOUTH
		interior.pixel_y = -24
		var/obj/machinery/light/L = new(south_panel_tile)
		L.dir = SOUTH

	// Exterior call button on the NW corner wall, reachable from the
	// corridor outside the elevator. Used to summon the elevator here when
	// it's parked elsewhere.
	if(isturf(exterior_panel_tile))
		var/obj/structure/quarry_elevator_panel/exterior = new(exterior_panel_tile)
		exterior.depth = depth
		exterior.dir = SOUTH
		exterior.pixel_y = -24
		exterior.is_call_panel = TRUE

	return bay


// Unload a layer: snapshot it to disk, qdel everything on the z,
// turf-to-space the lot, drop the layer record. The z-index itself is
// not reclaimed (BYOND limitation).
/datum/controller/subsystem/quarry/proc/unload_layer(depth)
	var/key = "[depth]"
	var/datum/quarry_layer/L = layers[key]
	if(!L?.loaded || L.unloading)
		return
	L.unloading = TRUE

	// If the elevator is currently parked at this depth, recall its bay
	// contents to the surface before we wipe the Z. This preserves the
	// "persistent progress" promise — items the player left in the lift
	// don't get qdel'd along with the layer. Done synchronously because
	// it has to finish before the wipe touches the bay.
	if(elevator && elevator.current_depth == depth && !elevator.traveling)
		var/list/origin_bay = elevator.bay_at(depth)
		var/list/dest_bay = elevator.bay_at(0)
		if(length(origin_bay) == length(dest_bay))
			for(var/i in 1 to length(origin_bay))
				var/turf/src_t = origin_bay[i]
				var/turf/dst_t = dest_bay[i]
				if(!isturf(src_t) || !isturf(dst_t))
					continue
				for(var/atom/movable/AM in src_t)
					if(istype(AM, /mob/observer))
						continue
					if(AM.anchored)
						continue
					AM.forceMove(dst_t)
		elevator.current_depth = 0

	// Drop the layer's bay reference. The doors get qdel'd along with the Z
	// below, so just clear the list.
	if(elevator)
		elevator.layer_bays -= key
		elevator.doors -= key

	// Hand the slow part (snapshot + tile wipe) off so the SS tick
	// returns immediately. The layer stays in `layers` and is marked
	// `unloading` so the next periodic sweep doesn't try to unload it
	// again while this is in flight.
	INVOKE_ASYNC(src, PROC_REF(_finish_unload_layer), depth)


// Async tail of unload_layer. Runs the snapshot (yielding as it walks
// the 256x256 tile grid) and then the wipe pass (same). Both use
// CHECK_TICK internally so a long-running unload only consumes idle
// MC ticks instead of stalling the world.
//
// Safety: re-check is_layer_empty before each pass. If a player has
// arrived on the z between unload trigger and now (shouldn't happen
// given the elevator's bay-cleared check, but defensive), abort the
// unload entirely so we don't delete them.
/datum/controller/subsystem/quarry/proc/_finish_unload_layer(depth)
	var/key = "[depth]"
	var/datum/quarry_layer/L = layers[key]
	if(!L)
		return
	var/quarry_z = L.z

	if(!is_layer_empty(quarry_z))
		log_game("SSquarry: aborting unload of depth [depth] (z [quarry_z]) — a player is on the z")
		L.unloading = FALSE
		return

	// Snapshot the layer to disk before wiping so the next visit can
	// restore exactly what the players left behind.
	snapshot_layer(depth, quarry_z)

	// Re-check before the destructive pass. Snapshot took time during
	// which a player could in theory have arrived.
	if(!is_layer_empty(quarry_z))
		log_game("SSquarry: aborting wipe of depth [depth] (z [quarry_z]) — a player is on the z")
		L.unloading = FALSE
		return

	// Wipe pass: qdel every movable so the z stops ticking AI and
	// signal subscriptions. We deliberately do NOT ChangeTurf each
	// tile to /turf/space — benchmark showed ChangeTurf costs ~380µs
	// per tile and dominates wipe time (65k tiles × 380µs ≈ 25s).
	// Leaving the turfs alone has no behavioural cost (the z is
	// orphaned, nothing reaches it) and only keeps a small constant
	// memory footprint per orphaned tile until restart.
	//
	// CHECK_TICK_HIGH_PRIORITY yields only above 95% usage so the
	// wipe gets most of each MC tick. Batches per 4 rows.
	var/row_batch = 0
	for(var/y in 1 to QUARRY_LAYER_SIZE)
		for(var/x in 1 to QUARRY_LAYER_SIZE)
			var/turf/T = locate(x, y, quarry_z)
			if(!isturf(T))
				continue
			if(!length(T.contents))
				continue
			for(var/atom/movable/AM in T)
				if(istype(AM, /mob/observer))
					continue
				qdel(AM)
		row_batch++
		if(row_batch >= 4)
			row_batch = 0
			CHECK_TICK_HIGH_PRIORITY
			// Defensive: a player teleporting onto the z mid-wipe
			// triggers an immediate abort. Better a half-wiped z
			// than a deleted player.
			if(!is_layer_empty(quarry_z))
				log_game("SSquarry: stopping mid-wipe of depth [depth] (z [quarry_z]) — a player arrived on the z")
				L.unloading = FALSE
				return

	L.loaded = FALSE
	L.z = 0
	L.unloading = FALSE
	layers -= key

// Empty iff no /mob/living with an active mind (live client OR temporarily
// disconnected body) is on the Z. Bodies of disconnected players keep the
// layer loaded so players can reconnect.
/datum/controller/subsystem/quarry/proc/is_layer_empty(z)
	for(var/mob/living/M in GLOB.living_mob_list)
		if(M.z != z)
			continue
		if(M.mind)
			return FALSE
	return TRUE


// Deterministic (cx, cy) for a depth's elevator footprint. Same depth
// always returns the same coordinates so snapshot/restore overlays
// don't clash with a freshly-carved elevator. Adjacent depths get
// spread across the map via a small mix so they don't visually clump.
//
// Returns a 2-element list: list(cx, cy). Both fall inside the carve
// window described in carve_elevator_room (3..MAX-2 on x, 3..MAX-5 on
// y) so a 5x5 footprint plus the 3-tile north approach corridor fit.
//
// Implementation note: DM uses 24-bit floats for numbers, so Knuth's
// 32-bit multiplicative hash (depth * 2654435761) loses precision
// during the multiply, and the subsequent bitwise mask + modulo
// collapse to the bottom-left corner instead of spreading. Use small
// prime multipliers and stay well inside 24-bit range — works
// correctly across all reachable depths.
/proc/_quarry_elevator_xy_for(depth)
	var/x_window = QUARRY_LAYER_SIZE - 4  // 3..MAX-2 inclusive
	var/y_window = QUARRY_LAYER_SIZE - 7  // 3..MAX-5 inclusive
	// Two independent small-prime mixes for decorrelated x/y.
	var/cx = 3 + ((depth * 73 + 19) % x_window)
	var/cy = 3 + ((depth * 41 + 11) % y_window)
	return list(cx, cy)
