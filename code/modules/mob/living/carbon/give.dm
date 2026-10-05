/mob/living/verb/give(mob/living/target in living_mobs_in_view(1))
	set category = VERB_CAT_IC_GAME
	set name = "Give"

	do_give(target)

/mob/living/proc/do_give(mob/living/carbon/human/target)

	if(src.incapacitated())
		return
	if(!istype(target) || target.incapacitated() || target.client == null)
		return

	var/obj/item/I = src.get_active_hand()
	if(!I)
		I = src.get_inactive_hand()
	if(!I)
		to_chat(src, span_warning("You don't have anything in your hands to give to \the [target]."))
		return

	if(istype(I, /obj/item/grab)) // Drop grabs, this is an edge case
		var/obj/item/grab/check_grab = I
		if(check_grab?.grab_target())
			act_message(src, check_grab?.grab_target(), others = span_danger("%U% breaks their grip on %T%!"))
		drop_from_inventory(check_grab)
		return

	act_message(src, target, MSG_SELF(span_notice("You hold out %I% to %T%, waiting for them to accept it.")), MSG_OTHERS(span_notice("%U% holds out %I% to %T%.")), item = I)

	// The offer is answered by the target; the answer runs on us.
	open_request(src, /datum/prompt/choice/give_item, PROC_REF(give_request_finished), answerer = target, asker = src, subject = I)

/// An item offer (the subject), answered by the target. Re-checked on the answer: both able,
/// still adjacent, and the item still in the giver's hands.
/datum/prompt/choice/give_item
	title = "Item Offer"
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0

/datum/prompt/choice/give_item/prepare(datum/act/A)
	..()
	question = "[asker] wants to give you \a [subject]. Will you accept it?"

/datum/prompt/choice/give_item/proc/captures_available()
	return !QDELETED(asker) && !QDELETED(answerer) && !QDELETED(subject)

/datum/prompt/choice/give_item/recheck_extra()
	. = ..()
	if(.)
		return
	if(!captures_available())
		return "The original item offer is no longer available."
	// Old No/decline was delivered before typed_recheck, even after movement or incapacity.
	if(isnull(answer_value) || answer_value == "No")
		return
	if(answerer.incapacitated() || asker.incapacitated())
		return "not able to"
	if(!answerer.Adjacent(asker))
		return "too far away"
	if(asker.get_active_hand() != subject && asker.get_inactive_hand() != subject)
		return "not holding it"

/datum/prompt/choice/give_item/proc/declined()
	act_message(answerer, asker, others = span_notice("%T% tried to hand %I% to %U%, but %U% didn't want it."), item = subject)

/datum/prompt/choice/give_item/proc/refused(reason)
	if(!asker || !answerer || !subject)
		return
	if(reason == "too far away")
		to_chat(asker, span_warning("You need to stay in reaching distance while giving an object"))
		to_chat(answerer, span_warning("\The [asker] moved too far away."))
	else if(reason != "not able to")
		to_chat(asker, span_warning("You need to keep the item in your hands."))
		to_chat(answerer, span_warning("\The [asker] seems to have given up on passing \the [subject] to you."))

/mob/living/proc/give_request_finished(datum/act/request/context)
	resolve_item_offer(context)

/mob/living/proc/resolve_item_offer(datum/act/request/context)
	var/datum/prompt/choice/give_item/ask = context.request
	if(!ask.captures_available())
		return
	if(!context.answer)
		if(!isnull(ask.answer_value))
			ask.refused(ask.last_error)
		return
	if(ask.answer_value == "No")
		ask.declined()
		return
	give_answered(ask)

/mob/living/proc/give_answered(datum/prompt/choice/give_item/ask)
	var/obj/item/I = ask.subject
	var/mob/living/carbon/human/target = ask.answerer

	if(target.hands_are_full())
		to_chat(target, span_warning("Your hands are full."))
		to_chat(src, span_warning("Their hands are full."))
		return

	if(src.unEquip(I))
		target.put_in_hands(I) // If this fails it will just end up on the floor, but that's fitting for things like dionaea.
		act_message(src, target, others = span_notice("%U% handed %I% to %T%"), item = I)
