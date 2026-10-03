// reagent_container(volume, transfer, lid, needle, spray) (doc/rewrite/final_api.html, section 11 "Reagents and food"; section 16.5): a holder with a
// reagent holder of its own and the ops that move reagents between holders and mobs.
//
//   CAPABILITIES(/obj/item/reagent_containers/glass/beaker,
//       reagent_container(volume = 60, transfer = list(5, 10, 15, 30, 60), lid = TRUE))
//   CAPABILITIES(/obj/item/reagent_containers/glass/beaker/large, configure(reagent_container(volume = 120)))
//
// Ops (all keyed "reagent_container.<name>"):
//   lid          hand or in-hand, when the container has a lid: toggles REAGENT_CONTAINER_LID_OPEN
//   set_amount   the menu: asks how much one transfer moves (one of `transfer`), kept per container (cap_data)
//   pour         the held container into the clicked one, when it has something in it
//   fill         the held container takes from the clicked one, when it is empty
//   splash       the same click in a hostile stance: everything in the held container is splashed over the target
//   drink        the held container onto its own holder's mouth (the click is on the actor)
//   inject       (needle = TRUE) the held container into another mob
//   spray        (spray = TRUE) the amount of one transfer is sprayed over the target; such a container does not pour
//
// A pour, a fill, a drink and an injection are one RES_REAGENTS transaction: the source's volume and the sink's capacity are set aside together and
// committed together (reagent_flow.dm), so a sink that is full refuses with its reason before anything leaves the source. Requirements say why: a
// closed lid, an empty source, a closed or full target. The amount of one transfer is the chosen one, clamped to what the source holds and the sink takes.
//
// State: REAGENT_CONTAINER_LID_OPEN (a lidless container is open from the start). Look: the lid layer while closed, and "fill0".."fill4" by how full it is.
// Examine: what it holds, and a closed lid. The reagent holder is made at init with `volume`, so a type that configures a bigger volume gets a bigger holder.

CAPABILITY_TYPE(reagent_container, CAP_REAGENT_CONTAINER, /datum/capability/lib/reagent_container, key = NONE, volume = 30, transfer = list(5, 10, 15, 30), lid = FALSE, needle = FALSE, spray = FALSE)
cap_keys(CAP_REAGENT_CONTAINER, LID_OPEN = MSG(reagent_container/lid_closed))

MSG_DEF_SELF(reagent_container/lid_closed, "The lid is closed.")
MSG_DEF_SELF(reagent_container/empty, "There is nothing in it to pour.")
MSG_DEF_SELF(reagent_container/full, "It is full.")
MSG_DEF_SELF(reagent_container/target_closed, "It is closed.")
MSG_DEF_SELF(reagent_container/no_holder, "That can't hold liquids.")
MSG_DEF_SELF(reagent_container/bad_amount, "It can't pour that amount.")
MSG_DEF(reagent_container/lid, "You work the lid of %T%.", "%U% works the lid of %T%.")
MSG_DEF(reagent_container/pour, "You pour from %I% into %T%.", "%U% pours from %I% into %T%.")
MSG_DEF(reagent_container/fill, "You fill %I% from %T%.", "%U% fills %I% from %T%.")
MSG_DEF(reagent_container/splash, "You splash %I% over %T%.", "%U% splashes %I% over %T%!")
MSG_DEF(reagent_container/drink, "You drink from %I%.", "%U% drinks from %I%.")
MSG_DEF(reagent_container/inject, "You inject %T% with %I%.", "%U% injects %T% with %I%.")
MSG_DEF(reagent_container/spray, "You spray %I% at %T%.", "%U% sprays %I% at %T%.")
MSG_DEF_SELF(reagent_container/lid_examine, "Its lid is closed.")

/// Per-activation state: the transfer amount the user chose (null: the first of `transfer`).
/datum/cap_data/reagent_container
	var/transfer_amount

/datum/capability/lib/reagent_container
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/reagent_container/cap_data_type()
	return /datum/cap_data/reagent_container

/datum/capability/lib/reagent_container/entries()
	return list(
		lid ? op("lid", inputs(hand(), in_hand()), label("Open or close the lid"), toggles(REAGENT_CONTAINER_LID_OPEN), says(MSG(reagent_container/lid))) : null,
		op("set_amount", menu(), label("Set transfer amount"),
			asks(/datum/prompt/number, fields = list("question" = "Amount per transfer:")), then(CAP_PROC(apply_amount))),
		spray ? null : op("pour", at_target(), when(CAP_PROC(held_has_reagents)), label("Pour"),
			needs(req(CAP_PROC(source_open), because = MSG(reagent_container/lid_closed)), req(CAP_PROC(sink_has_holder), because = MSG(reagent_container/no_holder)),
				req(CAP_PROC(sink_open), because = MSG(reagent_container/target_closed)), req(CAP_PROC(source_has_reagents), because = MSG(reagent_container/empty)),
				req(CAP_PROC(sink_has_room), because = MSG(reagent_container/full))),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/pour))),
		op("fill", at_target(), when(cond_not(CAP_PROC(held_has_reagents))), label("Fill"),
			needs(req(CAP_PROC(sink_open), because = MSG(reagent_container/lid_closed)), req(CAP_PROC(source_has_holder), because = MSG(reagent_container/no_holder)),
				req(CAP_PROC(source_open), because = MSG(reagent_container/target_closed)), req(CAP_PROC(source_has_reagents), because = MSG(reagent_container/empty)),
				req(CAP_PROC(sink_has_room), because = MSG(reagent_container/full))),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/fill))),
		op("splash", at_target(), hostile(), label("Splash"),
			needs(req(CAP_PROC(source_open), because = MSG(reagent_container/lid_closed)), req(CAP_PROC(source_has_reagents), because = MSG(reagent_container/empty))),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/splash))),
		op("drink", at_target(/mob/living), when(CAP_PROC(targets_self)), priority(OP_PRIORITY_PART), label("Drink"),
			needs(req(CAP_PROC(source_open), because = MSG(reagent_container/lid_closed)), req(CAP_PROC(source_has_reagents), because = MSG(reagent_container/empty)),
				req(CAP_PROC(sink_has_room), because = MSG(reagent_container/full))),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/drink))),
		needle ? op("inject", at_target(/mob/living), when(cond_not(CAP_PROC(targets_self))), priority(OP_PRIORITY_PART), label("Inject"),
			needs(req(CAP_PROC(source_has_reagents), because = MSG(reagent_container/empty)), req(CAP_PROC(sink_has_room), because = MSG(reagent_container/full))),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/inject))) : null,
		spray ? op("spray", at_target(), when(CAP_PROC(held_has_reagents)), label("Spray"),
			needs(req(CAP_PROC(source_open), because = MSG(reagent_container/lid_closed)), req(CAP_PROC(source_has_reagents), because = MSG(reagent_container/empty))),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/spray))) : null,
		lid ? look_layer(LOOK_LID, when = cond_not(REAGENT_CONTAINER_LID_OPEN)) : null,
		look_layer(CAP_PROC(fill_layer)),
		examine_line(CAP_PROC(volume_text)),
		lid ? examine_line(MSG(reagent_container/lid_examine), when = cond_not(REAGENT_CONTAINER_LID_OPEN)) : null)

/// Look steps of the fill gauge.
#define REAGENT_FILL_LEVELS 4

/datum/capability/lib/reagent_container/on_holder_init_ctx(datum/act/eval/A)
	var/atom/holder = A.holder
	if(!holder.reagents)
		holder.create_reagents(volume)
	else if(holder.reagents.maximum_volume != volume)
		holder.reagents.maximum_volume = volume
	if(!lid)
		cap_key_set(holder, REAGENT_CONTAINER_LID_OPEN, TRUE)

// ---- state ----

/// The amount one transfer moves as the user chose it (the first of `transfer` until they choose).
/datum/capability/lib/reagent_container/proc/chosen_amount(atom/holder)
	var/datum/activation/act_state = cap_activation(holder, CAP_REAGENT_CONTAINER, null, TRUE)
	var/datum/cap_data/reagent_container/D = act_state ? activation_data(act_state) : null
	if(D?.transfer_amount)
		return D.transfer_amount
	return length(transfer) ? transfer[1] : 5

/// What set_amount answered: one of `transfer`.
/datum/capability/lib/reagent_container/proc/apply_amount(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/value = isnull(R) ? null : text2num("[R.value]")
	if(!isnum(value) || !(value in transfer))
		A.reason = /datum/msg/reagent_container/bad_amount
		return OP_REFUSED
	var/datum/activation/act_state = cap_activation(A.holder, CAP_REAGENT_CONTAINER, null, TRUE)
	var/datum/cap_data/reagent_container/D = activation_data(act_state)
	D.transfer_amount = value
	return OP_OK

// ---- the flow of each op ----

/// The short name of the op an act runs ("pour" for "reagent_container.pour").
/datum/capability/lib/reagent_container/proc/op_name(datum/act/op/A)
	var/at = findlasttext(A.key, ".")
	return at ? copytext(A.key, at + 1) : A.key

/// (source, sink, mode) of the act's op, for RES_REAGENTS.
/datum/capability/lib/reagent_container/proc/flow_of(datum/act/op/A)
	switch(op_name(A))
		if("fill")
			return list(A.target, A.holder, REAGENT_FLOW_TRANSFER)
		if("splash", "spray")
			return list(A.holder, A.target, REAGENT_FLOW_SPLASH)
	return list(A.holder, A.target, REAGENT_FLOW_TRANSFER)

/// How much this op moves: the chosen amount clamped to what the source holds and the sink takes. A splash throws everything. 0 when it cannot move any.
/datum/capability/lib/reagent_container/proc/transfer_amount(datum/act/op/A)
	var/list/flow = flow_of(A)
	var/atom/source = flow[1]
	var/atom/sink = flow[2]
	var/amount = op_name(A) == "splash" ? reagents_giveable(source) : chosen_amount(A.holder)
	amount = min(amount, reagents_giveable(source))
	if(flow[3] == REAGENT_FLOW_TRANSFER)
		amount = min(amount, reagents_takeable(sink))
	return amount

// ---- requirements and conditions (x(datum/act/A), pure) ----

/datum/capability/lib/reagent_container/proc/held_has_reagents(datum/act/op/A)
	var/atom/holder = A.holder
	return !!holder.reagents?.total_volume

/datum/capability/lib/reagent_container/proc/targets_self(datum/act/op/A)
	return !isnull(A.target) && A.target == A.actor

/datum/capability/lib/reagent_container/proc/source_open(datum/act/op/A)
	var/list/flow = flow_of(A)
	return reagent_holder_open(flow[1])

/datum/capability/lib/reagent_container/proc/sink_open(datum/act/op/A)
	var/list/flow = flow_of(A)
	return reagent_holder_open(flow[2])

/datum/capability/lib/reagent_container/proc/source_has_holder(datum/act/op/A)
	var/list/flow = flow_of(A)
	var/atom/source = flow[1]
	return !!source?.reagents

/datum/capability/lib/reagent_container/proc/sink_has_holder(datum/act/op/A)
	var/list/flow = flow_of(A)
	var/atom/sink = flow[2]
	return !!sink?.reagents

/datum/capability/lib/reagent_container/proc/source_has_reagents(datum/act/op/A)
	var/list/flow = flow_of(A)
	return reagents_giveable(flow[1]) > 0

/datum/capability/lib/reagent_container/proc/sink_has_room(datum/act/op/A)
	var/list/flow = flow_of(A)
	if(flow[3] != REAGENT_FLOW_TRANSFER)
		return TRUE
	return reagents_takeable(flow[2]) > 0

/// TRUE when `thing` can be poured from or into: a container with this capability by its lid, anything else by the atom's own open-container flag.
/proc/reagent_holder_open(atom/thing)
	if(!thing?.reagents)
		return FALSE
	var/datum/capability/lib/reagent_container/C = cap_of(thing, CAP_REAGENT_CONTAINER)
	if(C)
		return !C.lid || reagent_container_lid_open(thing)
	return thing.is_open_container()

// ---- presentation ----

/// The fill gauge layer: "fill0".."fill4", null while there is no holder or nothing in it.
/datum/capability/lib/reagent_container/proc/fill_layer(datum/act/eval/A)
	var/atom/holder = A.holder
	var/datum/reagents/R = holder.reagents
	if(!R || !R.maximum_volume || !R.total_volume)
		return null
	return "[LOOK_FILL_PREFIX][clamp(round(R.total_volume / R.maximum_volume * REAGENT_FILL_LEVELS), 0, REAGENT_FILL_LEVELS)]"

/datum/capability/lib/reagent_container/proc/volume_text(datum/act/op/A)
	var/atom/holder = A.holder
	var/datum/reagents/R = holder.reagents
	if(!R)
		return null
	return R.total_volume ? "It contains [R.total_volume] of [R.maximum_volume] units." : "It is empty. It holds [R.maximum_volume] units."
