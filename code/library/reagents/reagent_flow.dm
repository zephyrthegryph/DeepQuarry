// RES_REAGENTS (doc/rewrite/final_api.html, section 9 "Resource transactions (X2)"; section 16.5): a reagent transfer is one reservation on the
// source's volume and one reservation of capacity on the sink, committed together. A full sink refuses before anything leaves the source, and an
// op that ends any other way releases both, so neither end is ever half moved.
//
// Which entity is the source and which the sink is the capability's answer: its `flow_of(datum/act/op/A)` returns list(source, sink, mode)
// (mode is a REAGENT_FLOW_* value). A capability that owns reagent ops without the reagent_container library (a tank, a vending machine) gives its
// own `flow_of`; with none, the held item is the source and the target the sink.

/// Mode of a flow: the source's reagents move into the sink's holder.
#define REAGENT_FLOW_TRANSFER 1
/// Mode of a flow: the reagents are splashed over the target (a mob, a turf, an object): no capacity is reserved, and they touch what they land on.
#define REAGENT_FLOW_SPLASH 2

/// A reservation of reagents: the source side carries the sink's capacity reservation as its peer, so the one the engine tracks ends both.
/datum/reservation/reagents
	/// The sink of a transfer (or the thing splashed).
	var/atom/sink
	var/flow_mode = REAGENT_FLOW_TRANSFER
	/// The capacity reserved on the sink, ended with this reservation.
	var/datum/reservation/reagents/peer
	/// TRUE for the sink-side record: it holds capacity, not volume.
	var/capacity_hold = FALSE

/// The (source, sink, mode) an act's reagent op moves: the capability's flow_of(), else the held item into the target.
/proc/reagent_flow_of(datum/act/op/A)
	var/datum/capability/def = A.cap
	if(def && hascall(def, "flow_of"))
		return call(def, "flow_of")(A)
	return list(A.held, A.target, REAGENT_FLOW_TRANSFER)

/// Units of `holder` already set aside: as a source (volume) or as a sink (capacity).
/proc/reagents_reserved(atom/holder, capacity)
	. = 0
	for(var/datum/reservation/reagents/R in holder.rx?.reservations)
		if(R.res_id == RES_REAGENTS && !R.ended && R.capacity_hold == capacity)
			. += R.amount

/// What a source can still give now: its volume less what other ops set aside.
/proc/reagents_giveable(atom/source)
	return source?.reagents ? max(0, source.reagents.total_volume - reagents_reserved(source, FALSE)) : 0

/// What a sink can still take now: its free space less what other ops set aside.
/proc/reagents_takeable(atom/sink)
	return sink?.reagents ? max(0, sink.reagents.get_free_space() - reagents_reserved(sink, TRUE)) : 0

/// RES_REAGENTS: the source's volume and the sink's capacity.
/datum/resource/reagents
	res_id = RES_REAGENTS
	name = "reagents"

/datum/resource/reagents/holder_of(datum/act/op/A)
	var/list/flow = reagent_flow_of(A)
	return flow[1]

/// How much the flow can carry now: the source's volume, and with a sink the sink's free space (the smaller). Reserved amounts are the engine's to subtract.
/datum/resource/reagents/available(datum/act/op/A)
	var/list/flow = reagent_flow_of(A)
	var/atom/source = flow[1]
	if(!source?.reagents)
		return 0
	var/amount = source.reagents.total_volume
	if(flow[3] == REAGENT_FLOW_TRANSFER)
		var/atom/sink = flow[2]
		if(!sink?.reagents)
			return 0
		amount = min(amount, reagents_takeable(sink) + reserved_total(source, RES_REAGENTS))
	return amount

/datum/resource/reagents/refusal(datum/act/op/A, n)
	var/list/flow = reagent_flow_of(A)
	var/atom/source = flow[1]
	if(!source?.reagents || !reagents_giveable(source))
		return /datum/msg/reagent_container/empty
	return /datum/msg/reagent_container/full

/// Sets `n` aside on the source and, for a transfer, `n` of capacity on the sink. All or nothing.
/datum/resource/reagents/reserve(datum/act/op/A, n)
	if(!isnum(n) || n <= 0)
		return null
	var/list/flow = reagent_flow_of(A)
	var/atom/source = flow[1]
	var/atom/sink = flow[2]
	var/mode = flow[3]
	if(!source || QDELETED(source) || reagents_giveable(source) < n)
		return null
	if(mode == REAGENT_FLOW_TRANSFER && (!sink || QDELETED(sink) || reagents_takeable(sink) < n))
		return null
	var/datum/reservation/reagents/R = new
	R.res_id = res_id
	R.holder = source // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	R.amount = n
	R.op_key = A.key
	R.held = A.held // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	R.actor = A.actor // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	R.sink = sink // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	R.flow_mode = mode
	LAZYADD(rx_of(source).reservations, R)
	if(mode == REAGENT_FLOW_TRANSFER)
		var/datum/reservation/reagents/P = new
		P.res_id = res_id
		P.holder = sink // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
		P.amount = n
		P.op_key = A.key
		P.capacity_hold = TRUE
		LAZYADD(rx_of(sink).reservations, P)
		R.peer = P // ALLOW(ownership): a reservation lives until its op ends, then the engine drops it
	return R

/// Moves the reserved amount: the source gives it up and the sink takes it, or the target is splashed. The sink's capacity hold ends with it.
/datum/resource/reagents/commit(datum/reservation/R)
	var/datum/reservation/reagents/RR = R
	var/atom/source = RR.holder
	var/moved = 0
	if(QDELETED(source) || !source.reagents)
		reagent_flow_end(RR)
		return OP_FAILED
	switch(RR.flow_mode)
		if(REAGENT_FLOW_TRANSFER)
			var/atom/sink = RR.sink
			if(QDELETED(sink) || !sink.reagents)
				reagent_flow_end(RR)
				return OP_FAILED
			reagent_flow_end(RR) // the capacity hold goes first: the move below is what takes the space
			moved = source.reagents.trans_to_holder(sink.reagents, RR.amount)
		if(REAGENT_FLOW_SPLASH)
			var/atom/target = RR.sink
			moved = min(RR.amount, source.reagents.total_volume)
			source.reagents.splash(target, moved)
	return moved > 0 ? OP_OK : OP_FAILED

/datum/resource/reagents/release(datum/reservation/R)
	reagent_flow_end(R)

/// Ends the sink-side capacity hold of a reagent reservation, if it has one.
/proc/reagent_flow_end(datum/reservation/reagents/R)
	var/datum/reservation/reagents/P = R.peer
	if(P)
		R.peer = null
		reservation_forget(P)
