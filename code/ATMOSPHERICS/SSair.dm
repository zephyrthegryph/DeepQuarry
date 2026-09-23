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
	// auxmos turf processing writes these cost mirrors back into SSair each tick
	// (turfs/processing.rs writes cost_turfs/cost_post_process, groups.rs writes
	// cost_groups, katmos.rs writes cost_equalize). They MUST be declared or the
	// Rust write_var_id(byond_string!(...)) panics with NonExistentString.
	var/cost_post_process = 0
	var/cost_equalize = 0
	/// Last atmosphere generation published by the detached Rust turf worker.
	var/async_generation = 0
	/// End-to-end worker time for the most recently published generation, in milliseconds.
	var/async_compute_cost = 0
	var/async_seed_limit = 0
	var/async_selection_cost = 0
	var/async_snapshot_cost = 0
	var/async_fdm_cost = 0
	var/async_equalize_cost = 0
	var/async_publication_cost = 0
	/// Compact Rust->DM semantic events produced by the latest generation.
	var/async_semantic_events = 0
	var/async_reaction_events = 0
	var/async_overlay_events = 0
	var/async_reaction_callback_cost = 0
	var/async_overlay_callback_cost = 0
	var/async_cancelled = FALSE
	/// Largest immediate pressure mutation in the current/recent worker generation.
	var/async_pressure_urgency = 0
	var/cost_finalize_last = 0
	var/cost_finalize = 0
	var/unsteady_polling = FALSE
	/// Turfs in the connected components considered by the last generation.
	var/async_active_turfs = 0
	/// Explicit active seeds consumed by the latest worker generation.
	var/async_seed_turfs = 0
	/// Turfs still materially divergent after the latest worker generation.
	var/async_retained_turfs = 0
	/// Retained turfs with at least one temperature residual above the solver threshold.
	var/async_retained_temperature_turfs = 0
	/// Retained turfs with at least one composition/mole residual above the solver threshold.
	var/async_retained_mole_turfs = 0
	/// Turfs queued for the next local-frontier generation.
	var/async_pending_turfs = 0
	/// Exact scheduler-lane breakdown for diagnosing persistent work.
	var/async_pending_urgent_turfs = 0
	var/async_pending_fresh_turfs = 0
	var/async_pending_frontier_turfs = 0
	/// Mixtures copied into the latest worker snapshot.
	var/async_snapshot_mixtures = 0
	/// Mixtures materially changed by the latest published generation.
	var/async_published_mixtures = 0
	/// Transactions discarded because synchronous mutations changed their inputs.
	var/async_rejected_generations = 0
	/// Generations rejected specifically because a closed component lost mass or energy.
	var/async_conservation_rejections = 0
	/// Closed mutable components checked by the latest async generation.
	var/async_closed_components = 0
	/// Closed components that violated conservation in the latest generation.
	var/async_conservation_violation_components = 0
	/// Mixture count in the largest violating component from the latest generation.
	var/async_conservation_worst_component_mixtures = 0
	/// Largest absolute per-gas mole discrepancy in the latest generation.
	var/async_conservation_max_gas_delta = 0
	/// Largest absolute thermal-energy discrepancy in the latest generation.
	var/async_conservation_max_energy_delta = 0
	/// Detailed diagnostic for the latest violating generation, populated by Rust.
	var/async_conservation_diagnostic = ""
	/// Last cumulative violation count emitted to runtime.log.
	var/async_conservation_logged = 0

	// === auxmos turf-processing tunables (read by the Rust binds) ===
	// Every var below is read via read_number_id(byond_string!(...)) in the
	// verdigris turf hooks; declaring them is mandatory (NonExistentString panic
	// otherwise). Defaults per SSAIR_CONTRACT.
	/// FDM sharing steps per process_turfs tick (turfs/processing.rs).
	var/share_max_steps = 4
	/// Fraction of the delta a planetary turf shares with its atmosphere each pass.
	var/planet_share_ratio = 0.25

	// auxmos turf processing writes these counters back each tick. Declared so the
	// Rust write_var_id calls don't panic (NonExistentString). Informational only.
	var/low_pressure_turfs = 0
	var/high_pressure_turfs = 0
	var/num_group_turfs_processed = 0
	var/num_equalize_processed = 0

	// active_turfs / excited_groups are gone — turf sharing lives in the Rust
	// arena now. hotspots stays (LINDA hotspot fires are still DM). networks stays
	// (CHOMP pipenets). The rebuild/expansion queues below are unchanged.
	var/list/hotspots = list()
	var/list/networks = list()
	var/list/rebuild_queue = list()
	//Subservient to rebuild queue
	var/list/expansion_queue = list()
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
	var/list/arena_diag = vg_auxmos_diagnostics()
	msg += "\n  Cost:{"
	msg += "AT:[round(cost_turfs,1)]|"
	msg += "PP:[round(cost_post_process,1)]|"
	msg += "HS:[round(cost_hotspots,1)]|"
	msg += "EG:[round(cost_groups,1)]|"
	msg += "EQ:[round(cost_equalize,1)]|"
	msg += "HP:[round(cost_highpressure,1)]|"
	msg += "PN:[round(cost_pipenets,1)]|"
	msg += "RB:[round(cost_rebuilds,1)]|"
	msg += "ASYNC:[round(async_compute_cost,1)]|"
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
	msg += "EP:[expansion_queue.len]"
	msg += "|GEN:[async_generation]"
	msg += "|ACT:[async_active_turfs]"
	msg += "|PEND:[async_pending_turfs]"
	msg += "|SNAP:[async_snapshot_mixtures]"
	msg += "|PUB:[async_published_mixtures]"
	msg += "|EV:[async_semantic_events]"
	msg += "|RX:[async_reaction_events]"
	msg += "|VIS:[async_overlay_events]"
	msg += "|RXms:[round(async_reaction_callback_cost, 0.01)]"
	msg += "|VISms:[round(async_overlay_callback_cost, 0.01)]"
	msg += "|REJ:[async_rejected_generations]"
	msg += "|CREJ:[async_conservation_rejections]"
	msg += "|CLOSED:[async_closed_components]"
	msg += "|CV:[async_conservation_violation_components]"
	msg += "|CW:[async_conservation_worst_component_mixtures]"
	msg += "|CG:[round(async_conservation_max_gas_delta, 0.001)]"
	msg += "|CE:[round(async_conservation_max_energy_delta, 0.1)]"
	msg += "}"
	if(length(arena_diag) >= 15)
		msg += "\n  Arena:{MIX:[arena_diag[1]]/[arena_diag[2]]|FREE:[arena_diag[3]]|BASE:[arena_diag[4]]|BCAP:[arena_diag[5]]|DIRTY:[arena_diag[6]]|TURF:[arena_diag[7]]/[arena_diag[8]]|NODE:[arena_diag[9]]|EDGE:[arena_diag[10]]|ACTIVE:[arena_diag[11]]|CB:[arena_diag[12]]|HEAT:[arena_diag[13]]/[arena_diag[14]]/[arena_diag[15]]us}"
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

	// Hand Rust the map dimensions it needs to compute turf neighbours by
	// coordinate id. MUST precede setup_allturfs(), whose registration builds
	// adjacency from them; reading world vars from Rust is unreliable on BYOND 516
	// so DM pushes them in.
	vg_set_world_dims(world.maxx, world.maxy)

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
	// Floor the drain budget: when the arena's post_process floods the queue (e.g. the
	// round-start pass where every turf's vis hash flips from its 0 initial), a 1 ms
	// slice can't keep up and real per-turf visual/react callbacks queue behind the
	// backlog indefinitely. process_callbacks_for_millis returns as soon as the queue
	// empties, so this floor only actually spends time when there IS a backlog.
	if(initialized)
		timer = TICK_USAGE_REAL
		vg_finish_process_turfs(min(max(SSAIR_REMAINING_MS, 1), 3))
		cost_finalize_last = TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
		cost_finalize = cost_finalize ? MC_AVERAGE(cost_finalize, cost_finalize_last) : cost_finalize_last

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
	// Turf diffusion runs on a detached Rust worker against a private snapshot.
	// The hook returns TRUE while that generation is in flight, keeping SSair on
	// this step until it atomically publishes or rejects the result. Reactions,
	// visuals, and pressure callbacks remain queued for the main thread.
	// NOTE on cost bookkeeping: the Rust binds maintain their own smoothed cost
	// mirrors (cost_turfs, cost_post_process, cost_groups, cost_equalize) by
	// read-modify-writing those SSair vars themselves. So we do NOT reassign them
	// here — doing so would clobber the arena-reported timings.
	if(currentpart == SSAIR_TURFS)
		var/overtimed = process_turfs_auxtools(src, SSAIR_REMAINING_MS)
		if(state != SS_RUNNING)
			return
		if(overtimed)
			// The Rust worker owns this generation until publication. Marking the
			// subsystem paused makes the MC immediately resume and busy-poll it
			// thousands of times, preventing unrelated DM subsystems from running.
			// Keep the stage and poll once at SSair's next scheduled fire instead.
			unsteady_polling = TRUE
			if(async_pressure_urgency >= 100)
				wait = 1 // 10 Hz for breach/canister/explosion-scale changes.
			else if(async_pressure_urgency >= 20 || async_pending_turfs > 100)
				wait = 2 // 5 Hz for meaningful equalization.
			else
				wait = initial(wait) // Routine settling remains at the normal 2 Hz.
			return
		unsteady_polling = async_pressure_urgency >= 20 || async_pending_turfs > 100
		wait = async_pressure_urgency >= 100 ? 1 : unsteady_polling ? 2 : initial(wait)
		if(async_conservation_rejections > async_conservation_logged)
			async_conservation_logged = async_conservation_rejections
			log_runtime(async_conservation_diagnostic || "ATMOS_CONSERVATION_ERROR without Rust diagnostic payload")
			#ifdef UNIT_TESTS
			CRASH(async_conservation_diagnostic || "Atmos transaction violated conservation")
			#endif
		resumed = FALSE
		currentpart = SSAIR_FINALIZE_TURFS

	if(currentpart == SSAIR_FINALIZE_TURFS)
		// Drain the Rust->DM callback queue on the main thread. finish drains the
		// turf-processing callbacks; process_atmos_callbacks drains everything
		// else queued (both return TRUE on overtime). These invoke DM
		// air.react(turf) / turf.set_visuals(...) / turf.consider_pressure_difference().
		var/callback_budget = min(max(SSAIR_REMAINING_MS, 1), 3)
		var/overtimed = vg_finish_process_turfs(callback_budget)
		if(!overtimed)
			overtimed = vg_atmos_callback_handle(callback_budget)
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
// need a duplicate registry — SSmachines.all_machines already holds every
// /obj/machinery, and /obj/machinery/Initialize populates it during SSatoms.
// SSair runs after SSatoms (mapping/atoms deps), so by the time this fires
// every atmos device exists with init_dir() done; it's safe to wire nodes.
/datum/controller/subsystem/air/proc/setup_atmos_machinery()
	for (var/obj/machinery/atmospherics/AM in SSmachines.all_machines)
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
