// Auxmos init/lifecycle bridge.
//
// The Rust gas-math backend IS live: /datum/gas_mixture is an opaque handle
// over the Rust arena, and every gas proc in gasmixtures/gas_mixture.dm routes
// through the generated vg_* procs (code/__defines/verdigris/_bindings.dm).
// This file hands Rust the gas registry rows; the registry
// is populated by ensure_auxmos_gas_registry() below, called from
// SSair.Initialize AND lazily from /datum/gas_mixture/New() (mapload turf air
// is created before SSair inits, so the lazy path is load-bearing — see the
// note above it).

// The gas registry MUST be initialised in auxmos before any gas_mixture's
// set_moles runs — otherwise the gas ids are unknown and set_moles no-ops
// ("Invalid gas ID"), so every mixture stays empty (the whole station boots
// in vacuum). Turf air is created eagerly in /turf/open/Initialize (mapload),
// which runs BEFORE SSair.Initialize, so we can't rely on SSair to register
// gases first. Register lazily on the first gas_mixture ever created (New()),
// guarded so it runs exactly once. build_auxmos_gas_registry() only reads the
// compiled /datum/gas roster, so it's safe this early.
GLOBAL_VAR_INIT(auxmos_gas_registry_initialized, FALSE)

/proc/ensure_auxmos_gas_registry()
	if(GLOB.auxmos_gas_registry_initialized)
		return
	// Set the guard only after init succeeds so a runtimed first attempt (e.g.
	// verdigris failed to load) retries on the next mixture instead of leaving
	// the registry permanently unpopulated after one log line.
	vg_hook_init(build_auxmos_gas_registry())
	GLOB.auxmos_gas_registry_initialized = TRUE

// byondapi_stack_trace: every Rust error and caught panic routes back into DM here (the bind
// macro wraps each error with "in verdigris bind `name`"). Each one is counted per bind
// (GLOB.vg_bind_errors, shown by verdigris_metrics_list() and the profiler); the first
// occurrence of each distinct message is logged to the world log AND raised as a real DM
// runtime, so admins see it in the runtime log and a unit test that triggers one fails,
// naming the bind. Repeats are only counted, so a per-turf flood cannot drown the log.
GLOBAL_LIST_EMPTY(auxmos_seen_errors)
/// Rust bind name -> errors seen since boot.
GLOBAL_LIST_EMPTY(vg_bind_errors)
/// TRUE while a test deliberately provokes Rust errors (they are counted and logged, not raised).
GLOBAL_VAR_INIT(vg_errors_expected, FALSE)

/// The bind name inside a Rust error message, or "unknown".
/proc/vg_error_bind_name(msg)
	var/start = findtext(msg, "in verdigris bind `")
	if(!start)
		return "unknown"
	start += length("in verdigris bind `")
	var/end = findtext(msg, "`", start)
	return end ? copytext(msg, start, end) : "unknown"

/proc/byondapi_stack_trace(msg)
	var/key = "[msg]"
	var/bind = vg_error_bind_name(key)
	GLOB.vg_bind_errors[bind]++
	if(GLOB.auxmos_seen_errors[key])
		return
	GLOB.auxmos_seen_errors[key] = TRUE
	log_world("AUXMOS_STACK_TRACE: [key]")
	if(!GLOB.vg_errors_expected)
		stack_trace("Verdigris error in [bind]: [key]")

// === Gas registry rows ===
//
// Rust owns the gas registry (verdigris/domains/gas/src/gate.rs) and each
// gas's id (gas/ids.rs, generated into DM as GAS_ID_* = /datum/gas/var/idx).
// DM hands it only the per-gas data it declares, one row per id in order:
// list(specific_heat, molar_mass, moles_visible). Rust checks the row count
// and each specific heat against its own table.

/proc/build_auxmos_gas_registry()
	var/list/rows = new /list(GAS_ID_COUNT)
	for(var/gp in subtypesof(/datum/gas))
		var/datum/gas/g = gp
		var/gid = initial(g.id)
		if(!gid)
			continue
		rows[initial(g.idx) + 1] = list(initial(g.specific_heat), GLOB.gas_data.molar_mass[gid] || (initial(g.specific_heat) * 0.05), initial(g.moles_visible))
	return rows

// adjust_moles_temp is the one arena mole-accessor gas_mixture.dm doesn't already
// define (get_moles/set_moles/adjust_moles now live there, arena-backed).
/datum/gas_mixture/proc/adjust_moles_temp(gas_type, moles, temp)
	return vg_adjust_moles_temp_hook(src, GAS_IDX(gas_type), moles, temp)

/// Latches the mixture immutable in the arena (one-way; further writes no-op).
/datum/gas_mixture/proc/mark_immutable()
	return vg_mark_immutable_hook(src)

/// Removes all gases from the mixture (arena-side).
/datum/gas_mixture/proc/clear()
	return vg_clear_hook(src)
