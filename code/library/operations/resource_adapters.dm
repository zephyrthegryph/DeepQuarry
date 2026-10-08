/datum/resource/uses
	res_id = RES_USES
	name = "uses"

/datum/resource/uses/holder_of(datum/act/op/A)
	return A.held

/datum/resource/uses/available(datum/act/op/A)
	var/n = op_var(A.held, "uses")
	return isnum(n) ? n : 0

/datum/resource/uses/commit(datum/reservation/R)
	var/datum/D = R.held
	if(D && ("uses" in D.vars))
		D.vars["uses"] -= R.amount

/// RES_CHARGE: the held item's cell charge, per use.
/datum/resource/charge
	res_id = RES_CHARGE
	name = "charge"

/datum/resource/charge/holder_of(datum/act/op/A)
	return A.held

/datum/resource/charge/available(datum/act/op/A)
	var/atom/movable/AM = A.held
	var/obj/item/cell/C = istype(AM) ? AM.get_cell() : null
	return C ? C.charge : 0

/datum/resource/charge/commit(datum/reservation/R)
	var/atom/movable/AM = R.held
	var/obj/item/cell/C = istype(AM) ? AM.get_cell() : null
	if(!C || !C.use(R.amount))
		return OP_FAILED

/// RES_FUEL: the held tool's fuel (a welder).
/datum/resource/fuel
	res_id = RES_FUEL
	name = "fuel"

/datum/resource/fuel/holder_of(datum/act/op/A)
	return A.held

/datum/resource/fuel/available(datum/act/op/A)
	var/obj/item/weldingtool/W = A.held
	return istype(W) ? W.get_fuel() : 0

/datum/resource/fuel/commit(datum/reservation/R)
	var/obj/item/weldingtool/W = R.held
	if(!istype(W) || !W.remove_fuel(R.amount))
		return OP_FAILED

/// RES_STACK: units of the held stack. reserve sets the units aside. Under a stack(T, n) binding with put_in(), the put splits off exactly those
/// units and moves the split, and the commit consumes nothing further because the split already moved them; without a put_in() the commit deletes
/// the units.
/datum/resource/stack
	res_id = RES_STACK
	name = "stack units"

/datum/resource/stack/holder_of(datum/act/op/A)
	return A.held

/datum/resource/stack/available(datum/act/op/A)
	var/n = op_var(A.held, "amount")
	return isnum(n) ? n : 0

/datum/resource/stack/commit(datum/reservation/R)
	if(R.moved)
		return OP_OK
	var/obj/item/I = R.held
	if(!istype(I) || QDELETED(I))
		return OP_FAILED
	if(istype(I, /obj/item/stack))
		var/obj/item/stack/S = I
		return S.use(R.amount) ? OP_OK : OP_FAILED
	var/amount = op_var(I, "amount")
	if(!isnum(amount) || amount < R.amount)
		return OP_FAILED
	I.vars["amount"] = amount - R.amount // ALLOW(api): a resource adapter spends the var it reads: its own state
	if(I.vars["amount"] <= 0)
		consume(I, R.actor)
	return OP_OK

/// RES_ITEM: the item consumes() takes. reserve claims it, so no other op can use it meanwhile; commit deletes it; release lets it go.
/datum/resource/item
	res_id = RES_ITEM
	name = "item"

/datum/resource/item/holder_of(datum/act/op/A)
	return A.held

/datum/resource/item/available(datum/act/op/A)
	return (A.held && !QDELETED(A.held)) ? 1 : 0

/datum/resource/item/commit(datum/reservation/R)
	var/atom/movable/AM = R.held
	if(istype(AM) && !QDELETED(AM))
		consume(AM, R.actor)

/// RES_COOLDOWN: an op's cooldown(t). reserve checks that the cooldown is ready and claims it; commit starts it; release leaves it ready.
/datum/resource/cooldown
	res_id = RES_COOLDOWN
	name = "cooldown"

/datum/resource/cooldown/holder_of(datum/act/op/A)
	return A.holder

/datum/resource/cooldown/available(datum/act/op/A)
	var/list/ready = A.holder?.rx?.op_cooldowns
	return (isnull(ready?[A.key]) || op_now() >= ready[A.key]) ? 1 : 0

/datum/resource/cooldown/refusal(datum/act/op/A, n)
	return /datum/msg/op/cooling_down

/datum/resource/cooldown/reserve(datum/act/op/A, n)
	return ..(A, 1)

/datum/resource/cooldown/commit(datum/reservation/R)
	var/datum/D = R.holder
	if(!D)
		return OP_FAILED
	var/datum/op_plan/P = op_plan_for(D, R.op_key, list())
	if(!P || isnull(P.cooldown_t))
		return OP_OK
	LAZYSET(rx_of(D).op_cooldowns, R.op_key, op_now() + P.cooldown_t)

/// RES_DARK_ENERGY: the actor's dark energy (phase shift): the var of that name.
/datum/resource/dark_energy
	res_id = RES_DARK_ENERGY
	name = "dark energy"

/datum/resource/dark_energy/available(datum/act/op/A)
	var/n = op_var(A.actor, "dark_energy")
	return isnum(n) ? n : 0

/datum/resource/dark_energy/watch_reads(datum/act/op/A, list/pairs)
	if(A.actor)
		pairs += list(list(A.actor, "dark_energy"))

/datum/resource/dark_energy/commit(datum/reservation/R)
	var/datum/D = R.holder
	if(!D || !("dark_energy" in D.vars))
		return OP_FAILED
	var/new_value = D.vars["dark_energy"] - R.amount
	if(hascall(D, "set_dark_energy"))
		call(D, "set_dark_energy")(new_value)
	else
		D.vars["dark_energy"] = new_value // ALLOW(api): a resource adapter spends the var it reads: its own state

/// RES_BLOOD: the actor's blood volume.
/datum/resource/blood
	res_id = RES_BLOOD
	name = "blood"

/datum/resource/blood/available(datum/act/op/A)
	var/n = op_var(A.actor, "blood_volume")
	return isnum(n) ? n : 0

/datum/resource/blood/commit(datum/reservation/R)
	var/datum/D = R.holder
	if(D && ("blood_volume" in D.vars))
		D.vars["blood_volume"] -= R.amount

/// RES_REAGENTS is the library's adapter: code/library/reagents/reagent_flow.dm (a transfer reserves the source's volume and the target's capacity).

/// RES_SLOT_CAPACITY: a slot's free capacity. An insert reserves it and the move commits it. The slot is `A.target`'s, named by the op's put_in().
/datum/resource/slot_capacity
	res_id = RES_SLOT_CAPACITY
	name = "slot capacity"

/datum/resource/slot_capacity/holder_of(datum/act/op/A)
	return A.target

/datum/resource/slot_capacity/available(datum/act/op/A)
	return 0

/// The reason the units of `n` cannot go into slot `slot_id` of `holder`, or null when they can (the insert action's pre-check).
