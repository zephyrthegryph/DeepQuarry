// Auxmos init/lifecycle bridge.
//
// The Rust gas-math backend IS live: /datum/gas_mixture is an opaque handle
// over the Rust arena, and every gas proc in gasmixtures/gas_mixture.dm routes
// through the generated vg_* procs (code/__defines/verdigris/_bindings.dm).
// This file carries the gas-registry adapter; the registry
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

// byondapi_stack_trace — auxmos error/panic handler routes back into DM via this
// proc. Log each DISTINCT message once (deduped) to world log so a per-turf error
// flood doesn't drown the log — and so we can actually see the message.
GLOBAL_LIST_EMPTY(auxmos_seen_errors)
/proc/byondapi_stack_trace(msg)
	var/key = "[msg]"
	if(GLOB.auxmos_seen_errors[key])
		return
	GLOB.auxmos_seen_errors[key] = TRUE
	log_world("AUXMOS_STACK_TRACE: [key]")

// === Gas registry adapter ===
//
// auxmos hook_init reads gas_data.datums as an ASSOC list (id -> gas datum). Each
// gas is identified by its type-path TEXT ("/datum/gas/plasma"), which Rust maps
// to the fixed numeric ID in verdigris gas/ids.rs; that ID is generated into DM as
// GAS_ID_* and set as /datum/gas/var/idx. Gas binds then take only numbers.

/// Lightweight metadata datum shaped for auxmos hook_register_gas.
/// NOTE: auxmos reads combustion vars via byond_string!("oxidation_temperature")
/// etc., which PANICS (NonExistentString) if the var-name string was never
/// emitted into the compiled DM. DeepQuarry has no such vars (they're /tg/-isms),
/// so we MUST declare every name auxmos looks up here — even unused ones — so the
/// strings exist. Left null; auxmos then resolves them to FireInfo::None.
/datum/auxmos_gas_meta
	var/id
	/// GAS_ID_* number; Rust checks it against its own table.
	var/idx
	var/name
	var/specific_heat
	var/flags = 0
	var/fusion_power = 0
	var/moles_visible
	// Combustion metadata auxmos hook_register_gas reads (kept null — reactions
	// run in DM, not auxmos; these exist only to satisfy the string lookups).
	var/oxidation_temperature
	var/oxidation_rate
	var/fire_temperature
	var/fire_burn_rate
	var/fire_products
	var/enthalpy
	var/fire_radiation_released

/// Container passed to auxtools_atmos_init; exposes `datums` (assoc id -> meta).
/datum/auxmos_gas_registry
	var/list/datums

/// Build the auxmos gas registry from the /datum/gas roster, keyed by path-text.
/proc/build_auxmos_gas_registry()
	var/datum/auxmos_gas_registry/reg = new
	reg.datums = list()
	for(var/gp in subtypesof(/datum/gas))
		var/datum/gas/g = gp
		var/gid = initial(g.id)
		if(!gid)
			continue
		var/datum/auxmos_gas_meta/m = new
		m.id = "[gp]"                     // "/datum/gas/plasma"
		m.idx = initial(g.idx)
		m.name = "[initial(g.name)]"
		m.specific_heat = initial(g.specific_heat)
		m.fusion_power = initial(g.fusion_power)
		m.moles_visible = initial(g.moles_visible)
		reg.datums["[gp]"] = m
	return reg

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
