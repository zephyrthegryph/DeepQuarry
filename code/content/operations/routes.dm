// Routes, compartments and affordances (doc/rewrite/dx_conventions.md, "Operations").
//
// A route is how an operation reaches its target: physically (hands on it), through its interface,
// through a UI window, a verb, speech, a mind link or a granted authority (an admin, a console).
// A context says which route an attempt used.
//
// A compartment is a named bay of a holder with a boundary; slots (`at =`) name the bay they sit in. The boundary
// answers one thing:
//   transmission(effect)  the share of a PATH_EFFECT_* (heat, damage, gas, radiation) crossing it;
//                         paths.dm multiplies a slot's share by it when the slot has `at`.
// Affordances live on slot decls: slot.provides is an AFF_* mask of what its holder can do through it (a hand: hold,
// manipulate, hold small, interface).

/datum/capability/compartment
	/// BAY_*: the bay this boundary belongs to.
	var/bay
	/// Shares (0..1) of each PATH_EFFECT_* that cross.
	var/heat = 1
	var/damage = 1
	var/radiation = 1
	var/gas = TRUE

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

/// A's compartment for `bay`, or null when it declares none.
/proc/compartment_of(atom/A, bay)
	RETURN_TYPE(/datum/capability/compartment)
	for(var/datum/capability/compartment/C as anything in caps_all(A))
		if(istype(C) && C.bay == bay)
			return C
	return null

/// The share of `effect` a slot of `holder` that sits in a bay lets through that bay's boundary.
/// 1 for a slot with no bay, or a bay the holder never declared (transmission fails open; ops fail closed).
/proc/dq_bay_share(atom/holder, datum/relation_definition/slot/def, effect)
	if(!def.at)
		return 1
	var/datum/capability/compartment/C = compartment_of(holder, def.at)
	return C ? C.transmission(effect) : 1
