// Auxmos init/lifecycle bridge.
//
// auxmos_bindings.dm has the full call_ext routes for every gas_mixture proc,
// but including it would re-declare procs already defined in /tg/'s vendored
// gas_mixture.dm (a duplicate-definition compile error).
//
// IMPORTANT — the gas-math backend is NOT live. byondapi does NOT transparently
// swap DM proc bodies at DLL load (that was auxtools' detour hooking; byondapi is
// pull-based — a #[byondapi::bind] only exports an FFI symbol reachable via
// call_ext). So the pure-DM bodies in gas_mixture.dm are what actually run today;
// gas math is NOT routed through Rust. Making it Rust-backed requires REPLACING
// those DM bodies with the call_ext routes from auxmos_bindings.dm AND adopting
// auxmos' Rust gas-arena data model (mixtures live in Rust, the DM datum is a
// handle) — a core re-architecture, not a drop-in. See doc/atmos_migration.md.
//
// What this bridge DOES provide: the small set of init/lifecycle FREE procs
// (auxtools_atmos_init etc.) declared as thin call_ext stubs. These are wired
// targets but auxtools_atmos_init() is still not CALLED from SSair, so the Rust
// gas registry is currently unpopulated (see SSair.Initialize).
//
// DO NOT add proc declarations that conflict with gas_mixture.dm here.
// Generation source: verdigris/atmos/bindings.dm (selected procs only).


/// Registers gases, and get reaction infos for auxmos, only call when ssair is initing.
/proc/auxtools_atmos_init(gas_data)
	return call_ext(VERDIGRIS, "byond:hook_init_ffi")(gas_data)

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
	GLOB.auxmos_gas_registry_initialized = TRUE
	auxtools_atmos_init(build_auxmos_gas_registry())

/// For registering gases, do not touch this.
/proc/_auxtools_register_gas(gas)
	return call_ext(VERDIGRIS, "byond:hook_register_gas_ffi")(gas)

/// For updating reagent gas fire products, do not use for now.
/proc/finalize_gas_refs()
	return call_ext(VERDIGRIS, "byond:finalize_gas_refs_ffi")()

/// Args: (ms). Runs callbacks until time limit is reached. If time limit is omitted, runs all callbacks.
/proc/process_atmos_callbacks(remaining)
	return call_ext(VERDIGRIS, "byond:atmos_callback_handle_ffi")(remaining)

/// For updating reaction information for auxmos, call after gas_reactions list changes.
/datum/controller/subsystem/air/proc/auxtools_update_reactions()
	return call_ext(VERDIGRIS, "byond:update_reactions_ffi")()

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


// === Gas registry adapter (chunk 2) ===
//
// auxmos hook_init reads gas_data.datums as an ASSOC list (id -> gas datum) and
// registers each by the `id` string it reads. DeepQuarry's LINDA identifies
// gases by /datum/gas TYPE PATHS (gases[] keys, caller args) — so we register
// each gas under its type-path TEXT ("/datum/gas/plasma"). DM gas_mixture
// wrappers then pass the arg stringified ("[gas_type]") and auxmos resolves it
// via get_string. See doc/auxmos_wiring_plan.md.

/// Lightweight metadata datum shaped for auxmos hook_register_gas.
/// NOTE: auxmos reads combustion vars via byond_string!("oxidation_temperature")
/// etc., which PANICS (NonExistentString) if the var-name string was never
/// emitted into the compiled DM. DeepQuarry has no such vars (they're /tg/-isms),
/// so we MUST declare every name auxmos looks up here — even unused ones — so the
/// strings exist. Left null; auxmos then resolves them to FireInfo::None.
/datum/auxmos_gas_meta
	var/id
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
		m.name = "[initial(g.name)]"
		m.specific_heat = initial(g.specific_heat)
		m.fusion_power = initial(g.fusion_power)
		m.moles_visible = initial(g.moles_visible)
		reg.datums["[gp]"] = m
	return reg


// adjust_moles_temp is the one arena mole-accessor gas_mixture.dm doesn't already
// define (get_moles/set_moles/adjust_moles now live there, arena-backed). Route it
// through the auxmos bind and refresh the temperature mirror. Gas arg stringified
// per the get_strid contract.
/datum/gas_mixture/proc/adjust_moles_temp(gas_type, moles, temp)
	. = call_ext(VERDIGRIS, "byond:adjust_moles_temp_hook_ffi")(src, "[gas_type]", moles, temp)
	temperature = return_temperature()

/// Latches the mixture immutable in the arena (one-way; further writes no-op).
/datum/gas_mixture/proc/mark_immutable()
	return call_ext(VERDIGRIS, "byond:mark_immutable_hook_ffi")(src)

/// Removes all gases from the mixture (arena-side).
/datum/gas_mixture/proc/clear()
	return call_ext(VERDIGRIS, "byond:clear_hook_ffi")(src)
