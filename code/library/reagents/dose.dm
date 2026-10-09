// dose(...) (doc/rewrite/final_api.html, section 11; section 16.5): a thing that is taken whole and used up: a pill (swallowed), a patch (stuck on the
// skin). On top of reagent_container() (the holder).
//
//   CAPABILITIES(/obj/item/reagent_containers/pill,
//       reagent_container(volume = nameof(volume), needle = TRUE, sealed = TRUE, settable = FALSE, shows_contents = FALSE),
//       dose(route = CHEM_INGEST))
//
// `route` is CHEM_INGEST (swallowed: the ingested holder, with the taste) or CHEM_TOUCH (on the skin, through the limb aimed at; `pierces` names the holder
// var that says a patch may go through thick material). `dose_wait` is the time it takes to put it on somebody else.
//
// Ops (all "dose.<name>"):
//   take       (ingest) a click on yourself: all of it is swallowed, and it is used up. A mask or a missing mouth refuses.
//   force      (ingest) a click on another person: after `dose_wait`, the same into them
//   apply      (touch) a click on yourself: all of it goes on the limb you aim at; a missing, robotic or covered limb refuses
//   stick      (touch) the same on another person, after `dose_wait`
//   dissolve   a click on an open container with something in it: all that fits goes into it, and it is used up
//   cut        (`cuts_into` = a type) a sharp thing, or an ID card, used on it: it is cut up into one of that type, which holds what it held
//
// What goes is one RES_REAGENTS transaction (reagent_flow.dm: REAGENT_FLOW_INGEST, REAGENT_FLOW_TOUCH, REAGENT_FLOW_TRANSFER), and the thing is used up by
// the op's consumes() when it commits.

CAPABILITY_TYPE(dose, CAP_DOSE, /datum/capability/lib/dose, key = NONE, route = CHEM_INGEST, dose_wait = 30, pierces = null, cuts_into = null)

MSG_DEF_SELF(dose/limb_missing, "The limb is missing!")
MSG_DEF_SELF(dose/limb_robotic, "It won't work on a robotic limb!")
MSG_DEF_SELF(dose/limb_covered, "It can't be applied through such a thick material!")
MSG_DEF_SELF(dose/target_empty, "It is empty.")
MSG_DEF(dose/taken, "You swallow %I%.", "%U% swallows %I%.")
MSG_DEF(dose/forced, "You force %T% to swallow %I%.", "%U% forces %T% to swallow %I%.")
MSG_DEF(dose/begin_force, "You attempt to force %T% to swallow %I%.", "%U% attempts to force %T% to swallow %I%.")
MSG_DEF(dose/applied, "You put %I% on yourself.", "%U% puts %I% on.")
MSG_DEF(dose/stuck, "You apply %I% to %T%.", "%U% applies %I% to %T%.")
MSG_DEF(dose/begin_stick, "You attempt to place %I% onto %T%.", "%U% attempts to place %I% onto %T%.")
MSG_DEF(dose/dissolved, "You put %I% in %T%; it dissolves.", "%U% puts something in %T%.")

/datum/capability/lib/dose/entries()
	var/touch = route == CHEM_TOUCH
	return list(
		touch ? op("apply", at_target(/mob/living/carbon/human), when(CAP_PROC(targets_self)), priority(OP_PRIORITY_PART), label("Put on"),
			needs(req_reagents(1, because = MSG(dose/target_empty)), req_bool(CAP_PROC(limb_there), because = MSG(dose/limb_missing)),
				req_bool(CAP_PROC(limb_not_robotic), because = MSG(dose/limb_robotic)), req_bool(CAP_PROC(limb_open), because = MSG(dose/limb_covered))),
			costs(RES_REAGENTS, CAP_PROC(whole)), consumes(), then(CAP_PROC(put_on)), says(MSG(dose/applied))) : null,
		touch ? op("stick", at_target(/mob/living/carbon/human), when(cond_not(CAP_PROC(targets_self))), priority(OP_PRIORITY_PART), label("Apply to"),
			begins(MSG(dose/begin_stick)), wait(CAP_PROC(wait_time)),
			needs(req_reagents(1, because = MSG(dose/target_empty)), req_bool(CAP_PROC(limb_there), because = MSG(dose/limb_missing)),
				req_bool(CAP_PROC(limb_not_robotic), because = MSG(dose/limb_robotic)), req_bool(CAP_PROC(limb_open), because = MSG(dose/limb_covered))),
			costs(RES_REAGENTS, CAP_PROC(whole)), consumes(), then(CAP_PROC(put_on_other)), says(MSG(dose/stuck))) : null,
		touch ? null : op("take", at_target(/mob/living/carbon/human), when(CAP_PROC(targets_self)), priority(OP_PRIORITY_PART), label("Swallow"),
			needs(req_belly_free(), req_mouth_free()),
			costs(RES_REAGENTS, CAP_PROC(whole)), consumes(), says(MSG(dose/taken))),
		touch ? null : op("force", at_target(/mob/living/carbon/human), when(cond_not(CAP_PROC(targets_self))), priority(OP_PRIORITY_PART), label("Force down"),
			begins(MSG(dose/begin_force)), wait(CAP_PROC(wait_time)),
			needs(req_belly_free(), req_mouth_free()),
			costs(RES_REAGENTS, CAP_PROC(whole)), consumes(), then(CAP_PROC(forced_down)), says(MSG(dose/forced))),
		cuts_into ? op("cut", item(/obj/item), when(CAP_PROC(held_cuts)), label("Cut it up"), then(CAP_PROC(cut_up))) : null,
		op("dissolve", at_target(), when(CAP_PROC(target_is_open_holder)), priority(OP_PRIORITY_PART), label("Dissolve in it"),
			needs(req_bool(CAP_PROC(target_has_reagents), because = MSG(dose/target_empty)), req_bool(CAP_PROC(target_has_room), because = MSG(reagent_container/full))),
			costs(RES_REAGENTS, CAP_PROC(whole)), consumes(), then(CAP_PROC(dose_dissolved)), says(MSG(dose/dissolved))))

/// (source, sink, mode) of the act's op: the thing into the one it is taken by, put on, or dissolved in.
/datum/capability/lib/dose/proc/flow_of(datum/act/op/A)
	switch(route)
		if(CHEM_TOUCH)
			if(op_name(A) != "dissolve")
				return list(A.holder, A.target, REAGENT_FLOW_TOUCH)
		else
			if(op_name(A) != "dissolve")
				return list(A.holder, A.target, REAGENT_FLOW_INGEST)
	return list(A.holder, A.target, REAGENT_FLOW_TRANSFER)

/datum/capability/lib/dose/proc/op_name(datum/act/op/A)
	var/at = findlasttext(A.key, ".")
	return at ? copytext(A.key, at + 1) : A.key

/// All of it, or all that fits when it is dissolved.
/datum/capability/lib/dose/proc/whole(datum/act/op/A)
	var/list/flow = flow_of(A)
	var/amount = reagents_giveable(flow[1])
	if(flow[3] == REAGENT_FLOW_TRANSFER)
		amount = min(amount, reagents_takeable(flow[2]))
	return amount

/datum/capability/lib/dose/proc/wait_time(datum/act/op/A)
	return dose_wait

// ---- conditions and requirements (x(datum/act/op/A), pure) ----

/datum/capability/lib/dose/proc/targets_self(datum/act/op/A)
	return !isnull(A.target) && A.target == A.actor

/// The clicked thing is an open holder (a beaker with its lid off, an open can): it is dissolved in.
/datum/capability/lib/dose/proc/target_is_open_holder(datum/act/op/A)
	var/atom/target = A.target
	return !isnull(target?.reagents) && target.is_open_container()

/// The held thing has an edge (or is a card to scrape it with).
/datum/capability/lib/dose/proc/held_cuts(datum/act/op/A)
	var/obj/item/held = A.held
	return !isnull(held) && (held.sharp || held.edge || istype(held, /obj/item/card/id))

/datum/capability/lib/dose/proc/target_has_reagents(datum/act/op/A)
	var/atom/target = A.target
	return !!target?.reagents?.total_volume

/datum/capability/lib/dose/proc/target_has_room(datum/act/op/A)
	var/atom/target = A.target
	return reagents_takeable(target) > 0

/datum/capability/lib/dose/proc/req_belly_free()
	return req_bool(CAP_PROC(belly_free), because = MSG(reagent_container/from_belly))

/datum/capability/lib/dose/proc/req_mouth_free()
	return req_bool(CAP_PROC(mouth_free), because = MSG(reagent_container/mouth_blocked))

/datum/capability/lib/dose/proc/belly_free(datum/act/op/A)
	var/mob/living/target = A.target
	return target.consume_liquid_belly || !reagents_from_belly(A.holder)

/datum/capability/lib/dose/proc/mouth_free(datum/act/op/A)
	return isnull(mouth_blocked_reason(A.actor, A.target))

/// The limb the one who acts aims at, on the person it goes on.
/datum/capability/lib/dose/proc/limb_aimed(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/mob/user = A.actor
	if(!ishuman(target) || !user?.zone_sel)
		return null
	return target.get_organ(check_zone(user.zone_sel.selecting))

/datum/capability/lib/dose/proc/limb_there(datum/act/op/A)
	return !isnull(limb_aimed(A))

/datum/capability/lib/dose/proc/limb_not_robotic(datum/act/op/A)
	var/obj/item/organ/external/affecting = limb_aimed(A)
	return isnull(affecting) || affecting.status < ORGAN_ROBOT

/// Whatever covers the limb lets it through (a patch may pierce material, if it says so). The thick hide of some species is a roll made when it goes on.
/datum/capability/lib/dose/proc/limb_open(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/mob/user = A.actor
	var/atom/holder = A.holder
	var/pierce = pierces
	if(istext(pierce))
		pierce = holder.vars[pierce]
	return !!target.can_inject(user, FALSE, user.zone_sel.selecting, pierce, INJECT_METHOD_NEEDLE, FALSE)

/// The roll of a thick hide, for the limb aimed at: TRUE when the thing is turned away.
/datum/capability/lib/dose/proc/hide_turns_it_away(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/obj/item/organ/external/affecting = limb_aimed(A)
	if(!affecting || !target.thick_skin_holds(affecting))
		return FALSE
	to_chat(A.actor, span_notice("[A.holder] can't be applied through such a thick material!"))
	return TRUE

// ---- effects ----

/// The thing goes on the one who aims it at themselves.
/datum/capability/lib/dose/proc/put_on(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/obj/item/organ/external/affecting = limb_aimed(A)
	if(hide_turns_it_away(A))
		return OP_REFUSED
	to_chat(target, span_notice("[A.holder] is placed on your [affecting]."))
	return OP_OK

/// The thing goes on another (the wait is over).
/datum/capability/lib/dose/proc/put_on_other(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/mob/user = A.actor
	var/obj/item/organ/external/affecting = limb_aimed(A)
	if(hide_turns_it_away(A))
		return OP_REFUSED
	var/atom/holder = A.holder
	user.setClickCooldown(user.get_attack_speed(holder))
	add_attack_logs(user, target, "Applied a patch containing [holder.reagents.get_reagents()]")
	to_chat(target, span_notice("[holder] is placed on your [affecting]."))
	return OP_OK

/// Somebody else is made to swallow it (the wait is over).
/datum/capability/lib/dose/proc/forced_down(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/holder = A.holder
	user.setClickCooldown(user.get_attack_speed(holder))
	add_attack_logs(user, A.target, "Fed a pill containing [holder.reagents.get_reagents()]")
	return OP_OK

/// It is cut up into a powder that holds what it held.
/datum/capability/lib/dose/proc/cut_up(datum/act/op/A)
	var/obj/item/W = A.held
	var/mob/user = A.actor
	var/atom/holder = A.holder
	var/obj/item/reagent_containers/powder/J = new cuts_into(holder.loc)
	if(is_sharp(W))
		user.balloon_alert_visible("[user] cuts up [holder] with [W]!", "cut up [holder] with [W]")
	else
		user.balloon_alert_visible("[user] clumsily cuts up [holder] with [W]!", "You clumsily cut up [holder] with [W]")
	play_sfx(holder.loc, SFX_EFFECTS_CHOP)
	if(holder.reagents)
		holder.reagents.trans_to_obj(J, holder.reagents.total_volume, user = user)
	J.get_appearance()
	consume(holder, user)
	return OP_OK

/// It is dissolved in a container.
/datum/capability/lib/dose/proc/dose_dissolved(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/holder = A.holder
	add_attack_logs(user, A.target, "Spiked [A.target] with a pill containing [holder.reagents.get_reagents()]")
	return OP_OK
