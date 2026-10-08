/datum/entry/part/effect/fixes/run_effect(datum/act/op/A)
	var/obj/O = A.holder
	if(istype(O) && O.max_integrity)
		O.repair_damage(O.max_integrity)
	return OP_OK

/datum/entry/part/effect/becomes/run_effect(datum/act/op/A)
	var/atom/movable/AM = A.holder
	if(!istype(AM))
		return OP_FAILED
	return replace_with(AM, src.args["type"]) ? OP_OK : OP_FAILED

/datum/entry/part/effect/spawns/run_effect(datum/act/op/A)
	var/atom/where = A.holder
	if(!istype(where))
		return OP_FAILED
	var/spawn_path = src.args["type"]
	if(ispath(spawn_path, /obj/item/stack)) // a stack spawns as one pile of n
		new spawn_path(get_turf(where), src.args["n"])
		return OP_OK
	for(var/i in 1 to src.args["n"])
		new spawn_path(get_turf(where))
	return OP_OK

/datum/entry/part/effect/opens_ui/run_effect(datum/act/op/A)
	var/datum/D = A.holder
	if(!D || !A.actor)
		return OP_FAILED
	D.tgui_interact(A.actor)
	return OP_OK

// ---- put_in / take_out ----

/datum/entry/part/effect/put_in/precheck(datum/act/op/A)
	var/obj/item/thing = A.held
	if(!thing)
		return null
	if(istype(A.target, /atom) && op_var_slot(A.target, src.args["slot"]))
		return varslot_refusal(A.target, src.args["slot"], thing, A.actor)
	var/why = slot_precheck(A.target, src.args["slot"], thing, A.actor)
	return why || op_insert_precheck(A.target, thing, src.args["slot"])

/datum/entry/part/effect/put_in/run_effect(datum/act/op/A)
	return op_transport_insert(A, src.args["slot"], A.reservations)

/// Guarded slot transport after put_in/precheck() has run. Hooks or the insertion itself may still refuse or replace the world action;
/// preserve their result and return any split units when the transport fails.
/proc/op_transport_insert(datum/act/action/A, slot_id, list/reservations)
	var/atom/holder = A.target
	var/obj/item/thing = A.held
	if(!thing || !istype(holder))
		return OP_FAILED
	// A one-item slot over a var of the holder (a cell bay): the item goes into the holder and the var names it.
	if(op_var_slot(holder, slot_id))
		var/var_why = varslot_refusal(holder, slot_id, thing, A.actor)
		if(var_why)
			A.reason = var_why
			return OP_REFUSED
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
		var/atom/var_from = thing.loc
#endif
		if(!varslot_insert(holder, slot_id, thing, A.actor))
			A.reason = /datum/msg/op/failed
			return OP_REFUSED
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
		if(rel_kind(holder, slot_id) != OWNK_OWN) // a declared owned var moved through move_into(), which recorded the row already
			TEST_REC_TRANSFER(thing, var_from, holder, slot_id)
#endif
		return OP_OK
	// Under a stack(T, n) binding the put splits off exactly the reserved units and moves that split.
	var/atom/movable/moving = thing
	var/datum/reservation/stack_units = null
	for(var/datum/reservation/R as anything in reservations)
		if(R.res_id == RES_STACK && R.held == thing)
			stack_units = R
	if(stack_units)
		var/obj/item/split = op_split_units(thing, stack_units.amount)
		if(!split)
			return OP_FAILED
		moving = split
	var/why = slot_precheck(holder, slot_id, moving, A.actor)
	if(why)
		A.reason = why
		if(moving != thing)
			op_merge_units(thing, moving)
		return OP_REFUSED
	// The insert is a world action: its hooks may refuse it or take it over, and its notice goes out when it lands. move_into() runs it.
	if(!move_into(holder, slot_id, moving, A.actor))
		if(moving != thing)
			op_merge_units(thing, moving)
		A.reason = GLOB.act_last_reason || /datum/msg/op/not_available
		return (GLOB.act_last_outcome & ACT_REPLACED) ? OP_REPLACED : OP_REFUSED
	if(stack_units)
		stack_units.moved = TRUE
	return OP_OK

/datum/entry/part/effect/take_out/precheck(datum/act/op/A)
	return null

/datum/entry/part/effect/take_out/run_effect(datum/act/op/A)
	var/atom/holder = A.target
	if(!istype(holder))
		return OP_FAILED
	var/slot_id = src.args["slot"]
	var/obj/item/carrier = op_carrier(A)
	if(op_var_slot(holder, slot_id))
		var/atom/movable/taken = varslot_take(holder, slot_id, A.actor, carrier)
		if(!taken)
			return OP_REFUSED
		TEST_REC_TRANSFER(taken, holder, taken.loc, slot_id)
		return OP_OK
	var/list/inside = holder.slot_contents(slot_id)
	if(!length(inside))
		return OP_REFUSED
	var/atom/movable/thing = inside[1]
	var/atom/destination = get_turf(A.actor || holder)
	var/carried = carrier && istype(thing, /obj/item) && carrier.can_carry(thing, A.actor)
	if(!carried && A.actor && istype(thing, /obj/item))
		var/obj/item/I = thing
		if(!A.actor.put_in_hands(I))
			destination = get_turf(A.actor)
		else
			TEST_REC_TRANSFER(thing, holder, A.actor, slot_id)
			return OP_OK
	if(!holder.slot_remove(thing, destination, A.actor))
		return OP_FAILED
	if(carried && carrier.carry(thing, A.actor)) // out of the slot onto the floor, then into the carrier (a gripper's pocket)
		destination = carrier
	TEST_REC_TRANSFER(thing, holder, destination, slot_id)
	return OP_OK

/// The provider of an op that carries what it takes (a cyborg's gripper, not the actor's own hand), or null.
/proc/op_carrier(datum/act/op/A)
	var/obj/item/carrier = A.provider
	if(!istype(carrier) || carrier == A.held)
		return null
	return carrier

/// Where something an op took out goes: into the provider that carries it (a gripper), else the actor's hands, else the actor's floor. TRUE
/// when it reached the carrier or a hand.
/proc/op_deliver(datum/act/op/A, obj/item/thing)
	var/obj/item/carrier = op_carrier(A)
	if(carrier && carrier.can_carry(thing, A.actor) && carrier.carry(thing, A.actor))
		return TRUE
	if(A.actor && A.actor.put_in_hands(thing))
		return TRUE
	thing.forceMove(get_turf(A.actor || A.target_atom))
	return FALSE

/// Splits `n` units off a stack item into a new item (the original keeps the rest).
/proc/op_split_units(obj/item/I, n)
	RETURN_TYPE(/obj/item)
	if(istype(I, /obj/item/stack))
		var/obj/item/stack/S = I
		return S.split(n)
	var/amount = op_var(I, "amount")
	if(!isnum(amount) || amount < n)
		return null
	if(amount == n)
		return I
	var/obj/item/clone = new I.type(null)
	clone.vars["amount"] = n // ALLOW(api): units moved between two items of one type: the engine's own bookkeeping
	I.vars["amount"] = amount - n // ALLOW(api): units moved between two items of one type: the engine's own bookkeeping
	return clone

/// Puts a split's units back (an insert that was refused after the split).
/proc/op_merge_units(obj/item/original, obj/item/split)
	if(original == split)
		return
	if(istype(original, /obj/item/stack) && istype(split, /obj/item/stack))
		var/obj/item/stack/S = original
		S.add(split.vars["amount"])
		qdel(split) // ALLOW(lifecycle): a split of a stack made inside an op and never placed in the world: it holds nothing to unlink
		return
	var/amount = op_var(original, "amount")
	if(isnum(amount))
		original.vars["amount"] = amount + split.vars["amount"] // ALLOW(api): units moved between two items of one type: the engine's own bookkeeping
	qdel(split) // ALLOW(lifecycle): a split of a stack made inside an op and never placed in the world: it holds nothing to unlink
