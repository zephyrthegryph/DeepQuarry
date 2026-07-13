// DQ LINDA turf glue: the previous build of this file existed because
// /turf/simulated didn't inherit from /turf/open and had to be hand-bridged
// for air persistence + hotspots. That bridge has been replaced by a
// `parent_type = /turf/open` declaration on /turf/simulated (code/game/turfs/
// simulated.dm) and /turf/space (code/game/turfs/space/space.dm), so the
// turf atmos glue now runs on simulated turfs the same as it does on
// /turf/open subtypes in /tg/.
//
// What's left in this file:
//  - the auxmos turf-processing FFI routes (the SSair.fire() driver and the
//    per-turf register/adjacency hooks) — these live HERE (a compiled file)
//    because auxmos_bindings.dm, which also declares them, is intentionally NOT
//    #included (it would duplicate the gas_mixture proc defs). Keeping just the
//    turf/SSair routes here avoids that collision.
//  - the SSair init-time hook that fires per-turf adjacency calculation, and the
//    CHOMP-side lingering-fire procs (not provided by the reparent).

// === auxmos turf-processing FFI routes ===
// Gas args never appear here (these are turf/SSair hooks, not gas ops), so no
// "[gas_type]" stringification is needed. Every route is call_ext(VERDIGRIS, ...).
// process_atmos_callbacks / auxtools_atmos_init live in auxmos_init_bridge.dm;
// don't redeclare them here.

/// Runs one FDM turf-sharing cycle in the Rust arena, bounded by `remaining` ms.
/// Reads SSair.share_max_steps / equalize_enabled / planet_share_ratio and
/// writes back cost_turfs / cost_post_process / low_pressure_turfs /
/// high_pressure_turfs. Returns TRUE if interrupted by the time budget.
/datum/controller/subsystem/air/proc/process_turfs_auxtools(remaining)
	return call_ext(VERDIGRIS, "byond:process_turf_hook_ffi")(src, remaining)

/// Runs one excited-group processing cycle. Reads excited_group_pressure_goal,
/// writes cost_groups / num_group_turfs_processed. Returns TRUE if overtimed.
/datum/controller/subsystem/air/proc/process_excited_groups_auxtools(remaining)
	return call_ext(VERDIGRIS, "byond:groups_hook_ffi")(src, remaining)

/// Runs one katmos equalize cycle. Reads equalize_hard_turf_limit, writes
/// cost_equalize / num_equalize_processed. Returns TRUE if overtimed.
/datum/controller/subsystem/air/proc/process_turf_equalize_auxtools(remaining)
	return call_ext(VERDIGRIS, "byond:equalize_hook_ffi")(src, remaining)

/// Drains the turf-processing callback queue on the main thread (react /
/// set_visuals / consider_pressure_difference). Returns TRUE if overtimed.
/datum/controller/subsystem/air/proc/finish_turf_processing_auxtools(time_remaining)
	return call_ext(VERDIGRIS, "byond:finish_process_turfs_ffi")(time_remaining)

/// Pushes world.maxx / world.maxy into the Rust superconductivity arena so it can
/// compute turf neighbours by coordinate id. Call once before setup_allturfs().
/datum/controller/subsystem/air/proc/auxmos_set_world_dims(max_x, max_y)
	return call_ext(VERDIGRIS, "byond:set_world_dims_ffi")(max_x, max_y)

/// Fires the Rust superconductivity (heat-conduction) pass on a detached thread;
/// results land via the atmos callback queue drained in SSAIR_FINALIZE_TURFS.
/// cost_superconductivity is written back from the worker thread.
/datum/controller/subsystem/air/proc/process_turf_heat()
	return call_ext(VERDIGRIS, "byond:process_heat_notify_ffi")(src)

/// Rust arena heat temperature (K) for this turf, or a sentinel if untracked.
/turf/proc/return_temperature()
	return call_ext(VERDIGRIS, "byond:hook_turf_temperature_ffi")(src)

/// Set this turf's temperature. The superconductivity arena OWNS turf heat (it seeds
/// from the `temperature` var only at registration, then runs its own conduction), so
/// a bare `T.temperature = x` updates a stale mirror the arena ignores. This is the
/// sanctioned setter: it updates the DM mirror AND pushes the value into the arena.
/// Use it for any external heat injection (pipe-to-wall exchange, holodeck programs).
/turf/proc/set_temperature(temp)
	temperature = temp
	return call_ext(VERDIGRIS, "byond:hook_set_turf_temperature_ffi")(src, temp)

/// Registers / refreshes (flag >= 0) or removes (flag < 0) this turf's air ref in
/// the Rust arena. Rust reads blocks_air / air._extools_pointer_gasmixture /
/// planetary_atmos / initial_gas_mix.
///
/// Base /turf is a NO-OP: only /turf/open carries an `air` var, and the Rust
/// hook_register_turf unconditionally reads `air._extools_pointer_gasmixture`
/// (when blocks_air == 0). Non-open turfs (/turf/unsimulated/planetary floors,
/// which have blocks_air == 0 but NO `air` var — 1188 of them on Southern Cross)
/// would make that read raise a per-tick runtime. Gate the FFI to open turfs.
/turf/proc/update_air_ref(flag)
	return

// Rust hook_register_turf uses the flag arg AS the turf's SimulationFlags
// (turfs.rs). A turf is only processed by the FDM if it has SIMULATION_DIFFUSE
// or SIMULATION_ALL set (is_active = flags.intersects(SIMULATION_ANY)). The
// driver's callers use `flag` only as a register(>=0)/unregister(<0) signal, so
// register must translate to SIMULATION_ANY or the turf is registered inert and
// gas never moves.
#define SIMULATION_DIFFUSE 1
#define SIMULATION_ALL 2
#define SIMULATION_ANY 3

/turf/open/update_air_ref(flag)
	// Airless open turfs that don't block air (rare, but the reparent made walls
	// /turf/open) would also trip the null-air read on the register path. Walls
	// (blocks_air == 1) are fine — Rust short-circuits on blocks_air before reading
	// air. So only skip the register (flag >= 0) case for the null-air/non-blocking
	// tile; always allow the unregister (flag < 0) path through.
	if(flag >= 0 && !blocks_air && isnull(air))
		return
	// Register (flag>=0) with SIMULATION_ANY so the Rust FDM actually processes
	// this turf; unregister passes the negative flag straight through.
	return call_ext(VERDIGRIS, "byond:hook_register_turf_ffi")(src, flag >= 0 ? SIMULATION_ANY : flag)

/// Bulk arena registration: one FFI entry for a whole list of turfs (Rust
/// iterates). Callers MUST pre-filter with the same rule /turf/open/update_air_ref
/// applies — skip tiles with !blocks_air && isnull(air) — or the Rust side
/// errors reading their air var. Used by SSair.setup_allturfs; runtime
/// single-turf paths keep using update_air_ref.
/proc/auxmos_register_turfs_bulk(list/turf/turfs)
	return call_ext(VERDIGRIS, "byond:hook_register_turfs_bulk_ffi")(turfs, SIMULATION_ANY)

/// Bulk adjacency push: one FFI entry for a whole list of registered turfs.
/proc/auxmos_update_adjacencies_bulk(list/turf/turfs)
	return call_ext(VERDIGRIS, "byond:hook_infos_bulk_ffi")(turfs)

/// Pushes this turf's atmos_adjacent_turfs graph into the Rust arena. Both the
/// turf and every neighbour must already be registered (update_air_ref) or the
/// arena silently drops the unresolved edges. Base /turf is a no-op — only open
/// turfs participate in the arena.
/turf/proc/__update_auxtools_turf_adjacency_info()
	return

/turf/open/__update_auxtools_turf_adjacency_info()
	return call_ext(VERDIGRIS, "byond:hook_infos_ffi")(src)

// /turf/open is what SSair.setup_allturfs() expects to walk and call
// Initalize_Atmos() on. The base /turf/proc/Initalize_Atmos in
// tg_infra_compat.dm is a no-op; we override it on /turf/open here to do the
// /tg/-canonical thing — build the adjacency graph and seed current_cycle.
/turf/open/Initalize_Atmos(times_fired, register = TRUE)
	// Set current_cycle BEFORE building adjacency — init_immediate_calculate_adjacent_turfs
	// reads current_cycle on both sides to decide "have I already done this neighbor?".
	// SSair.setup_allturfs passes a negative (decrementing) times_fired so the very
	// first turf has current_cycle = -1 and untouched neighbors still default to 0;
	// "0 <= -1" is FALSE so they get added. With the order swapped (our own
	// current_cycle still 0 when the calc runs) every neighbor gets skipped and
	// atmos_adjacent_turfs comes out empty — gases never spread.
	current_cycle = times_fired
	// Build the DM adjacency graph (multi-z aware).
	init_immediate_calculate_adjacent_turfs()
	// Register this turf's air ref into the Rust arena (arena.map[turf_id] = node).
	// We do NOT push adjacency here: auxmos' update_adjacencies drops any edge whose
	// endpoint isn't registered yet, and during setup_allturfs a neighbour may not
	// be initialised at this point. setup_allturfs runs a SECOND pass (PASS 2 in
	// that proc) that pushes adjacency once every turf is registered. Runtime
	// callers (air_update_turf) hit the fully-registered arena and push adjacency
	// immediately, so they're unaffected.
	// register=FALSE lets setup_allturfs skip this per-turf FFI call and instead
	// bulk-register everything in chunked list calls (~327k call_ext dispatches
	// saved on a 5-z roundstart).
	if(register)
		update_air_ref(0)


// === CHOMP lingering-fire bridge ===
//
// Several CHOMP atmos callers expect /turf/proc/lingering_fire,
// /turf/proc/feed_lingering_fire, and /turf/proc/create_fire. /turf/open
// doesn't supply these; provide them in terms of LINDA's hotspot model so
// CHOMP-originated igniters/candles/cigs/runes/etc. light fires on
// /turf/open subtypes (which now include /turf/simulated and /turf/space).

/turf/open/lingering_fire()
	return active_hotspot

/turf/open/feed_lingering_fire(intensity = 1)
	var/temp = T0C + 300 * max(0.1, intensity)
	hotspot_expose(temp, CELL_VOLUME * 0.5, soh = TRUE)
	SSair.add_to_active(src)

/turf/open/create_fire(temp = T0C + 300)
	hotspot_expose(temp, CELL_VOLUME, soh = FALSE)
	SSair.add_to_active(src)
