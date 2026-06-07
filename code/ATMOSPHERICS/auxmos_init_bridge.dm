// Auxmos init/lifecycle bridge.
//
// auxmos_bindings.dm has the full call_ext routes for every gas_mixture proc,
// but including it would re-declare procs already defined in /tg/'s vendored
// gas_mixture.dm. Instead, byondapi's runtime-swap (#[byondapi::bind]) replaces
// those proc bodies at DLL-load time — so the DM-side declarations from
// gas_mixture.dm are kept, and the call_ext routes are not needed for them.
//
// What IS needed: the small set of init/lifecycle FREE procs that aren't on
// gas_mixture. We declare them here as thin call_ext stubs so SSair.Initialize
// can hand gas metadata to the Rust side at boot.
//
// DO NOT add proc declarations that conflict with gas_mixture.dm here.
// Generation source: verdigris/atmos/bindings.dm (selected procs only).


/// Registers gases, and get reaction infos for auxmos, only call when ssair is initing.
/proc/auxtools_atmos_init(gas_data)
	return call_ext(VERDIGRIS, "byond:hook_init_ffi")(gas_data)

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

// byondapi_stack_trace — auxmos panic handler routes back into DM via this proc.
// Logging-only; do not raise.
/proc/byondapi_stack_trace(msg)
	stack_trace("[msg]")


// === auxmos-only gas_mixture procs ===
//
// /tg/'s gas_mixture.dm doesn't declare these — they live ONLY in auxmos's
// byondapi bindings. The DM-side declarations below are required so byondapi
// has a target proc to swap at DLL load. CHOMP/DQ code uses these for
// Rust-state-aware reads/writes — `adjust_gas` from gas_mixture.dm only
// mutates the DM dict and is invisible to the Rust-backed total_moles/pressure.
//
// USE THESE for any read/write that needs to round-trip through Rust:
//   - get_moles(gas_type) — current moles
//   - set_moles(gas_type, value) — overwrite moles
//   - adjust_moles(gas_type, delta) — add to moles
//   - adjust_moles_temp(gas_type, moles, temp) — add moles at temp
//   - set_temperature(value) — set temperature
//   - merge(other) — combine moles + temperature from `other`

/datum/gas_mixture/proc/get_moles(gas_type)
	// Body is replaced at DLL load by auxmos byondapi bind.
	// Fallback: read DM dict if Rust isn't loaded.
	return gases[gas_type] ? gases[gas_type][MOLES] : 0

/datum/gas_mixture/proc/set_moles(gas_type, amount)
	ASSERT_GAS(gas_type, src)
	gases[gas_type][MOLES] = amount

/datum/gas_mixture/proc/adjust_moles(gas_type, delta)
	ASSERT_GAS(gas_type, src)
	gases[gas_type][MOLES] += delta

/datum/gas_mixture/proc/adjust_moles_temp(gas_type, moles, temp)
	ASSERT_GAS(gas_type, src)
	gases[gas_type][MOLES] += moles
	if(temperature > 0 && moles > 0)
		temperature = (temperature * total_moles() + temp * moles) / max(total_moles() + moles, 1)
