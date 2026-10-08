// Routes, compartments and affordances (doc/rewrite/dx_conventions.md, "Operations").
//
// A route is how an operation reaches its target: physically (hands on it), through its interface,
// through a UI window, a verb, speech, a mind link or a granted authority (an admin, a console).
// An op says which it accepts (cap_op(via =)); the context says which this attempt used.
//
// A compartment is a named bay of a holder with a boundary. compartment(BAY_INTERIOR, door = CAP_KEY,
// route_gate = req_set(CAP_PANEL_OPEN)) declares it; ops (`at =`) and slots (`at =`) name the bay they work
// through. The boundary answers two things:
//   passes(route, ctx)    whether an operation over `route` gets through to the bay
//   transmission(effect)  the share of a PATH_EFFECT_* (heat, damage, gas, radiation) crossing it;
//                         paths.dm multiplies a slot's share by it when the slot has `at`.
// Affordances live on slot decls: slot.provides is an AFF_* mask of what its holder can do through
// it (a hand: hold, manipulate, hold small, interface). ops_provider() (op_ctx.dm) picks the slot,
// active hand first.

/datum/capability/compartment
	/// BAY_*: the bay this boundary belongs to.
	var/bay
	/// What closes the boundary to the physical route: null (open), CAP_KEY (needs access to the
	/// holder), a number (CAP_* bits that must be set: the cover is open) or a /datum/req.
	var/door
	/// A requirement every route must meet to get through.
	var/datum/req/route_gate
	/// ROUTE_* bits that never get through.
	var/blocked_routes = NONE
	/// Shares (0..1) of each PATH_EFFECT_* that cross.
	var/heat = 1
	var/damage = 1
	var/radiation = 1
	var/gas = TRUE

/// Whether an operation over `route` gets through this boundary. On a refusal ctx.reason says why.
/datum/capability/compartment/proc/passes(route, datum/op_ctx/ctx)
	if(route == ROUTE_AUTHORITY)
		return TRUE
	if(blocked_routes & route)
		ctx.reason = /datum/msg/req_sealed
		return FALSE
	if(route_gate)
		var/why = route_gate.test(ctx)
		if(why)
			ctx.reason = why
			return FALSE
	if(route == ROUTE_PHYSICAL && !isnull(door))
		var/why_door
		if(door == CAP_KEY)
			why_door = req_access().test(ctx)
		else if(isnum(door))
			var/atom/A = ctx.target
			if(!istype(A) || (capability_bits(A) & door) != door)
				why_door = /datum/msg/req_sealed
		else if(istype(door, /datum/req))
			var/datum/req/R = door
			why_door = R.test(ctx)
		if(why_door)
			ctx.reason = why_door
			return FALSE
	return TRUE

/// The share (0..1) of `effect` (PATH_EFFECT_*) that crosses this boundary.
/datum/capability/compartment/proc/transmission(effect)
	switch(effect)
		if(PATH_EFFECT_HEAT)
			return heat
		if(PATH_EFFECT_DAMAGE)
			return damage
		if(PATH_EFFECT_GAS)
			return gas ? 1 : 0
		if(PATH_EFFECT_RADIATION)
			return radiation
	return 1

/// Declares bay `bay` of the holder. door / route_gate / blocked_routes decide what passes(); heat, damage,
/// radiation and gas (TRUE/FALSE) what transmission() answers.
/proc/legacy_compartment(bay, door, datum/req/route_gate, blocked_routes = NONE, heat = 1, damage = 1, radiation = 1, gas = TRUE)
	var/datum/capability/compartment/C = new
	C.bay = bay
	C.door = door
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	C.route_gate = route_gate
	C.blocked_routes = blocked_routes
	C.heat = heat
	C.damage = damage
	C.radiation = radiation
	C.gas = gas
	C.key = "bay:[bay]"
	return C

/// A's compartment for `bay`, or null when it declares none.
/proc/compartment_of(atom/A, bay)
	RETURN_TYPE(/datum/capability/compartment)
	for(var/datum/capability/compartment/C as anything in caps_all(A))
		if(istype(C) && C.bay == bay)
			return C
	return null

/// The share of `effect` a slot of `holder` that sits in a bay lets through that bay's boundary.
/// 1 for a slot with no bay, or a bay the holder never declared (transmission fails open; ops fail closed).
/proc/dq_bay_share(atom/holder, datum/om/relation/slot/def, effect)
	if(!def.at)
		return 1
	var/datum/capability/compartment/C = compartment_of(holder, def.at)
	return C ? C.transmission(effect) : 1
