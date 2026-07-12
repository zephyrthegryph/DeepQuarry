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


// === Phase 1: gas registry + reaction init ===
//
// Auxmos keeps its own Rust-side gas registry (specific heats, fire info, and a
// parsed reaction table). It must be populated at SSair init before any gas-op
// FFI call in later phases. auxtools_atmos_init(holder) iterates holder.datums,
// registers each gas (reading id/specific_heat/fire fields off the instance),
// then reads SSair.gas_reactions to build the Rust reaction cache.
//
// Gas math still runs in DM at this phase — this only makes the Rust backend
// *ready* for the arena cutover (Phase 2+). It is safe to run standalone.

/// Populate auxmos's Rust gas registry from the DM gas roster.
///
/// We register each gas individually via _auxtools_register_gas(), which reads
/// id/specific_heat/fire fields off a live gas instance and returns a Result
/// (a bad field surfaces as a DM runtime, not a crash).
///
/// We deliberately do NOT call auxtools_atmos_init() here yet. That entry point
/// also parses SSair.gas_reactions into auxmos's Rust reaction table, and this
/// fork keeps the CHOMP/XGM reaction roster (doc/atmos_migration.md Q6), whose
/// datum shape doesn't match auxmos's Reaction parser. auxmos's byondapi binds
/// are not wrapped in panic_safe! (doc §1.1c "What 1.1c did NOT do"), so a fault
/// in that path takes down DreamDaemon natively with no catchable runtime —
/// which is exactly what wiring it up produced. Reaction registration is
/// deferred until the auxmos binds are panic-hardened and the reaction contract
/// is adapted (Phase 2+). Gases-only registration is enough for the arena
/// cutover to begin.
///
/// Returns the number of gases registered, or FALSE if verdigris isn't loaded /
/// the backend is gated off.
///
/// BLOCKED — the FFI registration loop is gated behind AUXMOS_GAS_BACKEND
/// (undefined by default) because it crashes DreamDaemon natively today:
///
///   auxmos allocates its gas registry + mixture arena in four
///   `#[byondapi::init]` functions (verdigris/atmos/src/{lib,gas,gas/types,
///   turfs}.rs). When auxmos is force-linked into verdigris as an rlib
///   (`use auxmos as _;`), only its `#[byondapi::bind]` FFI symbols are pulled
///   in — the linker drops the init-slice entries, so those init fns never run.
///   Every bind then does `.unwrap()` on a still-`None` static, panics, and —
///   because auxmos's binds are NOT wrapped in panic_safe! (doc §1.1c) — the
///   panic unwinds through the C ABI and kills the process with no DM runtime.
///   The very first `_auxtools_register_gas()` call is enough to crash boot.
///
/// Unblocking is Rust work in verdigris (no DM change fixes it):
///   1. Ensure auxmos's `#[byondapi::init]` fns actually link + run in the
///      combined library (force-reference them, or invoke them from
///      verdigris_init()), so the registry/arena statics are `Some`.
///   2. Wrap the auxmos binds in panic_safe! so a fault is a DM runtime, not a
///      native crash — required before any atmos hot-path call is safe.
///   3. Rebuild verdigris.dll, then define AUXMOS_GAS_BACKEND and re-test.
/datum/controller/subsystem/air/proc/init_auxmos_backend()
	var/version = verdigris_version()
	if(!version)
		log_world("auxmos: verdigris backend not loaded; gas registry stays DM-only")
		return FALSE
#ifdef AUXMOS_GAS_BACKEND
	var/registered = 0
	for(var/gas_path in subtypesof(/datum/gas))
		var/datum/gas/gas = new gas_path
		_auxtools_register_gas(gas)
		registered++
	log_world("auxmos: registered [registered] gases with the Rust backend (verdigris [version]); reactions deferred")
	return registered
#else
	log_world("auxmos: Rust gas backend gated off (AUXMOS_GAS_BACKEND undefined); gas math stays DM. See auxmos_init_bridge.dm for the Rust init blocker.")
	return FALSE
#endif
