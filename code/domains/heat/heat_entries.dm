// The heat domain's declarative entries (doc/rewrite/final_api.html, section 14 "Gas and heat"): persistent heat flows declared by the type
// that causes them and integrated by Rust each world step. Each is a scoped activation: at type level under when(...) it exists while the
// condition holds, under while_slotted(..., on = ON_CONTENTS) while the occupant is in the slot, and it ends with its scope. No DM code adds,
// removes or steps a flow.
//
//   heat_link(a, b, conductance, emissivity = 0, area = 0)
//       conduction at `conductance` W/K between two reservoirs, plus radiation εσA(T_a⁴ − T_b⁴) when emissivity and area (m²) are given;
//       integrated exactly (any step length, never past equilibrium)
//   heat_pump(controlled, other, watts, target, mode = HEAT_PUMP_BOTH, resistive = FALSE, carnot_fraction = 0.5, max_cop = 10)
//       drives `controlled` toward `target` K with at most `watts` of electrical work, rejecting heat to (or drawing it from) `other` at a
//       Carnot-bounded COP; resistive heating turns work into heat one for one. Also contributes STAT_POWER_DRAW = watts, so the power the
//       machine is rated for and the heat it moves come from one declaration; heat_entries_power(holder) is what its pumps drew last step.
//   heat_engine(hot, cold, efficiency, conductance)
//       heat flows hot -> cold through `conductance` W/K and `efficiency` of it (capped at Carnot) leaves as electricity:
//       heat_entries_power(holder) is the engine's output, W.
//
// An endpoint is HEAT_HOLDER, HEAT_DECLARER, HEAT_AIR (the declaring side's air), HEAT_HULL (its turf's solid), HEAT_SPACE, or nameof(v): a
// var of the declaring side holding a gas mixture or an atom. A number argument may be nameof(v) too; name it in `reads` (nameof(v) of a tracked
// var) to re-apply when it changes, or call heat_entries_refresh(holder) after writing it.
//
// Examples:
//
//	// a cryo cell: its occupant and its gas exchange heat while it works and they are inside
//	when(STAT_OPERABLE, while_slotted(OCCUPANT_SLOT_CRYO, heat_link(HEAT_HOLDER, nameof(air_contents), CRYO_OCCUPANT_CONDUCTANCE), on = ON_CONTENTS))
//	// a space heater: a heat pump on the room's air, rejecting into the floor
//	when(nameof(on), heat_pump(HEAT_AIR, HEAT_HULL, nameof(heating_power), nameof(set_temperature)))
//	// a heat-exchange pipe radiating to space
//	when(nameof(exposed_to_space), heat_link(nameof(air_temporary), HEAT_SPACE, 0, emissivity = 0.9, area = nameof(surface)))
//	// a thermoelectric generator between its hot and cold loops
//	when(STAT_OPERABLE, heat_engine(nameof(air1), nameof(air2), TEG_EFFICIENCY, TEG_CONDUCTANCE))

/proc/heat_link(a, b, conductance, emissivity = 0, area = 0, list/reads = null, key = null)
	return entry_make("heat_edge", key, list("edge" = HEAT_EDGE_LINK, "a" = a, "b" = b, "p1" = conductance, "p2" = emissivity, "p3" = area, "reads" = reads))

/proc/heat_pump(controlled, other, watts, target, mode = HEAT_PUMP_BOTH, resistive = FALSE, carnot_fraction = 0.5, max_cop = 10, list/reads = null, key = null, power_draw = TRUE)
	var/datum/entry/pump = entry_make("heat_edge", key, list("edge" = HEAT_EDGE_PUMP, "a" = controlled, "b" = other, "p1" = watts, "p2" = target, "p3" = mode, "p4" = resistive, "p5" = carnot_fraction, "p6" = max_cop, "reads" = reads))
	// A machine's pump is part of its power draw; something that is not a machine (an exosuit) pays from its own cell and says power_draw = FALSE.
	return power_draw ? list(pump, contributes(STAT_POWER_DRAW, watts)) : pump

/proc/heat_engine(hot, cold, efficiency, conductance, list/reads = null, key = null)
	return entry_make("heat_edge", key, list("edge" = HEAT_EDGE_ENGINE, "a" = hot, "b" = cold, "p1" = efficiency, "p2" = conductance, "reads" = reads))

/// One live edge an entry made.
/datum/heat_edge_record
	/// The Rust edge id.
	var/id
	var/datum/activation/activation
	var/datum/entry/entry
	/// The declaring side, when an endpoint follows where it is (HEAT_AIR, HEAT_HULL): re-made when it moves.
	var/atom/movable/follows

/// "activation serial:entry sig" -> /datum/heat_edge_record.
GLOBAL_LIST_EMPTY(heat_entry_edges)

/datum/entry_engine/heat_edge
	kind = "heat_edge"
	cond_scoped = TRUE

/datum/entry_engine/heat_edge/validate(datum/activation/A, datum/entry/E)
	for(var/end in list(E.args["a"], E.args["b"]))
		if(!istext(end) || !length(end))
			return "a heat entry's endpoint is HEAT_HOLDER, HEAT_DECLARER, HEAT_AIR, HEAT_HULL, HEAT_SPACE or nameof(v), got [end]"
	return null

/// An entry whose endpoint holds no heat yet (a pipe machine before its ports bind, a var not set yet) is kept and made by
/// heat_entries_refresh(), which the pipe machines call when their ports bind.
/datum/entry_engine/heat_edge/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	var/datum/heat_edge_record/R = new
	R.activation = A // ALLOW(ownership): an engine record the heat entry engine owns and drops in remove()
	R.entry = E // ALLOW(ownership): the interned entry this record was made for, a flyweight
	heat_entry_make(R)
	GLOB.heat_entry_edges["[A.serial]:[E.sig]"] = R
	heat_records_add(GLOB.heat_edge_records_of, heat_entry_declarer(A), R)
	return TRUE

/datum/entry_engine/heat_edge/remove(datum/activation/A, datum/entry/E)
	var/datum/heat_edge_record/R = GLOB.heat_entry_edges["[A.serial]:[E.sig]"]
	if(!R)
		return
	GLOB.heat_entry_edges -= "[A.serial]:[E.sig]"
	heat_entry_unmake(R)
	heat_records_remove(GLOB.heat_edge_records_of, heat_entry_declarer(A), R)

/// The side that declares an activation's entries: the container of a slotted one, else the holder.
/proc/heat_entry_declarer(datum/activation/A)
	return (A.scope == SCOPE_SLOT && isdatum(A.source)) ? A.source : A.holder

/// An entry argument's value: a constant, or nameof(v) of the declaring side.
/proc/heat_entry_value(datum/declarer, spec, default = 0)
	if(istext(spec) && (spec in declarer.vars))
		spec = declarer.vars[spec]
	return isnum(spec) ? spec : default

/// An endpoint of an entry as a reservoir: list(HEAT_TARGET_*, ref), or null.
/proc/heat_entry_end(datum/activation/A, spec)
	var/datum/declarer = heat_entry_declarer(A)
	switch(spec)
		if(HEAT_HOLDER)
			return heat_reservoir_of(A.holder)
		if(HEAT_DECLARER)
			return heat_reservoir_of(declarer)
		if(HEAT_SPACE)
			return heat_reservoir_of(HEAT_SPACE)
		if(HEAT_AIR)
			var/turf/T = isatom(declarer) ? get_turf(declarer) : null
			return T ? heat_reservoir_of(T) : null
		if(HEAT_HULL)
			var/turf/T = isatom(declarer) ? get_turf(declarer) : null
			return T ? list(HEAT_TARGET_SOLID, T) : null
		if(HEAT_AMBIENT)
			return list(HEAT_TARGET_SPACE, T20C)
	if(istext(spec) && findtext(spec, "heat:port:") == 1)
		var/obj/machinery/atmospherics/machine = declarer
		var/index = text2num(copytext(spec, 11))
		if(!istype(machine) || index > length(machine.rust_pipe_port_ids) || !machine.rust_pipe_port_ids[index])
			return null
		return list(HEAT_TARGET_PIPE_PORT, machine.rust_pipe_port_ids[index])
	if(istext(spec) && findtext(spec, "heat:sky:") == 1)
		return list(HEAT_TARGET_SPACE, text2num(copytext(spec, 10)))
	if(istext(spec) && (spec in declarer.vars))
		return heat_reservoir_of(declarer.vars[spec])
	return null

/// Creates the Rust edge of a record. FALSE when an endpoint holds no heat (no gas yet, nowhere to be).
/proc/heat_entry_make(datum/heat_edge_record/R)
	var/datum/activation/A = R.activation
	var/datum/entry/E = R.entry
	var/list/a = heat_entry_end(A, E.args["a"])
	var/list/b = heat_entry_end(A, E.args["b"])
	if(!a || !b)
		return FALSE
	var/datum/declarer = heat_entry_declarer(A)
	switch(E.args["edge"])
		if(HEAT_EDGE_LINK)
			R.id = vg_heat_link_create(a[1], a[2], b[1], b[2], heat_entry_value(declarer, E.args["p1"]), heat_entry_value(declarer, E.args["p2"]), heat_entry_value(declarer, E.args["p3"]))
		if(HEAT_EDGE_PUMP)
			R.id = vg_heat_pump_create(a[1], a[2], b[1], b[2], heat_entry_value(declarer, E.args["p1"]), heat_entry_value(declarer, E.args["p2"], T20C), \
				heat_entry_value(declarer, E.args["p3"], HEAT_PUMP_BOTH), heat_entry_value(declarer, E.args["p4"]), heat_entry_value(declarer, E.args["p5"], 0.5), \
				heat_entry_value(declarer, E.args["p6"], 10))
		if(HEAT_EDGE_ENGINE)
			R.id = vg_heat_engine_create(a[1], a[2], b[1], b[2], heat_entry_value(declarer, E.args["p1"]), heat_entry_value(declarer, E.args["p2"]))
	if(!R.id)
		return FALSE
	// A heat body an edge names is kept while it does (it never settles away under a live flow).
	for(var/list/end in list(a, b))
		if(end[1] == HEAT_TARGET_BODY)
			vg_heat_body_keep(end[2], TRUE)
	if((E.args["a"] in list(HEAT_AIR, HEAT_HULL)) || (E.args["b"] in list(HEAT_AIR, HEAT_HULL)))
		if(ismovable(declarer))
			R.follows = declarer // ALLOW(ownership): a weak back-reference the record clears in heat_entry_unmake()
			heat_records_add(GLOB.heat_followers_of, declarer, R)
	return TRUE

/// Removes the Rust edge of a record.
/proc/heat_entry_unmake(datum/heat_edge_record/R)
	if(R.id)
		vg_heat_edge_remove(R.id)
		R.id = null
	if(R.follows)
		heat_records_remove(GLOB.heat_followers_of, R.follows, R)
		R.follows = null // ALLOW(ownership): clearing the record's weak back-reference

/// Declarer -> the records of the edges whose endpoint follows where it is (HEAT_AIR, HEAT_HULL of a machine that can be moved).
GLOBAL_LIST_EMPTY(heat_followers_of)
/// Declarer -> the records of the heat edges it declares (heat_entries_refresh(), heat_entries_bill()).
GLOBAL_LIST_EMPTY(heat_edge_records_of)

/proc/heat_records_add(list/index, datum/key, datum/heat_edge_record/R)
	if(!key)
		return
	var/list/records = index[key]
	if(!records)
		records = list()
		index[key] = records
	records += R

/proc/heat_records_remove(list/index, datum/key, datum/heat_edge_record/R)
	var/list/records = key ? index[key] : null
	if(!records)
		return
	records -= R
	if(!length(records))
		index -= key

/// A movable moved: the edges that name its air or its hull are re-made on the new turf.
/proc/heat_followers_moved(atom/movable/M)
	var/list/records = GLOB.heat_followers_of[M]
	for(var/datum/heat_edge_record/R as anything in records?.Copy())
		heat_entry_unmake(R)
		heat_entry_make(R)

/// Re-makes the holder's heat edges with the current values of what they read: after a var a heat entry reads changed without a
/// tracked setter, or once an endpoint exists (a pipe machine's ports bound).
/proc/heat_entries_refresh(atom/holder)
	for(var/datum/heat_edge_record/R as anything in GLOB.heat_edge_records_of[holder])
		heat_entry_unmake(R)
		heat_entry_make(R)

/// Makes the holder's heat edges that could not be made yet (an endpoint did not exist).
/proc/heat_entries_complete(atom/holder)
	for(var/datum/heat_edge_record/R as anything in GLOB.heat_edge_records_of[holder])
		if(!R.id)
			heat_entry_make(R)

/// The electrical power of the holder's live heat edges last step, W: positive for engines' output, negative for pumps' draw.
/proc/heat_entries_power(atom/holder)
	. = 0
	for(var/datum/heat_edge_record/R as anything in GLOB.heat_edge_records_of[holder])
		if(R.id)
			. += heat_edge_power(R.id)

/// The electrical energy the holder's heat edges exchanged since it last asked, J: what its pumps drew (positive) less what its
/// engines made, exactly as Rust booked it. A machine pays it from its cell or its grid, so the power it pays and the heat it moves agree.
/proc/heat_entries_bill(atom/holder)
	. = 0
	for(var/datum/heat_edge_record/R as anything in GLOB.heat_edge_records_of[holder])
		if(R.id)
			. += vg_heat_edge_take_work(R.id) || 0

/// The live heat edge ids the holder declares, or is the holder of (a slotted occupant) (tests, tooling).
/proc/heat_entries_of(datum/holder)
	. = list()
	for(var/key in GLOB.heat_entry_edges)
		var/datum/heat_edge_record/R = GLOB.heat_entry_edges[key]
		var/datum/activation/act = R.activation
		if(R.id && (heat_entry_declarer(act) == holder || act.holder == holder))
			. += R.id
