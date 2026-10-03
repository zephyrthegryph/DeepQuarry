// Resource transactions (doc/rewrite/final_api.html, section 9 "Resource transactions (X2)"; section 19 "E2, parts": "the commit contract and
// resource transactions (RESOURCE_DEF, costs(), reservations)").
//
// A resource is something an op takes in discrete amounts. Its ADAPTER knows where the amount lives (the held tool, the actor, the target, a slot)
// and answers five calls:
//
//   holder_of(A)       the entity whose store holds the amount (default: the actor); open reservations are totalled per holder
//   available(A)       how much there is: the raw amount, before reservations
//   reserve(A, n)      sets n aside and returns a /datum/reservation, or null when there is not enough
//   commit(R)          spends the reserved amount: OP_OK (a commit that returns nothing is OP_OK), or OP_FAILED when it cannot
//   release(R)         gives it back
//
// A reservation expires with the op: however the op ends, the engine commits or releases every reservation it holds. The base adapter
// implements reserve and release over available(), keeping the open reservations in the holder's own lazy reservations list, so deleting the
// holder drops them, and what it may set aside is available less that total. Most adapters write only available() and commit().
// Only discrete spends are transactions: continuous draw (power_draw, a heater's load) stays a stat.

/// A reservation: what one op set aside from one holder.
/datum/reservation
	var/res_id
	var/datum/holder
	var/amount = 0
	/// The op's key: a record row names it. (The act itself is pooled and is not kept.)
	var/op_key
	/// The context fields an adapter's commit needs after the act moved on (the held item a stack commit consumes, the actor).
	var/datum/held
	var/datum/actor
	/// TRUE when a put_in() already moved the reserved units (a stack split), so the commit consumes nothing further.
	var/moved = FALSE
	/// Set when the reservation ended (committed or released): a second end is a bug.
	var/ended = FALSE

/datum/rx_state
	/// Open reservations held against this entity (lazy).
	var/list/reservations
	/// op key -> the time the op's cooldown ends.
	var/list/op_cooldowns

/// The registry of adapters: "[RES_X]" -> the singleton.
GLOBAL_LIST_EMPTY(resource_adapters)

/proc/resource_of(res_id)
	RETURN_TYPE(/datum/resource)
	if(!length(GLOB.resource_adapters))
		for(var/adapter_type in subtypesof(/datum/resource))
			var/datum/resource/RS = new adapter_type
			if(!isnull(RS.res_id))
				GLOB.resource_adapters["[RS.res_id]"] = RS
		GLOB.resource_adapters["built"] = TRUE
	return GLOB.resource_adapters["[res_id]"]

/datum/resource
	/// RES_X.
	var/res_id
	var/name = "resource"

/// The entity whose store holds the amount: the actor by default.
/datum/resource/proc/holder_of(datum/act/op/A)
	return A.actor

/// How much there is, before reservations.
/datum/resource/proc/available(datum/act/op/A)
	return 0

/// Sets `n` aside: a reservation, or null when there is not enough.
/datum/resource/proc/reserve(datum/act/op/A, n)
	var/datum/holder = holder_of(A)
	if(!holder || QDELETED(holder))
		return null
	if(available(A) - reserved_total(holder, res_id) < n)
		return null
	var/datum/reservation/R = new
	R.res_id = res_id
	R.holder = holder // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	R.amount = n
	R.op_key = A.key
	R.held = A.held // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	R.actor = A.actor // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	LAZYADD(rx_of(holder).reservations, R)
	return R

/// Spends the reserved amount.
/datum/resource/proc/commit(datum/reservation/R)
	return OP_OK

/// Gives the reserved amount back (nothing was spent).
/datum/resource/proc/release(datum/reservation/R)
	return

/// The (entity, key) reads of the amount, added to `pairs`: a waiting op re-checks when one is published. Default: none (the amount does not publish).
/datum/resource/proc/watch_reads(datum/act/op/A, list/pairs)
	return

/// The reason shown when the reservation could not be made.
/datum/resource/proc/refusal(datum/act/op/A, n)
	return /datum/msg/op/no_resource

/// Total of the open reservations of a resource against a holder.
/proc/reserved_total(datum/holder, res_id)
	. = 0
	for(var/datum/reservation/R as anything in holder.rx?.reservations)
		if(R.res_id == res_id && !R.ended)
			. += R.amount

/// Ends a reservation: removes it from its holder's list. Returns FALSE if it already ended.
/proc/reservation_forget(datum/reservation/R)
	if(R.ended)
		return FALSE
	R.ended = TRUE
	if(R.holder && R.holder.rx?.reservations)
		R.holder.rx.reservations -= R
		if(!length(R.holder.rx.reservations))
			R.holder.rx.reservations = null
	return TRUE

/// Commits a reservation through its adapter: OP_OK or OP_FAILED. Reports to the recorder.
/proc/reservation_commit(datum/reservation/R)
	if(R.ended)
		return OP_OK
	var/datum/resource/RS = resource_of(R.res_id)
	TEST_REC_RESOURCE(TEST_EVENT_COMMIT, R.res_id, R.holder, R.amount, R.op_key)
	var/result = RS ? op_safe_call(RS, "commit", R) : OP_FAILED
	reservation_forget(R)
	return (isnull(result) || result == TRUE) ? OP_OK : result

/// Releases a reservation through its adapter. Reports to the recorder.
/proc/reservation_release(datum/reservation/R)
	if(R.ended)
		return
	var/datum/resource/RS = resource_of(R.res_id)
	TEST_REC_RESOURCE(TEST_EVENT_RELEASE, R.res_id, R.holder, R.amount, R.op_key)
	if(RS)
		RS.release(R)
	reservation_forget(R)

/// res_spend(): code outside an op reserves and commits `n` of `resource` in one call with an explicit context; returns `n`, or 0 when it could not
/// be spent (a reservation is all or nothing). An int resource rounds a fraction up.
/proc/res_spend(datum/holder, resource, n, mob/actor, obj/item/held, atom/target)
	if(!isnum(n) || n <= 0)
		return 0
	n = round(n) == n ? n : round(n) + 1
	var/datum/resource/RS = resource_of(resource)
	if(!RS)
		stack_trace("res_spend(): no adapter for resource [resource]")
		return 0
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder // ALLOW(ownership): a pooled transient: reset on release
	A.actor = actor || (ismob(holder) ? holder : null)
	A.held = held
	A.target = target || holder
	A.key = "res_spend"
	var/datum/reservation/R = RS.reserve(A, n)
	var/spent = 0
	if(R)
		TEST_REC_RESOURCE(TEST_EVENT_RESERVE, resource, R.holder, n, A.key)
		if(reservation_commit(R) == OP_OK)
			spent = n
	A.release()
	return spent

// ---- the adapters ----

/// A var on an entity, by name: null when the entity has none.
/proc/op_var(datum/D, var_name)
	if(D && (var_name in D.vars))
		return D.vars[var_name]
	return null

/// RES_USES: the held item's use count (its `uses` var).
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
/proc/slot_precheck(atom/holder, slot_id, atom/movable/thing, mob/actor)
	if(!holder || QDELETED(holder))
		return /datum/msg/op/target_gone
	var/why = dq_ledger_refusal(thing, holder, slot_id, actor, FALSE)
	return why
