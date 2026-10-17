// RES_GAS (doc/rewrite/proposals/transformations.md section 3): moles of gas in the mixture of an op's target. The term adapter of the gas currency:
// a chosen transformation that takes gas (a crafting step at a tank, a recipe at a vent) reserves moles with its other inputs and commits them together.
// A matched gas rule is settled by the native gate and books its heat through gas_react() (code/domains/heat/heat_net.dm); this adapter is for
// ops, where an actor chooses the rule.

/datum/resource/gas
	res_id = RES_GAS
	name = "gas"

/datum/resource/gas/holder_of(datum/act/op/A)
	return A.target

/// The moles in the target's mixture, all species together.
/datum/resource/gas/available(datum/act/op/A)
	var/atom/target = A.target
	var/datum/gas_mixture/air = target?.return_air()
	return air ? air.total_moles() : 0

/// Removes the reserved moles from the mixture, proportionally over its species.
/datum/resource/gas/commit(datum/reservation/R)
	var/atom/source = R.holder
	var/datum/gas_mixture/air = source?.return_air()
	if(!air)
		return OP_FAILED
	var/datum/gas_mixture/removed = air.remove(R.amount)
	if(removed)
		spent(removed)
	return OP_OK
