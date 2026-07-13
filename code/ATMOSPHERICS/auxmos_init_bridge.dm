// Auxmos init/lifecycle bridge.
//
// auxmos_bindings.dm has the full call_ext routes for every gas_mixture proc
// and all the init/lifecycle free procs. This file provides only the
// DM-side subsystem proc that bootstraps the Rust gas registry at SSair init,
// which is not part of the auto-generated bindings file.
//
// DO NOT re-declare procs that auxmos_bindings.dm already defines here.
// Generation source: verdigris/atmos/bindings.dm (selected procs only).


/// Register the DM gas roster with auxmos's Rust gas registry.
///
/// This MUST run before any gas mixture is populated. Turf air is created and
/// filled during SSatoms init, and `set_moles(gas)` on a gas auxmos hasn't been
/// told about indexes past the (empty) Rust gas table via an unchecked access
/// and segfaults the process. So this is called from /world/New — before the
/// Master Controller starts any subsystem — not from SSair.Initialize.
/// Idempotent: `_auxtools_register_gas` updates an existing entry in place.
/proc/auxmos_register_gases()
	if(!verdigris_version())
		log_world("auxmos: verdigris backend not loaded; gas math stays DM-only")
		return FALSE
	var/registered = 0
	for(var/gas_path in subtypesof(/datum/gas))
		var/datum/gas/gas = new gas_path
		_auxtools_register_gas(gas)
		registered++
	log_world("auxmos: registered [registered] gases with the Rust backend (verdigris [verdigris_version()])")
	return registered

/// Build auxmos's Rust reaction table from SSair.gas_reactions. Runs at SSair
/// init (gases are already registered by auxmos_register_gases in /world/New,
/// and SSair.gas_reactions is populated by now). Every gas_mixture/react() is a
/// Rust bind that reads this table; reactions that don't fit auxmos's parser are
/// logged and skipped (non-fatal), leaving the table with whatever parsed.
/datum/controller/subsystem/air/proc/init_auxmos_backend()
	if(!verdigris_version())
		return FALSE
	auxtools_update_reactions()
	log_world("auxmos: reaction table registered with the Rust backend")
	return TRUE
