/// A turf's gas may react (`GasEvent::CellReactionReady`,
/// verdigris/domains/gas/src/laws.rs): the same `air.react(turf)` the old
/// flat-encoded `GAS_EVENT_REACT` dispatched.
/datum/system/native/on_gas_cell_reaction_ready(cell, reaction)
	SSair.count_gas_event()
	var/turf/open/T = vg_turf_of(cell)
	if(!istype(T))
		return
	SSair.count_gas_reaction()
	native_fired(NATIVE_SRC_GAS_EVENT)
	if(T.air)
		T.air.react(T)

/// A turf's visible gas changed (`GasEvent::CellVisualChange`): the same
/// `set_visuals()` the old `GAS_EVENT_VISUAL` dispatched.
/datum/system/native/on_gas_cell_visual_change(cell, vis)
	SSair.count_gas_event()
	var/turf/open/T = vg_turf_of(cell)
	if(!istype(T))
		return
	SSair.count_gas_visual()
	T.set_visuals()
	native_fired(NATIVE_SRC_GAS_EVENT)

/// Spacewind: `cell`'s pressure differs from open neighbour `neighbor`'s by
/// more than the threshold (`GasEvent::PressureJump`): the same
/// `consider_pressure_difference(other, value)` the old `GAS_EVENT_PRESSURE`
/// dispatched.
/datum/system/native/on_gas_pressure_jump(cell, neighbor, delta)
	SSair.count_gas_event()
	var/turf/open/T = vg_turf_of(cell)
	var/turf/open/other = vg_turf_of(neighbor)
	if(!istype(T) || !istype(other))
		return
	SSair.count_gas_pressure()
	native_fired(NATIVE_SRC_GAS_EVENT)
	T.consider_pressure_difference(other, delta)
