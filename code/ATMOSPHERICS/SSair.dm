SUBSYSTEM_DEF(air)
	name = "Atmospherics"
	dependencies = list(
		/datum/controller/subsystem/mapping,
		/datum/controller/subsystem/atoms,
		// setup_atmos_machinery iterates SSmachines.all_machines, so
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
	var/cost_adjacent = 0
	// auxmos turf processing writes these cost mirrors back into SSair each tick
	// (turfs/processing.rs writes cost_turfs/cost_post_process, groups.rs writes
	// cost_groups, katmos.rs writes cost_equalize). They MUST be declared or the
	// Rust write_var_id(byond_string!(...)) panics with NonExistentString.
	var/cost_post_process = 0
	var/cost_equalize = 0

	// === auxmos turf-processing tunables (read by the Rust binds) ===
	// Every var below is read via read_number_id(byond_string!(...)) in the
	// verdigris turf hooks; declaring them is mandatory (NonExistentString panic
	// otherwise). Defaults per SSAIR_CONTRACT.
	/// FDM sharing steps per process_turfs tick (turfs/processing.rs).
	var/share_max_steps = 4
	/// Enables katmos equalize (turfs/processing.rs gates on this AND cfg!(fastmos)).
	var/equalize_enabled = TRUE
	/// Fraction of the delta a planetary turf shares with its atmosphere each pass.
	var/planet_share_ratio = 0.25
	/// Pressure delta below which an excited group is considered equalized (groups.rs).
	var/excited_group_pressure_goal = 0.5
	/// Hard cap on turfs a single katmos equalize pass may touch (katmos.rs).
	var/equalize_hard_turf_limit = 2000

	// auxmos turf processing writes these counters back each tick. Declared so the
	// Rust write_var_id calls don't panic (NonExistentString). Informational only.
	var/low_pressure_turfs = 0
	var/high_pressure_turfs = 0
	var/num_group_turfs_processed = 0
	var/num_equalize_processed = 0

	// active_turfs / excited_groups are gone — turf sharing lives in the Rust
	// arena now. hotspots stays (LINDA hotspot fires are still DM). networks stays
	// (CHOMP pipenets). The rebuild/expansion/adjacent queues below are unchanged.
	var/list/hotspots = list()
	var/list/networks = list()
	var/list/rebuild_queue = list()
	//Subservient to rebuild queue
	var/list/expansion_queue = list()
	/// List of turfs to recalculate adjacent turfs on before processing
	var/list/adjacent_rebuild = list()
	/// Turfs that requested a high-pressure spacewind push this tick. auxmos
	/// (katmos explosively_depressurize) appends to this list via
	/// consider_pressure_difference; the DM high-pressure step drains it.
	var/list/high_pressure_delta = list()
	// /tg/'s SSair.atmos_machinery (an atmos-tick-scheduled device
	// queue) is dead code on this fork: atmospherics devices run via
	// SSmachines.processing_machines (CHOMP-legacy /obj/machinery process()).
	// Nothing ever called start_processing_machine, so the list was always
	// empty. Removed along with cost_atmos_machinery, process_atmos_machinery,
	// the SSAIR_ATMOSMACHINERY currentpart step, and the no-op
	// /atom/proc/process_atmos hook.

	var/list/pipe_init_dirs_cache = list()
	//atmos singletons
	var/list/gas_reactions = list()
	var/list/atmos_gen
	var/list/planetary = list() //Lets cache static planetary mixes
	/// List of gas string -> canonical gas mixture
	var/list/strings_to_mix = list()


	//Special functions lists
	// active_super_conductivity removed — LINDA's DM superconduction engine is
	// deleted. auxmos ships a Rust superconductivity subsystem (process_turf_heat)
	// but it is NOT wired here (out of scope for the turf-processing cutover). See
	// the migration notes; reviving heat conduction means calling process_turf_heat
	// as a fire() step and declaring its turf vars.
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
	msg += "\n  Cost:{"
	msg += "AT:[round(cost_turfs,1)]|"
	msg += "PP:[round(cost_post_process,1)]|"
	msg += "HS:[round(cost_hotspots,1)]|"
	msg += "EG:[round(cost_groups,1)]|"
	msg += "EQ:[round(cost_equalize,1)]|"
	msg += "HP:[round(cost_highpressure,1)]|"
	msg += "PN:[round(cost_pipenets,1)]|"
	msg += "RB:[round(cost_rebuilds,1)]|"
	msg += "AJ:[round(cost_adjacent,1)]|"
	msg += "} "
	// Active-turf/excited-group counts now live in the Rust arena; the DM lists
	// are gone. Surface the auxmos-reported per-tick turf counts instead.
	msg += "\n  Count:{GT:[num_group_turfs_processed]|"
	msg += "EQ:[num_equalize_processed]|"
	msg += "LP:[low_pressure_turfs]|"
	msg += "HP:[high_pressure_turfs]|"
	msg += "HS:[hotspots.len]|"
	msg += "HPD:[high_pressure_delta.len]|"
	msg += "PN:[networks.len]|"
	msg += "RB:[rebuild_queue.len]|"
	msg += "EP:[expansion_queue.len]|"
	msg += "AJ:[adjacent_rebuild.len]"
	msg += "}"
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

	// Fill GLOB.gas_data.overlays now that meta_gas_info's overlay objects exist,
	// so the Rust turf-processing visuals path can render gas clouds.
	build_gas_data_overlays()

	gas_reactions = init_gas_reactions()
	hotspot_reactions = init_hotspot_reactions()

	build_multiz_atmos_levels()
	setup_allturfs()
	setup_atmos_machinery()
	// setup_pipenets() removed: CHOMP pipes call build_network()
	// themselves lazily through return_air() / build_network(), so no
	// central pipenet construction phase is needed once each device's
	// atmos_init() has wired its node references.
	setup_turf_visuals()
	process_adjacent_rebuild()
	// atmos_handbooks_init() removed. /tg/'s gas handbook is an
	// in-game wiki UI that DQ doesn't ship; the call had nothing to do.
	return SS_INIT_SUCCESS


/datum/controller/subsystem/air/fire(resumed = FALSE)
	var/timer = TICK_USAGE_REAL

	//Rebuilds can happen at any time, so this needs to be done outside of the normal system
	cost_rebuilds = 0
	cost_adjacent = 0

	// We need to have a solid setup for turfs before fire, otherwise we'll get massive runtimes and strange behavior
	if(length(adjacent_rebuild))
		timer = TICK_USAGE_REAL
		process_adjacent_rebuild()
		//This does mean that the apperent rebuild costs fluctuate very quickly, this is just the cost of having them always process, no matter what
		cost_adjacent = TICK_USAGE_REAL - timer
		if(state != SS_RUNNING)
			return

	// /tg/-style rebuild_queue/expansion_queue dispatch removed — CHOMP pipes
	// rebuild their networks through /obj/machinery/atmospherics/pipe Initialize
	// and the ChangeTurf path, no SSair orchestration needed.

	// Drain the Rust->DM atmos callback queue (gas-overlay updates + reactions the
	// arena's post_process pass enqueues for every turf whose gas changed) up front,
	// unconditionally, each fire. The stepped pipeline below only reaches its own
	// drain step (SSAIR_FINALIZE_TURFS) once the turf + equalize steps finish without
	// overtiming; with every turf registered active the turf step can pause on
	// overtime every fire and never reach it, starving the drain — so gas clouds that
	// spread onto a neighbouring tile via the FDM never get their overlay refreshed
	// (the tile that RECEIVED gas, as opposed to the one a machine injected into,
	// relies entirely on this callback). Draining here guarantees those run; it's a
	// no-op when the queue is empty.
	if(initialized)
		finish_turf_processing_auxtools(SSAIR_REMAINING_MS)

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

	// SSAIR_ATMOSMACHINERY step removed: see vars block comment.

	// === auxmos turf processing ===
	// The Rust binds run their own internal work loops bounded by a millisecond
	// budget (SSAIR_REMAINING_MS) and return TRUE if they were interrupted
	// ("overtimed"). On interruption we pause and resume this same currentpart
	// next fire(). process_turfs also SPAWNS callbacks (react / set_visuals /
	// consider_pressure_difference) onto a queue that FINALIZE_TURFS drains on the
	// main thread. cost_turfs / cost_post_process / cost_groups / cost_equalize are
	// written back into SSair by the binds themselves.
	// NOTE on cost bookkeeping: the Rust binds maintain their own smoothed cost
	// mirrors (cost_turfs, cost_post_process, cost_groups, cost_equalize) by
	// read-modify-writing those SSair vars themselves. So we do NOT reassign them
	// here — doing so would clobber the arena-reported timings.
	if(currentpart == SSAIR_TURFS)
		var/overtimed = process_turfs_auxtools(src, SSAIR_REMAINING_MS)
		// process_excited_groups only does work if process_turfs ran this cycle,
		// so run it immediately after (it has its own budget/overtime return).
		if(!overtimed)
			overtimed = process_excited_groups_auxtools(src, SSAIR_REMAINING_MS)
		if(state != SS_RUNNING)
			return
		if(overtimed) // ran out of tick; pause so we resume this step next run
			pause()
			return
		resumed = FALSE
		currentpart = SSAIR_EQUALIZE

	if(currentpart == SSAIR_EQUALIZE)
		// katmos equalize. No-op unless a process_turfs cycle queued equalizes.
		var/overtimed = process_turf_equalize_auxtools(src, SSAIR_REMAINING_MS)
		if(state != SS_RUNNING)
			return
		if(overtimed)
			pause()
			return
		resumed = FALSE
		currentpart = SSAIR_FINALIZE_TURFS

	if(currentpart == SSAIR_FINALIZE_TURFS)
		// Drain the Rust->DM callback queue on the main thread. finish drains the
		// turf-processing callbacks; process_atmos_callbacks drains everything
		// else queued (both return TRUE on overtime). These invoke DM
		// air.react(turf) / turf.set_visuals(...) / turf.consider_pressure_difference().
		var/overtimed = finish_turf_processing_auxtools(SSAIR_REMAINING_MS)
		if(!overtimed)
			overtimed = process_atmos_callbacks(SSAIR_REMAINING_MS)
		if(state != SS_RUNNING)
			return
		if(overtimed)
			pause()
			return
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

	// SSAIR_SUPERCONDUCTIVITY step removed: DM engine deleted, auxmos heat unwired.
	// SSAIR_PROCESS_ATOMS step removed; see cost_atoms comment.

	currentpart = SSAIR_PIPENETS
	SStgui.update_uis(SSair) //Lightning fast debugging motherfucker

/datum/controller/subsystem/air/Recover()
	// active_turfs / excited_groups / active_super_conductivity are gone (arena-side).
	hotspots = SSair.hotspots
	networks = SSair.networks
	rebuild_queue = SSair.rebuild_queue
	expansion_queue = SSair.expansion_queue
	adjacent_rebuild = SSair.adjacent_rebuild
	pipe_init_dirs_cache = SSair.pipe_init_dirs_cache
	gas_reactions = SSair.gas_reactions
	atmos_gen = SSair.atmos_gen
	planetary = SSair.planetary
	high_pressure_delta = SSair.high_pressure_delta
	currentrun = SSair.currentrun
	queued_for_activation = SSair.queued_for_activation

/datum/controller/subsystem/air/proc/process_adjacent_rebuild(init = FALSE)
	var/list/queue = adjacent_rebuild

	while (length(queue))
		var/turf/currT = queue[1]
		queue.Cut(1,2)

		// Rebuild the DM adjacency graph (multi-z aware) and push the result to
		// the Rust arena. The old MAKE_ACTIVE / KILL_EXCITED distinction is gone —
		// auxmos decides activity itself from the arena; we just keep the arena's
		// adjacency + air-ref view of this turf current. Register the air ref FIRST
		// (arena.map must hold the turf before update_adjacencies can attach edges).
		currT.immediate_calculate_adjacent_turfs()
		currT.update_air_ref(0)
		currT.__update_auxtools_turf_adjacency_info()

		if(init)
			CHECK_TICK
		else
			if(MC_TICK_CHECK)
				break

/datum/controller/subsystem/air/proc/process_pipenets(resumed = FALSE)
	if (!resumed)
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

// process_active_turfs / process_excited_groups removed — turf FDM sharing and
// excited-group tracking now live in the Rust arena (process_turfs_auxtools /
// process_excited_groups_auxtools, driven from fire()).

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
	// Turfs deferred during a mid-round map load (submaps, quarry z-levels). Now
	// that the whole batch exists, rebuild each one's adjacency, register it, then
	// push adjacency to the arena (all endpoints in the batch are registered by the
	// time the second loop runs).
	for(var/turf/T as anything in queued_for_activation)
		T.immediate_calculate_adjacent_turfs()
		T.update_air_ref(0)
	for(var/turf/T as anything in queued_for_activation)
		T.__update_auxtools_turf_adjacency_info()
	queued_for_activation.Cut()

/// Bridge the movement-multiz connection data (GLOB.z_levels, populated by
/// /obj/effect/landmark/map_data during mapload) into SSmapping.multiz_levels,
/// the table init_immediate_calculate_adjacent_turfs reads to decide vertical
/// atmos adjacency. Without this the init fast-path never wires UP/DOWN turf
/// adjacency even when z-levels are vertically stacked (the runtime recalc path
/// uses GetAbove/GetBelow and already works; only init lagged). No-op on
/// single-z maps, where HasAbove/HasBelow return 0 for every z. Re-runnable
/// when the z-level layout changes.
/datum/controller/subsystem/air/proc/build_multiz_atmos_levels()
	if(!SSmapping)
		return
	if(length(SSmapping.multiz_levels) < world.maxz)
		SSmapping.multiz_levels.len = world.maxz
	for(var/z in 1 to world.maxz)
		// Z_LEVEL_UP / Z_LEVEL_DOWN are the numeric direction constants UP (16)
		// and DOWN (32). init_immediate_calculate_adjacent_turfs reads this
		// per-z list POSITIONALLY (z_traits[Z_LEVEL_UP] / [Z_LEVEL_DOWN]), so it
		// must be at least Z_LEVEL_DOWN entries long or both read and write go
		// out of bounds. Slot 16 = up-connected, slot 32 = down-connected.
		var/list/traits = new /list(Z_LEVEL_DOWN)
		traits[Z_LEVEL_UP] = HasAbove(z) ? TRUE : FALSE
		traits[Z_LEVEL_DOWN] = HasBelow(z) ? TRUE : FALSE
		SSmapping.multiz_levels[z] = traits

/datum/controller/subsystem/air/proc/setup_allturfs()
	times_fired++

	// Roundstart turf init. The old DM active-turf diffing pass is gone: turf
	// FDM sharing lives in the Rust arena, which discovers active turfs itself on
	// the first process_turfs tick. So here we only need to build each turf's air
	// mixture + adjacency graph and register it in the arena.
	//
	// current_cycle is still seeded (decrementing per sleep) so the O(n)
	// init_immediate_calculate_adjacent_turfs fast-path in Initalize_Atmos works.
	var/time = -1

	// PASS 1: build each turf's DM adjacency graph and register its air ref in the
	// Rust arena. Adjacency is NOT pushed to the arena here — auxmos drops edges to
	// unregistered turfs, and a neighbour may not be registered yet on this pass.
	var/list/turf/open/open_turfs = list()
	for(var/turf/setup as anything in ALL_TURFS())
		if (!setup.init_air)
			continue
		setup.Initalize_Atmos(time)
		if(istype(setup, /turf/open))
			open_turfs += setup
		if(CHECK_TICK)
			time--

	// PASS 2: every /turf/open is now registered in the arena, so pushing the
	// adjacency graph resolves all edges (both endpoints exist in arena.map).
	for(var/turf/open/registered as anything in open_turfs)
		registered.__update_auxtools_turf_adjacency_info()
		CHECK_TICK

// log_active_turfs / resolve_active_graph removed — they existed only to service
// the DM roundstart active-turf diffing pass, which is gone (auxmos discovers
// active turfs from the arena). GLOB.active_turfs_startlist is no longer written.

// single-pass init for every map-loaded /obj/machinery/atmospherics.
// /tg/ ran this off SSair.atmos_machinery (which doubled as the per-tick
// process queue). On this fork devices process via SSmachines, so we don't
// need a duplicate registry — SSmachines.all_machines already holds every
// /obj/machinery, and /obj/machinery/Initialize populates it during SSatoms.
// SSair runs after SSatoms (mapping/atoms deps), so by the time this fires
// every atmos device exists with init_dir() done; it's safe to wire nodes.
/datum/controller/subsystem/air/proc/setup_atmos_machinery()
	for (var/obj/machinery/atmospherics/AM in SSmachines.all_machines)
		AM.atmos_init()
		CHECK_TICK

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
	var/list/gas = params2list(gas_string)
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
