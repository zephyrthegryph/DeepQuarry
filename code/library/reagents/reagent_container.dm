// reagent_container(...) (doc/rewrite/final_api.html, section 11 "Reagents and food"; section 16.5): a holder with a reagent holder of its own and the
// ops that move reagents between holders and mobs.
//
//   CAPABILITIES(/obj/item/reagent_containers/glass/beaker/large,
//       reagent_container(volume = 120, transfer = list(5, 10, 15, 30, 60, 120), lid = TRUE, starts_open = TRUE))
//
// A setting that is a fact of the type and not of this capability (the volume, the amount a transfer moves, the smallest and largest amount a
// person may choose, what it starts with) is a number or a list written here, or the name of a var of the holder that says it
// (`volume = nameof(volume)`): a type then keeps its settings on its own var lines, defaults and all, and a subtype or a map changes them there.
//
// Ops (all keyed "reagent_container.<name>"):
//   lid          used in hand, or from the menu, when the container has a lid: toggles REAGENT_CONTAINER_LID_OPEN
//   set_amount   the menu, and an alt-click: asks how much one transfer moves (one of `transfer`, or a whole number from `transfer_min` to
//                `transfer_max`), kept per container (cap_data)
//   pour         the held container into the clicked one: an open holder of liquid that the container is not put on (`rests_on`) and that is
//                not a tap with its top shut
//   fill         (`taps` = types) the held container takes from a tap, a closed tank of those types, by the tap's own amount
//   (`splash` = FALSE leaves out splash; `ingest_hostile` = TRUE lets drink and feed answer a hostile click too, unless it is a blow.)
//   splash       the same click in a hostile stance, on what cannot be poured into: everything in the held container is splashed over it
//   drink        a click on yourself in a stance that is not hostile: one transfer, swallowed (ingested); half of it for a small mob
//   feed         (feed = TRUE) the same click on somebody else, after `feed_wait`: the mouth, a gag, a mask or a belly can refuse
//   inject       (injects = TRUE) the held container into another mob, instantly (a hypospray; the syringe and the dropper have needle()'s ops)
//   spray        (spray = TRUE) the amount of one transfer is sprayed at the target (atom/reagent_spray_at(): a puff, a splash, what the holder's type
//                makes of it), after a click cooldown of `spray_cooldown`; a click on what the container rests on is left alone. A sprayer and a needle
//                container (`needle`; its ops are needle()'s) are not plain containers: they do not pour, splash, drink or feed. `sealed` = TRUE is a
//                container that is never open (a syringe), whatever it has for a lid. `lid_visible` = FALSE
//                is a lid that is only a state (an autoinjector is shut once it is spent): no op, no layer, no examine line; `starts_open` may be the name of a
//                holder var. `settable` = FALSE leaves out set_amount.
//
// A pour, a fill, a drink and an injection are one RES_REAGENTS transaction: the source's volume and the sink's capacity are set aside together and
// committed together (reagent_flow.dm), so a sink that is full refuses with its reason before anything leaves the source. Requirements say why: a
// closed lid, an empty source, a full target. What decides WHICH op a click is (pourable, tap, splashable) is a condition, so a click that no op
// answers (a table, a machine that takes the container) falls through to the target's own interactions. The amount of one transfer is the chosen
// one, clamped to what the source holds and the sink takes.
//
// State: REAGENT_CONTAINER_LID_OPEN (a lidless container, and a lidded one that `starts_open`, is open from the start; atom/is_open_container()
// follows it). Look: the lid layer while closed, and "fill0".."fill4" by how full it is. Examine: what it holds, and a closed lid, to `examine_range`
// tiles. The reagent holder is made at init with `volume`, and `starts` is put into it.

CAPABILITY_TYPE(reagent_container, CAP_REAGENT_CONTAINER, /datum/capability/lib/reagent_container, key = NONE, volume = 30, transfer = list(5, 10, 15, 30), lid = FALSE, needle = FALSE, injects = FALSE, spray = FALSE, starts_open = FALSE, transfer_default = null, transfer_min = null, transfer_max = null, starts = null, taps = null, rests_on = null, feed = FALSE, feed_wait = 30, examine_range = null, settable = TRUE, spray_cooldown = 4, shows_contents = TRUE, sealed = FALSE, lid_visible = TRUE, splash = TRUE, ingest_hostile = FALSE)
cap_keys(CAP_REAGENT_CONTAINER, LID_OPEN = MSG(reagent_container/lid_closed))

MSG_DEF_SELF(reagent_container/lid_closed, "The lid is closed.")
MSG_DEF_SELF(reagent_container/empty, "There is nothing in it to pour.")
MSG_DEF_SELF(reagent_container/full, "It is full.")
MSG_DEF_SELF(reagent_container/target_closed, "It is closed.")
MSG_DEF_SELF(reagent_container/no_holder, "That can't hold liquids.")
MSG_DEF_SELF(reagent_container/bad_amount, "It can't pour that amount.")
MSG_DEF_SELF(reagent_container/mouth_blocked, "Something is in the way of the mouth.")
MSG_DEF_SELF(reagent_container/cannot_feed, "That can't be fed.")
MSG_DEF_SELF(reagent_container/from_belly, "That contains something produced from a belly, and it won't be taken.")
MSG_DEF(reagent_container/lid, "You work the lid of %T%.", "%U% works the lid of %T%.")
MSG_DEF(reagent_container/pour, "You pour from %I% into %T%.", "%U% pours from %I% into %T%.")
MSG_DEF(reagent_container/fill, "You fill %I% from %T%.", "%U% fills %I% from %T%.")
MSG_DEF(reagent_container/splash, "You splash %I% over %T%.", "%U% splashes %I% over %T%!")
MSG_DEF(reagent_container/drink, "You drink from %I%.", "%U% drinks from %I%.")
MSG_DEF(reagent_container/begin_feed, "You begin to feed %T% from %I%.", "%U% is trying to feed %T% from %I%!")
MSG_DEF(reagent_container/feed, "You feed %T% from %I%.", "%U% feeds %T% from %I%.")
MSG_DEF(reagent_container/inject, "You inject %T% with %I%.", "%U% injects %T% with %I%.")
MSG_DEF(reagent_container/spray, "You spray %I% at %T%.", "%U% sprays %I% at %T%.")
MSG_DEF_SELF(reagent_container/lid_examine, "Its lid is closed.")

/// Per-activation state: the transfer amount the user chose (null: the type's default).
/datum/cap_data/reagent_container
	var/transfer_amount

/datum/capability/lib/reagent_container
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/reagent_container/cap_data_type()
	return /datum/cap_data/reagent_container

/datum/capability/lib/reagent_container/entries()
	return list(
		(lid && lid_visible) ? op("lid", inputs(in_hand(), menu()), label("Open or close the lid"), toggles(REAGENT_CONTAINER_LID_OPEN), says(MSG(reagent_container/lid))) : null,
		settable ? op("set_amount", inputs(menu(), hand()), answers(INTENT_TOGGLE), when(CAP_PROC(range_known)), label("Set transfer amount"),
			asks(/datum/prompt/number, fields = list("question" = "Amount per transfer:")), then(CAP_PROC(apply_amount))) : null,
		(spray || needle) ? null : op("pour", at_target(), when(CAP_PROC(target_pourable)), priority(OP_PRIORITY_PART), label("Pour"),
			needs(req_source_open(), req_source_has_reagents(),
				req_sink_has_room()),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/pour))),
		length(taps) ? op("fill", at_target(), when(CAP_PROC(target_is_tap)), priority(OP_PRIORITY_PART), priority(above("reagent_container.pour")), label("Fill"),
			needs(req(CAP_PROC(sink_open)), req_source_has_reagents(),
				req_sink_has_room()),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/fill))) : null,
		(spray || needle || !splash) ? null : op("splash", at_target(), hostile(), stance(I_HURT), when(CAP_PROC(target_splashable)), label("Splash"),
			needs(req_source_open(), req_source_has_reagents()),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/splash))),
		(spray || needle) ? null : op("drink", at_target(/mob/living), when(cond_all(CAP_PROC(targets_self), CAP_PROC(blow_free))), stance(ingest_hostile ? list(I_HELP, I_DISARM, I_GRAB, I_HURT) : list(I_HELP, I_DISARM, I_GRAB)), priority(OP_PRIORITY_PART), label("Drink"),
			needs(req_source_open(), req_source_has_reagents(),
				req(CAP_PROC(can_be_fed)), req_belly_free(),
				req_mouth_free()),
			then(CAP_PROC(fed)), costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/drink))),
		(feed && !spray && !needle) ? op("feed", at_target(/mob/living), when(cond_all(cond_not(CAP_PROC(targets_self)), CAP_PROC(blow_free))), stance(ingest_hostile ? list(I_HELP, I_DISARM, I_GRAB, I_HURT) : list(I_HELP, I_DISARM, I_GRAB)), priority(OP_PRIORITY_PART + 1), label("Feed"),
			begins(MSG(reagent_container/begin_feed)), wait(feed_wait),
			needs(req_source_open(), req_source_has_reagents(),
				req(CAP_PROC(can_be_fed)), req_belly_free(),
				req_mouth_free()),
			then(CAP_PROC(fed)), costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/feed))) : null,
		injects ? op("inject", at_target(/mob/living), when(cond_not(CAP_PROC(targets_self))), priority(OP_PRIORITY_PART), label("Inject"),
			needs(req_source_has_reagents(), req_sink_has_room()),
			costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/inject))) : null,
		spray ? op("spray", at_target(), when(CAP_PROC(target_sprayable)), priority(OP_PRIORITY_PART), priority(above("reagent_container.fill")), label("Spray"),
			needs(req_source_open(), req(CAP_PROC(source_has_amount))),
			then(CAP_PROC(sprayed)), costs(RES_REAGENTS, CAP_PROC(transfer_amount)), says(MSG(reagent_container/spray))) : null,
		(lid && lid_visible) ? look_layer(LOOK_LID, when = cond_not(REAGENT_CONTAINER_LID_OPEN)) : null,
		look_layer(CAP_PROC(fill_layer)),
		examine_line(CAP_PROC(volume_text)),
		(lid && lid_visible) ? examine_line(CAP_PROC(lid_text)) : null)

/// Look steps of the fill gauge.
#define REAGENT_FILL_LEVELS 4

/datum/capability/lib/reagent_container/on_holder_init(datum/act/eval/A)
	var/atom/holder = A.holder
	var/max_volume = setting(holder, volume, 30)
	if(!holder.reagents)
		holder.create_reagents(max_volume)
	else if(holder.reagents.maximum_volume != max_volume)
		holder.reagents.maximum_volume = max_volume
	if(!lid || setting(holder, starts_open, FALSE))
		cap_key_set(holder, REAGENT_CONTAINER_LID_OPEN, TRUE)
	var/list/fill = setting(holder, starts, null)
	for(var/id in fill)
		holder.reagents.add_reagent(id, fill[id] || 1)

// ---- settings ----

/// A setting: the value written in the declaration, or what the holder's var of that name says now; `fallback` when neither is a value.
/datum/capability/lib/reagent_container/proc/setting(atom/holder, value, fallback)
	if(istext(value))
		value = holder.vars[value]
	return isnull(value) ? fallback : value

/// The amount one transfer moves as the user chose it (the type's own default until they choose).
/datum/capability/lib/reagent_container/proc/chosen_amount(atom/holder)
	var/datum/activation/act_state = cap_activation(holder, CAP_REAGENT_CONTAINER, null, FALSE) // a read never makes the activation (it may run inside a condition)
	var/datum/cap_data/reagent_container/D = act_state?.data
	if(D?.transfer_amount)
		return D.transfer_amount
	var/default = setting(holder, transfer_default, null)
	if(isnum(default))
		return default
	return length(transfer) ? transfer[1] : 5

/// The holder says how much a person may choose: its max var, if the capability names one, is a number (a golden cup has none: its amount is fixed).
/datum/capability/lib/reagent_container/proc/range_known(datum/act/op/A)
	var/atom/holder = A.holder
	return !istext(transfer_max) || isnum(holder.vars[transfer_max])

/// Whether `value` is an amount a person may choose: one of `transfer`, or (with a range declared) a whole number inside it.
/datum/capability/lib/reagent_container/proc/amount_allowed(atom/holder, value)
	if(!isnum(value))
		return FALSE
	var/high = setting(holder, transfer_max, null)
	if(isnum(high))
		var/low = setting(holder, transfer_min, 1)
		return value >= low && value <= high
	return value in transfer

/// What set_amount answered.
/datum/capability/lib/reagent_container/proc/apply_amount(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/value = isnull(R) ? null : text2num("[R.value]")
	if(isnum(value))
		value = round(value)
	if(!amount_allowed(A.holder, value))
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
		if("splash")
			return list(A.holder, A.target, REAGENT_FLOW_SPLASH)
		if("spray")
			return list(A.holder, A.target, REAGENT_FLOW_SPRAY)
		if("drink", "feed")
			return list(A.holder, A.target, REAGENT_FLOW_INGEST)
	return list(A.holder, A.target, REAGENT_FLOW_TRANSFER)

/// How much this op moves: the chosen amount clamped to what the source holds and the sink takes (a tap's own amount for a fill, half of it for a
/// small mob drinking). A splash throws everything. 0 when it cannot move any.
/datum/capability/lib/reagent_container/proc/transfer_amount(datum/act/op/A)
	var/list/flow = flow_of(A)
	var/atom/source = flow[1]
	var/atom/sink = flow[2]
	var/name = op_name(A)
	var/amount
	switch(name)
		if("splash")
			amount = reagents_giveable(source)
		if("fill")
			amount = reagent_transfer_amount(source) || chosen_amount(A.holder)
		else
			amount = chosen_amount(A.holder)
	if(name == "drink" && issmall(A.actor))
		amount = CEILING(amount / 2, 1)
	amount = min(amount, reagents_giveable(source))
	if(flow[3] == REAGENT_FLOW_TRANSFER)
		amount = min(amount, reagents_takeable(sink))
	return amount

// ---- what a click is: conditions (x(datum/act/A), pure) ----

/// The clicked thing is somewhere to pour: an open holder of liquid that this container is not put on, and not a tap with its top shut.
/datum/capability/lib/reagent_container/proc/target_pourable(datum/act/op/A)
	var/atom/target = A.target
	return !isnull(target?.reagents) && target.is_open_container() && !rests_on_target(target)

/// The clicked thing is a tap of one of the declared types with its top shut: it is drawn from.
/datum/capability/lib/reagent_container/proc/target_is_tap(datum/act/op/A)
	var/atom/target = A.target
	if(isnull(target?.reagents) || target.is_open_container() || rests_on_target(target))
		return FALSE
	for(var/tap_type in taps)
		if(istype(target, tap_type))
			return TRUE
	return FALSE

/// The clicked thing is sprayed at: not what the container rests on, and not a tap with its top shut (which fills it).
/datum/capability/lib/reagent_container/proc/target_sprayable(datum/act/op/A)
	return !rests_on_target(A.target) && !target_is_tap(A)

/// The clicked thing can be splashed: it is not poured into, not drawn from, and not something this container is put on.
/datum/capability/lib/reagent_container/proc/target_splashable(datum/act/op/A)
	return !target_pourable(A) && !target_is_tap(A) && !rests_on_target(A.target)

/// The container is put on or in the clicked thing (a table, a machine that takes it): it is never poured or splashed over it.
/datum/capability/lib/reagent_container/proc/rests_on_target(atom/target)
	if(isnull(rests_on))
		return FALSE
	var/list/types = islist(rests_on) ? rests_on : GLOB.reagent_containers_can_be_placed_into[rests_on]
	for(var/rest_type in types)
		if(istype(target, rest_type))
			return TRUE
	return FALSE

/datum/capability/lib/reagent_container/proc/held_has_reagents(datum/act/op/A)
	var/atom/holder = A.holder
	return !!holder.reagents?.total_volume

/datum/capability/lib/reagent_container/proc/targets_self(datum/act/op/A)
	return !isnull(A.target) && A.target == A.actor

/// A hostile click with something that hits (force, not a no-bludgeon item) is a blow, not a drink or a feeding (`ingest_hostile` containers: a carton feeds in
/// any stance, a golden cup hits).
/datum/capability/lib/reagent_container/proc/blow_free(datum/act/op/A)
	if(!ingest_hostile)
		return TRUE
	var/obj/item/holder = A.holder
	var/mob/user = A.actor
	return !(user?.combat_mode && !user.attack_variant && holder.force && !(holder.flags & NOBLUDGEON)) // a hostile stance is combat mode with no disarm or grab variant

// ---- requirements (x(datum/act/A), pure) ----

// Named requirements the transfer ops repeat. Each is the requirement of the like-named proc below, with its refusal.
/datum/capability/lib/reagent_container/proc/req_source_open()
	return req(CAP_PROC(source_open))

/datum/capability/lib/reagent_container/proc/req_source_has_reagents()
	return req(CAP_PROC(source_has_reagents))

/datum/capability/lib/reagent_container/proc/req_sink_has_room()
	return req(CAP_PROC(sink_has_room))

/datum/capability/lib/reagent_container/proc/req_belly_free()
	return req(CAP_PROC(belly_free))

/datum/capability/lib/reagent_container/proc/req_mouth_free()
	return req(CAP_PROC(mouth_free))

/datum/capability/lib/reagent_container/proc/source_open(datum/act/op/A)
	var/list/flow = flow_of(A)
	return (reagent_holder_open(flow[1])) ? null : /datum/msg/reagent_container/lid_closed

/datum/capability/lib/reagent_container/proc/sink_open(datum/act/op/A)
	var/list/flow = flow_of(A)
	return (reagent_holder_open(flow[2])) ? null : /datum/msg/reagent_container/lid_closed

/datum/capability/lib/reagent_container/proc/source_has_reagents(datum/act/op/A)
	var/list/flow = flow_of(A)
	return (reagents_giveable(flow[1]) > 0) ? null : /datum/msg/reagent_container/empty

/// A whole amount is left to spray: a sprayer with less than one amount sprays nothing.
/datum/capability/lib/reagent_container/proc/source_has_amount(datum/act/op/A)
	var/list/flow = flow_of(A)
	return (reagents_giveable(flow[1]) >= chosen_amount(A.holder)) ? null : /datum/msg/reagent_container/empty

/// The spray: the click costs time, and the holder's type makes of the amount what it does (a puff of it, a splash over a dense thing).
/datum/capability/lib/reagent_container/proc/sprayed(datum/act/op/A)
	var/mob/user = A.actor
	user?.setClickCooldown(spray_cooldown)
	return OP_OK

/datum/capability/lib/reagent_container/proc/sink_has_room(datum/act/op/A)
	var/list/flow = flow_of(A)
	if(flow[3] != REAGENT_FLOW_TRANSFER)
		return null
	return (reagents_takeable(flow[2]) > 0) ? null : /datum/msg/reagent_container/full

/// The one who is fed can be fed at all.
/datum/capability/lib/reagent_container/proc/can_be_fed(datum/act/op/A)
	var/mob/target = A.target
	return (istype(target) && target.can_feed()) ? null : /datum/msg/reagent_container/cannot_feed

/// What is in the container may be given to this one: a mob that does not take what a belly made refuses it.
/datum/capability/lib/reagent_container/proc/belly_free(datum/act/op/A)
	var/mob/target = A.target
	return (!istype(target) || target.consume_liquid_belly || !reagents_from_belly(A.holder)) ? null : /datum/msg/reagent_container/from_belly

/// Nothing is over the mouth.
/datum/capability/lib/reagent_container/proc/mouth_free(datum/act/op/A)
	return (isnull(mouth_blocked_reason(A.actor, A.target))) ? null : /datum/msg/reagent_container/mouth_blocked

/// A drink or a feeding: the one acting pays the click's time, and an attack log says who fed whom with what.
/datum/capability/lib/reagent_container/proc/fed(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/holder = A.holder
	user.setClickCooldown(user.get_attack_speed(holder))
	if(A.target != user)
		var/datum/reagents/R = holder.reagents
		add_attack_logs(user, A.target, "Fed from [holder.name] containing [R ? R.get_reagents() : "no reagent holder"]")
	return OP_OK

/// TRUE when `thing` can be poured from or into: anything with a holder that is open (a lid taken off, or the atom's own open-container flag).
/proc/reagent_holder_open(atom/thing)
	if(!thing?.reagents)
		return FALSE
	return thing.is_open_container()

// ---- presentation ----

/// The fill gauge layer: "fill0".."fill4", null while there is no holder or nothing in it.
/datum/capability/lib/reagent_container/proc/fill_layer(datum/act/eval/A)
	var/atom/holder = A.holder
	var/datum/reagents/R = holder.reagents
	if(!R || !R.maximum_volume || !R.total_volume)
		return null
	return "[LOOK_FILL_PREFIX][clamp(round(R.total_volume / R.maximum_volume * REAGENT_FILL_LEVELS), 0, REAGENT_FILL_LEVELS)]"

/// Is the viewer near enough to read the container?
/datum/capability/lib/reagent_container/proc/near_enough(datum/act/op/A)
	if(isnull(examine_range) || isnull(A.actor))
		return TRUE
	return get_dist(A.actor, A.holder) <= examine_range

/datum/capability/lib/reagent_container/proc/volume_text(datum/act/op/A)
	var/atom/holder = A.holder
	var/datum/reagents/R = holder.reagents
	if(!R || !shows_contents || !near_enough(A))
		return null
	return R.total_volume ? "It contains [R.total_volume] of [R.maximum_volume] units." : "It is empty. It holds [R.maximum_volume] units."

/datum/capability/lib/reagent_container/proc/lid_text(datum/act/op/A)
	if(reagent_container_lid_open(A.holder) || !near_enough(A))
		return null
	return "Its lid is closed."
