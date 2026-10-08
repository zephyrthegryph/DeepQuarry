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
	R.held = A.held_provider() // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
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
/proc/res_spend(datum/holder, resource, n, mob/actor, obj/held, atom/target)
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
	A.set_held_provider(held)
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
/proc/slot_precheck(atom/holder, slot_id, atom/movable/thing, mob/actor)
	if(!holder || QDELETED(holder))
		return /datum/msg/op/target_gone
	var/why = dq_ledger_refusal(thing, holder, slot_id, actor, FALSE)
	return why
