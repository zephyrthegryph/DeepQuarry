SUBSYSTEM_DEF(air)
	name = "Atmospherics"
	dependencies = list(
		/datum/controller/subsystem/mapping,
		/datum/controller/subsystem/atoms,
		// setup_atmos_machinery iterates REGISTRY_MEMBERS(REGISTRY_MACHINES), so
		// SSmachines must finish populating that list before SSair inits.
		/datum/controller/subsystem/machines,
	)
	priority = FIRE_PRIORITY_AIR
	wait = 0.5 SECONDS
	ss_flags = SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	var/cached_cost = 0

	// cost_atoms / atom_process / process_atoms removed alongside
	// /atom/proc/process_exposure. /tg/'s atom-exposure pipeline (paper
	// burning, etc.) isn't wired on this fork — atoms use CHOMP's fire_act
	// dispatch instead. Strip the SSAIR_PROCESS_ATOMS step + atom_process
	// list (nothing was ever registered) so the dispatcher's hot loop only
	// touches code that does work.
	var/cost_turfs = 0
	var/cost_hotspots = 0
	var/cost_groups = 0
	var/cost_highpressure = 0
	var/cost_superconductivity = 0
	var/cost_pipenets = 0
	var/cost_rebuilds = 0
	/// Main-thread cost of the gas tick and its events, in milliseconds.
	var/cost_gas_events = 0
	// Informational counters read by the stat panel, the profiler and benches.
	var/low_pressure_turfs = 0
	var/high_pressure_turfs = 0
	var/num_group_turfs_processed = 0
	var/num_equalize_processed = 0

	/// Turf gas runs on the Rust gas field (verdigris/domains/gas, M1b): each
	/// fire pins the newest frame, starts the next and hands DM its events.
	/// Events of the current fire still to dispatch (GAS_EVENT_STRIDE each).
	var/list/pending_gas_events
	var/gas_event_index = 1
	/// Gas frames started so far (vg_gas_stats()[1]).
	var/gas_frames = 0
	/// Events dispatched by the last fire.
	var/gas_events_last = 0
	/// Reaction, visual and spacewind events dispatched by the last fire.
	var/gas_reactions_last = 0
	var/gas_visuals_last = 0
	var/gas_pressure_last = 0

	// hotspots stays (LINDA hotspot fires are still DM). networks stays
	// (pipe network wrappers). The rebuild/expansion queues below are unchanged.
	var/list/hotspots = list()
	var/list/networks = list()
	var/list/rebuild_queue = list()
	//Subservient to rebuild queue
	var/list/expansion_queue = list()
	/// Turfs that requested a high-pressure spacewind push this tick
	/// (consider_pressure_difference, from GAS_EVENT_PRESSURE); the DM
	/// high-pressure step drains it.
	var/list/high_pressure_delta = list()

	var/list/pipe_init_dirs_cache = list()
	//atmos singletons
	var/list/gas_reactions = list()
	var/list/atmos_gen
	var/list/planetary = list() //Lets cache static planetary mixes
	/// List of gas string -> canonical gas mixture
	var/list/strings_to_mix = list()


	//Special functions lists
	// Turf heat is the heat domain (vg-heat, code/modules/heat/heat.dm): the
	// SSAIR_SUPERCONDUCTIVITY fire() step below calls process_turf_heat().
	// high_pressure_delta moved up next to the auxmos tunables (auxmos appends to it).
	// atom_process removed; see cost_atoms comment.
	/// Reactions which will contribute to a hotspot's size.
	var/list/hotspot_reactions

	/// A cache of objects that perisists between processing runs when resumed == TRUE. Dangerous, qdel'd objects not cleared from this may cause runtimes on processing.
	var/list/currentrun = list()
	var/currentpart = SSAIR_PIPENETS

	var/map_loading = TRUE
	var/list/queued_for_activation
	var/display_all_groups = FALSE

	var/list/reaction_handbook
	var/list/gas_handbook


/datum/controller/subsystem/air/stat_entry(msg)
	var/list/diag = vg_auxmos_diagnostics()
	var/list/stats = vg_gas_stats()
	msg += "\n  Cost:{"
	msg += "GAS:[round(cost_turfs,1)]|"
	msg += "EV:[round(cost_gas_events,1)]|"
	msg += "HS:[round(cost_hotspots,1)]|"
	msg += "HP:[round(cost_highpressure,1)]|"
	msg += "PN:[round(cost_pipenets,1)]|"
	msg += "} "
	msg += "\n  Count:{HS:[hotspots.len]|HPD:[high_pressure_delta.len]|PN:[networks.len]"
	msg += "|EV:[gas_events_last]|RX:[gas_reactions_last]|VIS:[gas_visuals_last]|PUSH:[gas_pressure_last]}"
	if(length(stats) >= 17)
		msg += "\n  Field:{FRAMES:[stats[1]]|CMD:[stats[2]]|FRAMEus:[round(stats[9], 1)]|BACKLOG:[stats[10]]|OVERLAY:[stats[11]]|AGE:[stats[12]]|SKIP:[stats[13]]|SHORT:[round(stats[14], 0.001)]|MODE:[stats[17] ? "fallback" : "overlay"]}"
	if(length(diag) >= 10)
		msg += "\n  Gas:{MIX:[diag[1]]/[diag[2]]|PIPE:[diag[3]]/[diag[4]]|TURF:[diag[5]]|CB:[diag[7]]|HEAT:[diag[8]]/[diag[9]]/[diag[10]]us}"
	return ..()


/datum/controller/subsystem/air/Initialize()
	map_loading = FALSE

	// Register the gas roster in the Rust arena FIRST — reaction setup
	// (init_gas_reactions -> build_min_requirements) and everything else that
	// touches gas ops needs the registry populated, or lookups fail with "Invalid
	// gas ID" (and a throwing reaction New() would leave gas_reactions null).
	// gas_reactions is still empty (SSair default) at this point, so hook_init's
	// reaction parser reads nothing — reactions run in DM via /datum/gas_mixture/react().
	// Idempotent: in practice the very first turf air (created during mapload,
	// before this runs) already triggered registration via gas_mixture/New().
	ensure_auxmos_gas_registry()

	// The gas field was sized at world start (vg_configure_world); make sure it
	// covers the map as loaded before registering turfs.
	vg_configure_world(world.maxx, world.maxy, world.maxz)

	// Fill GLOB.gas_data.overlays now that meta_gas_info's overlay objects exist,
	// so the Rust turf-processing visuals path can render gas clouds.
	build_gas_data_overlays()

	gas_reactions = init_gas_reactions()
	hotspot_reactions = init_hotspot_reactions()

	build_multiz_atmos_levels()
	setup_allturfs()
	setup_atmos_machinery()
	// Rust setup is the sole pipenet topology build. Compatibility wrappers are
	// materialized from its connected-region publication.
	setup_turf_visuals()
	// atmos_handbooks_init() removed. /tg/'s gas handbook is an
	// in-game wiki UI that DQ doesn't ship; the call had nothing to do.
	return SS_INIT_SUCCESS


/datum/controller/subsystem/air/fire(resumed = FALSE)
	var/timer = TICK_USAGE_REAL

	//Rebuilds can happen at any time, so this needs to be done outside of the normal system
	cost_rebuilds = 0

	// Drain the Rust->DM callback queue (errors reported from Rust).
	if(initialized)
		vg_atmos_callback_handle(min(max(SSAIR_REMAINING_MS, 1), 3))

	if(currentpart == SSAIR_PIPENETS || !resumed)
		timer = TICK_USAGE_REAL
		if(!resumed)
			cached_cost = 0
		process_pipenets(resumed)
		cached_cost += TICK_USAGE_REAL - timer
		if(state != SS_RUNNING)
			return
		cost_pipenets = MC_AVERAGE(cost_pipenets, TICK_DELTA_TO_MS(cached_cost))
		resumed = FALSE
		currentpart = SSAIR_TURFS

	// === Turf gas (the Rust gas field) ===
	// One call pins the newest frame, collects its events and watch wakes,
	// applies heat, and starts the next frame on the gas pool; it never waits.
	// Then DM dispatches the frame's events: reactions, visuals, spacewind.
	if(currentpart == SSAIR_TURFS)
		timer = TICK_USAGE_REAL
		if(!resumed)
			cached_cost = 0
			pending_gas_events = vg_gas_tick()
			gas_event_index = 1
			gas_frames++
			cost_turfs = MC_AVERAGE(cost_turfs, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
			gas_events_last = 0
			gas_reactions_last = 0
			gas_visuals_last = 0
			gas_pressure_last = 0
		process_gas_events(resumed)
		cached_cost += TICK_USAGE_REAL - timer
		if(state != SS_RUNNING)
			return
		cost_gas_events = MC_AVERAGE(cost_gas_events, TICK_DELTA_TO_MS(cached_cost))
		pending_gas_events = null
		resumed = FALSE
		currentpart = SSAIR_HOTSPOTS

	if(currentpart == SSAIR_HOTSPOTS)
		timer = TICK_USAGE_REAL
		if(!resumed)
			cached_cost = 0
		process_hotspots(resumed)
		cached_cost += TICK_USAGE_REAL - timer
		if(state != SS_RUNNING)
			return
		cost_hotspots = MC_AVERAGE(cost_hotspots, TICK_DELTA_TO_MS(cached_cost))
		resumed = FALSE
		currentpart = SSAIR_HIGHPRESSURE

	// Spacewind. consider_pressure_difference (called from the FINALIZE_TURFS /
	// EQUALIZE callbacks above) populates high_pressure_delta; drain it here.
	if(currentpart == SSAIR_HIGHPRESSURE)
		timer = TICK_USAGE_REAL
		if(!resumed)
			cached_cost = 0
		process_high_pressure_delta(resumed)
		cached_cost += TICK_USAGE_REAL - timer
		if(state != SS_RUNNING)
			return
		cost_highpressure = MC_AVERAGE(cost_highpressure, TICK_DELTA_TO_MS(cached_cost))
		resumed = FALSE
		currentpart = SSAIR_SUPERCONDUCTIVITY

	// The heat domain: turf<->turf conduction, radiation to space, turf<->air and
	// heat bodies run as frames on vg-heat's pool. process_turf_heat() only
	// collects the finished frame, starts the next, and dispatches watch wakes.
	if(currentpart == SSAIR_SUPERCONDUCTIVITY)
		process_turf_heat()
		resumed = FALSE

	// SSAIR_PROCESS_ATOMS step removed; see cost_atoms comment.

	currentpart = SSAIR_PIPENETS
	SStgui.update_uis(SSair) //Lightning fast debugging motherfucker

/datum/controller/subsystem/air/Recover()
	// active_turfs / excited_groups / active_super_conductivity are gone (arena-side).
	hotspots = SSair.hotspots
	networks = SSair.networks
	rebuild_queue = SSair.rebuild_queue
	expansion_queue = SSair.expansion_queue
	pipe_init_dirs_cache = SSair.pipe_init_dirs_cache
	gas_reactions = SSair.gas_reactions
	atmos_gen = SSair.atmos_gen
	planetary = SSair.planetary
	high_pressure_delta = SSair.high_pressure_delta
	currentrun = SSair.currentrun
	queued_for_activation = SSair.queued_for_activation

/// Dispatches the gas field's events for this fire (GAS_EVENT_STRIDE values
/// each: kind, turf, value, other turf). Resumable.
/datum/controller/subsystem/air/proc/process_gas_events(resumed = FALSE)
	var/list/events = pending_gas_events
	var/count = length(events)
	while(gas_event_index <= count)
		var/kind = events[gas_event_index]
		var/turf/open/T = events[gas_event_index + 1]
		var/value = events[gas_event_index + 2]
		var/turf/other = events[gas_event_index + 3]
		gas_event_index += GAS_EVENT_STRIDE
		gas_events_last++
		if(!istype(T))
			continue
		switch(kind)
			if(GAS_EVENT_REACT)
				gas_reactions_last++
				if(T.air)
					T.air.react(T)
			if(GAS_EVENT_VISUAL)
				gas_visuals_last++
				T.set_visuals()
			if(GAS_EVENT_PRESSURE)
				gas_pressure_last++
				T.consider_pressure_difference(other, value)
		if(MC_TICK_CHECK)
			return

/// Test hook: runs `frames` gas frames to completion, deterministically (no
/// wall clock), and dispatches their events like fire() does.
/datum/controller/subsystem/air/proc/run_gas_frames(frames = 1)
	pending_gas_events = vg_gas_run_frames(frames)
	gas_event_index = 1
	gas_frames += frames
	while(gas_event_index <= length(pending_gas_events))
		var/list/events = pending_gas_events
		var/kind = events[gas_event_index]
		var/turf/open/T = events[gas_event_index + 1]
		var/value = events[gas_event_index + 2]
		var/turf/other = events[gas_event_index + 3]
		gas_event_index += GAS_EVENT_STRIDE
		if(!istype(T))
			continue
		switch(kind)
			if(GAS_EVENT_REACT)
				if(T.air)
					T.air.react(T)
			if(GAS_EVENT_VISUAL)
				T.set_visuals()
			if(GAS_EVENT_PRESSURE)
				T.consider_pressure_difference(other, value)
	pending_gas_events = null
	process_high_pressure_delta()

/datum/controller/subsystem/air/proc/process_pipenets(resumed = FALSE)
	if (!resumed)
		rust_commit_pending_pipenets()
		src.currentrun = networks.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(currentrun.len)
		var/datum/thing = currentrun[currentrun.len]
		currentrun.len--
		if(thing)
			thing.process()
		else
			networks.Remove(thing)
		if(MC_TICK_CHECK)
			return

// add_to_rebuild_queue / add_to_expansion / remove_from_expansion removed —
// /tg/-style pipenet rebuild queues are unused under CHOMP's /datum/pipe_network
// pipeline model.

// process_atoms removed alongside atom_process / process_exposure.
// process_atmos_machinery removed; see vars block comment.

// process_super_conductivity removed — LINDA's DM superconduction engine is
// deleted; auxmos' Rust heat subsystem is not wired.

/datum/controller/subsystem/air/proc/process_hotspots(resumed = FALSE)
	if (!resumed)
		src.currentrun = hotspots.Copy()
	//cache for sanic speed (lists are references anyways)
	var/list/currentrun = src.currentrun
	while(currentrun.len)
		var/obj/effect/hotspot/H = currentrun[currentrun.len]
		currentrun.len--
		if (H)
			H.process()
		else
			hotspots -= H
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/air/proc/process_high_pressure_delta(resumed = FALSE)
	while (high_pressure_delta.len)
		var/turf/open/T = high_pressure_delta[high_pressure_delta.len]
		high_pressure_delta.len--
		T.high_pressure_movements()
		T.pressure_difference = 0
		if(MC_TICK_CHECK)
			return

// process_active_turfs / process_excited_groups removed — transactional turf FDM
// sharing now lives in the Rust arena (process_turfs_auxtools, driven from fire()).

// process_rebuilds + expand_pipeline removed — /tg/-style pipenet expansion
// (rebuild_pipes / set_pipenet / replace_pipenet / pipeline_expansion / etc.)
// is replaced by CHOMP's /datum/pipe_network/build_network, which runs in the
// pipe's own Initialize chain.

// === active-turf API compat shims ===
//
// add_to_active / remove_from_active / sleep_active_turf were the DM active-turf
// bookkeeping API. ~50 call sites across the codebase (doors, canisters, vents,
// ChangeTurf, pipelines, mining, admin verbs) still call them meaning "this
// turf's air changed — reconsider it". The DM active-turf list is gone, so these
// now just push the turf's current air ref into the Rust arena via update_air_ref;
// auxmos decides activity itself. The blockchanges/excited-group args are ignored
// (excited groups are arena-side).

///Legacy API: a turf's air changed and should be reconsidered. Pushes its air
///ref to the Rust arena. (Was: add to the DM active-turf list.)
/datum/controller/subsystem/air/proc/add_to_active(turf/open/activate, blockchanges = FALSE)
	if(!activate)
		return
	// During mapload we can't register turfs whose air isn't set up yet; queue
	// them and register on StopLoadingMap, preserving the old load-time behaviour.
	if(map_loading && !(activate.flags_1 & INITIALIZED_1))
		if(queued_for_activation)
			queued_for_activation[activate] = activate
		return
	// flag >= 0 registers/updates the turf in the arena; the Rust side reads
	// blocks_air / air / planetary_atmos and figures out whether it's an airless
	// wall, space, planet, or a regular turf on its own.
	activate.update_air_ref(0)

///Legacy API: remove a turf's air from arena processing (Read: it became a wall
///or is being torn down). flag < 0 unregisters.
/datum/controller/subsystem/air/proc/remove_from_active(turf/open/T)
	if(!T)
		return
	T.update_air_ref(-1)

///Legacy API alias — the arena has no separate "sleep" state; treat it as a
///normal re-register (auxmos will drop it from processing once it's equalized).
/datum/controller/subsystem/air/proc/sleep_active_turf(turf/open/T)
	if(!T)
		return
	T.update_air_ref(0)

/datum/controller/subsystem/air/StartLoadingMap()
	LAZYINITLIST(queued_for_activation)
	map_loading = TRUE

/datum/controller/subsystem/air/StopLoadingMap()
	map_loading = FALSE
	// Turfs deferred during a mid-round map load (submaps, expedition z-levels).
	// Now that the whole batch exists, register each with its air-block mask; Rust
	// builds the adjacency regardless of order.
	for(var/turf/T as anything in queued_for_activation)
		T.update_air_ref(0, T.air_block_mask())
	queued_for_activation.Cut()

/// Bridge the movement-multiz connection data (GLOB.z_levels, populated by
/// /obj/effect/landmark/map_data during mapload) into SSmapping.multiz_levels and
/// on to Rust, which only links turfs vertically across linked z-levels.
/// No-op on single-z maps, where HasAbove/HasBelow return 0 for every z.
/// Re-runnable when the z-level layout changes.
/datum/controller/subsystem/air/proc/build_multiz_atmos_levels()
	if(!SSmapping)
		return
	if(length(SSmapping.multiz_levels) < world.maxz)
		SSmapping.multiz_levels.len = world.maxz
	for(var/z in 1 to world.maxz)
		// Z_LEVEL_UP / Z_LEVEL_DOWN are the numeric direction constants UP (16)
		// and DOWN (32); the per-z list is read POSITIONALLY, so it must be at
		// least Z_LEVEL_DOWN entries long. Slot 16 = up-connected, 32 = down.
		var/list/traits = new /list(Z_LEVEL_DOWN)
		traits[Z_LEVEL_UP] = HasAbove(z) ? TRUE : FALSE
		traits[Z_LEVEL_DOWN] = HasBelow(z) ? TRUE : FALSE
		SSmapping.multiz_levels[z] = traits
	push_z_links()

/// Update only a newly-added dynamic level and its immediate boundary. A full
/// rebuild is appropriate during round initialization, but mid-round template
/// loads must not replace authored traits on unrelated shuttle/sector levels.
/datum/controller/subsystem/air/proc/update_dynamic_multiz_atmos_level(z)
	if(!SSmapping || z < 1 || z > world.maxz)
		return
	if(length(SSmapping.multiz_levels) < world.maxz)
		SSmapping.multiz_levels.len = world.maxz
	for(var/level in max(1, z - 1) to min(world.maxz, z + 1))
		var/list/traits = new /list(Z_LEVEL_DOWN)
		traits[Z_LEVEL_UP] = HasAbove(level) ? TRUE : FALSE
		traits[Z_LEVEL_DOWN] = HasBelow(level) ? TRUE : FALSE
		SSmapping.multiz_levels[level] = traits
	push_z_links()

/// Sends Rust one UP|DOWN link mask per z-level from SSmapping.multiz_levels.
/// Rust re-syncs vertical adjacency across the whole map, so call it only when
/// the z-level layout changes.
/datum/controller/subsystem/air/proc/push_z_links()
	var/list/links = new /list(world.maxz)
	for(var/z in 1 to world.maxz)
		var/list/traits = length(SSmapping.multiz_levels) >= z ? SSmapping.multiz_levels[z] : null
		if(!traits)
			links[z] = NONE
			continue
		links[z] = (traits[Z_LEVEL_UP] ? UP : NONE) | (traits[Z_LEVEL_DOWN] ? DOWN : NONE)
	vg_set_z_links(links)

/datum/controller/subsystem/air/proc/setup_allturfs()
	times_fired++

	// Round-start turf init: register every eligible turf's air in the Rust arena
	// together with its air-block mask. Rust builds the whole adjacency graph
	// from the masks and discovers active turfs itself; there is no DM adjacency
	// pass. Chunked so a single FFI call can't hold the tick hostage.
	var/list/turf_masks = list()
	for(var/turf/setup as anything in ALL_TURFS())
		if(!setup.init_air)
			continue
		var/turf/open/open_setup = setup
		// Same eligibility rule as /turf/open/update_air_ref: a non-blocking
		// tile with no air mixture must not reach the Rust register (it reads
		// air unconditionally when blocks_air == 0).
		if(istype(open_setup) && (open_setup.blocks_air || !isnull(open_setup.air)))
			turf_masks[open_setup] = open_setup.air_block_mask()
			if(length(turf_masks) >= 8192)
				auxmos_register_turfs_bulk(turf_masks)
				heat_register_turfs(turf_masks)
				turf_masks = list()
		if(length(GLOB.clients) && TICK_CHECK)
			stoplag()
	if(length(turf_masks))
		auxmos_register_turfs_bulk(turf_masks)
		heat_register_turfs(turf_masks)

// log_active_turfs / resolve_active_graph removed — they existed only to service
// the DM roundstart active-turf diffing pass, which is gone (auxmos discovers
// active turfs from the arena). GLOB.active_turfs_startlist is no longer written.

// single-pass init for every map-loaded /obj/machinery/atmospherics.
// /tg/ ran this off SSair.atmos_machinery (which doubled as the per-tick
// process queue). On this fork devices process via SSmachines, so we don't
// need a duplicate registry — REGISTRY_MEMBERS(REGISTRY_MACHINES) already holds every
// /obj/machinery, and /obj/machinery/Initialize populates it during SSatoms.
// SSair runs after SSatoms (mapping/atoms deps), so by the time this fires
// every atmos device exists with init_dir() done; it's safe to wire nodes.
/datum/controller/subsystem/air/proc/setup_atmos_machinery()
	for (var/obj/machinery/atmospherics/AM in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		AM.atmos_init()
		if(length(GLOB.clients) && TICK_CHECK)
			stoplag()
	setup_rust_pipenets()

// setup_pipenets removed — see Initialize() comment.

GLOBAL_LIST_EMPTY(colored_turfs)
GLOBAL_LIST_EMPTY(colored_images)
/datum/controller/subsystem/air/proc/setup_turf_visuals()
	for(var/sharp_color in GLOB.contrast_colors)
		var/list/add_to = list()
		GLOB.colored_turfs += list(add_to)
		for(var/offset in 0 to SSmapping.max_plane_offset)
			var/obj/effect/overlay/atmos_excited/suger_high = new()
			SET_PLANE_W_SCALAR(suger_high, HIGH_GAME_PLANE, offset)
			add_to += suger_high
			var/image/shiny = new('icons/effects/effects.dmi', suger_high, "atmos_top")
			SET_PLANE_W_SCALAR(shiny, HIGH_GAME_PLANE, offset)
			shiny.color = sharp_color
			GLOB.colored_images += shiny

// setup_template_machinery removed — no callers, /tg/-style pipenet init not used.


// /tg/'s SSair.get_init_dirs(type, dir, init_dir) removed — CHOMP pipe
// construction caches via SSmachines.get_init_dirs (game/machinery/pipe/
// construction.dm:226) and atmospherics.dm's /obj/machinery/atmospherics/get_init_dirs.
// LINDA's variant was unused.

/datum/controller/subsystem/air/proc/generate_atmos()
	atmos_gen = list()
	for(var/T in subtypesof(/datum/atmosphere))
		var/datum/atmosphere/atmostype = T
		atmos_gen[initial(atmostype.id)] = new atmostype

/// Takes a gas string, returns the matching mutable gas_mixture
/datum/controller/subsystem/air/proc/parse_gas_string(gas_string, gastype = /datum/gas_mixture)
	var/cache_key = "[gas_string]-[gastype]"
	var/datum/gas_mixture/cached = strings_to_mix[cache_key]

	if(cached)
		if(istype(cached, /datum/gas_mixture/immutable))
			return cached
		return cached.copy()

	var/datum/gas_mixture/canonical_mix = new gastype()
	// We set here so any future key changes don't fuck us
	strings_to_mix[cache_key] = canonical_mix
	gas_string = preprocess_gas_string(gas_string)

	// Moles/temperature live in the Rust arena now — write through the arena-backed
	// setters (set_moles stringifies the gas path per the get_strid contract;
	// set_temperature clamps + refreshes the DM mirror). immutable mixtures parse
	// through their own parse_string_immutable path instead.
	var/list/gas = gas_string_to_list(gas_string)
	if(gas["TEMP"])
		canonical_mix.set_temperature(text2num(gas["TEMP"]))
		gas -= "TEMP"
	else // if we do not have a temp in the new gas mix lets assume room temp.
		canonical_mix.set_temperature(T20C)
	for(var/id in gas)
		var/path = id
		if(!ispath(path))
			path = gas_id2path(path) //a lot of these strings can't have embedded expressions (especially for mappers), so support for IDs needs to stick around
		canonical_mix.set_moles(path, text2num(gas[id]))

	if(istype(canonical_mix, /datum/gas_mixture/immutable))
		return canonical_mix
	return canonical_mix.copy()

/datum/controller/subsystem/air/proc/preprocess_gas_string(gas_string)
	if(!atmos_gen)
		generate_atmos()
	if(!atmos_gen[gas_string])
		return gas_string
	var/datum/atmosphere/mix = atmos_gen[gas_string]
	return mix.gas_string

/// Parses the semicolon-delimited mapping format without URL-decoding its values.
/datum/controller/subsystem/air/proc/gas_string_to_list(gas_string)
	var/list/parsed = list()
	for(var/entry in splittext(gas_string, ";"))
		var/separator = findtext(entry, "=")
		if(!separator)
			continue
		var/key = copytext(entry, 1, separator)
		var/value = copytext(entry, separator + 1)
		parsed[key] = value
	return parsed

// start_processing_machine / stop_processing_machine removed.
// See vars block comment: SSair never owned device processing on this fork.

// This fork's TGUI base calls tgui_state / tgui_interact / tgui_data / tgui_act
// on the src object (see code/modules/tgui/external.dm), NOT the /tg/ ui_* names.
// These were previously declared as ui_* procs, so the framework never called them
// and the panel was dead. Renamed to the fork convention + opened by an admin verb
// (code/modules/admin/verbs/debug.dm: "Debug Atmospherics").
/datum/controller/subsystem/air/tgui_state(mob/user)
	return ADMIN_STATE(R_DEBUG)

/datum/controller/subsystem/air/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AtmosControlPanel", "Atmospherics Debug")
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/controller/subsystem/air/tgui_data(mob/user)
	var/list/data = list()
	// Excited groups + active-turf/superconduction lists live in the Rust arena
	// now and aren't enumerable from DM. Surface the per-tick auxmos counters the
	// binds report back instead of the (deleted) DM lists.
	data["excited_groups"] = list()
	data["active_size"] = num_group_turfs_processed + num_equalize_processed
	data["hotspots_size"] = hotspots.len
	data["excited_size"] = num_group_turfs_processed
	data["conducting_size"] = 0
	data["frozen"] = can_fire
	data["show_all"] = display_all_groups
	data["fire_count"] = times_fired
	#ifdef TRACK_MAX_SHARE
	data["display_max"] = TRUE
	#else
	data["display_max"] = FALSE
	#endif
	data["showing_user"] = user.hud_used.atmos_debug_overlays
	return data

/datum/controller/subsystem/air/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = ui?.user
	if(!user || !check_rights_for(user.client, R_DEBUG))
		return
	switch(action)
		if("move-to-target")
			var/turf/target = locate(params["spot"])
			if(!target)
				return
			user.forceMove(target)
		if("toggle-freeze")
			can_fire = !can_fire
			return TRUE
		// toggle_show_group / toggle_show_all removed — excited groups live in the
		// Rust arena and have no DM turf_list to display/hide.
		if("toggle_show_all")
			display_all_groups = !display_all_groups
			return TRUE
		if("toggle_user_display")
			user.hud_used.atmos_debug_overlays = !user.hud_used.atmos_debug_overlays
			if(user.hud_used.atmos_debug_overlays)
				user.client.images += GLOB.colored_images
			else
				user.client.images -= GLOB.colored_images
			return TRUE
