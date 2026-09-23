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
//    per-turf register hook).
//  - the CHOMP-side lingering-fire procs (not provided by the reparent).

// === auxmos turf-processing FFI routes ===
// Gas args never appear here (these are turf/SSair hooks, not gas ops), so no
// "[gas_type]" stringification is needed. Every route calls a generated vg_* proc
// (code/__defines/verdigris/_bindings.dm); pure passthroughs were deleted in
// favour of calling vg_* directly.

/// Starts or polls an asynchronous Rust turf-sharing generation.
/// Returns TRUE while the worker is computing so SSair resumes this step.
/datum/controller/subsystem/air/proc/process_turfs_auxtools(remaining)
	return vg_process_turf_hook(src, remaining)

/// Diagnostic/test query: whether this exact turf is in either Rust activation queue.
/turf/proc/auxmos_is_atmos_active()
	return vg_turf_active_hook(src)

/// Fires the Rust superconductivity (heat-conduction) pass on a detached thread;
/// results land via the atmos callback queue drained in SSAIR_FINALIZE_TURFS.
/// cost_superconductivity is written back from the worker thread.
/datum/controller/subsystem/air/proc/process_turf_heat()
	return vg_process_heat_notify(src)

/// Rust arena heat temperature (K) for this turf, or a sentinel if untracked.
/turf/proc/return_temperature()
	return vg_hook_turf_temperature(src)

/// Monotonic gas revision used by sensors to avoid rescanning unchanged air.
/turf/proc/air_revision()
	return vg_hook_air_revision(src)

/// Set this turf's temperature. The superconductivity arena OWNS turf heat (it seeds
/// from the `temperature` var only at registration, then runs its own conduction), so
/// a bare `T.temperature = x` updates a stale mirror the arena ignores. This is the
/// sanctioned setter: it updates the DM mirror AND pushes the value into the arena.
/// Use it for any external heat injection (pipe-to-wall exchange, holodeck programs).
/turf/proc/set_temperature(temp)
	temperature = temp
	return vg_hook_set_turf_temperature(src, temp)

/// Registers / refreshes (flag >= 0) or removes (flag < 0) this turf's air in the
/// Rust arena and publishes its air-block mask (AIR_BLOCK_KEEP keeps the one Rust
/// has). Rust reads blocks_air / air._extools_pointer_gasmixture / planetary_atmos
/// / initial_gas_mix, and rebuilds the turf's adjacency from the masks.
///
/// Base /turf is a NO-OP: only /turf/open carries an `air` var, and the Rust
/// register reads `air._extools_pointer_gasmixture` when blocks_air == 0.
/// Non-open turfs (/turf/unsimulated/planetary floors, which have blocks_air == 0
/// but no `air` var) would make that read raise a runtime. Gate the FFI to open
/// turfs.
/turf/proc/update_air_ref(flag, mask = AIR_BLOCK_KEEP)
	return

/turf/open/update_air_ref(flag, mask = AIR_BLOCK_KEEP)
	// Walls (blocks_air) are fine: Rust short-circuits on blocks_air before
	// reading air. Only skip registering an airless tile that doesn't block air;
	// always let the unregister (flag < 0) path through.
	if(flag >= 0 && !blocks_air && isnull(air))
		return
	// Register with SIMULATION_ANY so the Rust FDM processes this turf; the
	// negative unregister flag passes straight through.
	return vg_hook_register_turf(src, flag >= 0 ? SIMULATION_ANY : flag, mask)

/// Bulk arena registration: one FFI entry for a whole assoc list of turf ->
/// air-block mask. Callers MUST pre-filter with the rule
/// /turf/open/update_air_ref applies (skip !blocks_air && isnull(air)) or the
/// Rust side errors reading their air var.
/proc/auxmos_register_turfs_bulk(list/turf_masks)
	return vg_hook_register_turfs_bulk(turf_masks, SIMULATION_ANY)

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
