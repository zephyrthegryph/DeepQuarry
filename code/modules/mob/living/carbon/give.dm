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
	om_ask(target, /datum/om/prompt/confirm/give_item, PROC_REF(give_answered), asker = src, subject = I)

/// An item offer (the subject), answered by the target. Re-checked on the answer: both able,
/// still adjacent, and the item still in the giver's hands.
/datum/om/prompt/confirm/give_item
	title = "Item Offer"
	ask_flags = ASK_CAPABLE | ASK_ADJACENT | ASK_HELD

/datum/om/prompt/confirm/give_item/prepare()
	message = "[asker] wants to give you \a [subject]. Will you accept it?"
	return TRUE

/datum/om/prompt/confirm/give_item/declined()
	answerer.visible_message(span_notice("\The [asker] tried to hand \the [subject] to \the [answerer], but \the [answerer] didn't want it."))

/datum/om/prompt/confirm/give_item/refused(reason)
	if(!asker || !answerer || !subject)
		return
	if(reason == "too far away")
		to_chat(asker, span_warning("You need to stay in reaching distance while giving an object"))
		to_chat(answerer, span_warning("\The [asker] moved too far away."))
	else if(reason != "not able to")
		to_chat(asker, span_warning("You need to keep the item in your hands."))
		to_chat(answerer, span_warning("\The [asker] seems to have given up on passing \the [subject] to you."))

/mob/living/proc/give_answered(datum/om/prompt/confirm/give_item/ask)
	var/obj/item/I = ask.subject
	var/mob/living/carbon/human/target = ask.answerer

	if(target.hands_are_full())
		to_chat(target, span_warning("Your hands are full."))
		to_chat(src, span_warning("Their hands are full."))
		return

	if(src.unEquip(I))
		target.put_in_hands(I) // If this fails it will just end up on the floor, but that's fitting for things like dionaea.
		act_message(src, target, others = span_notice("%U% handed %I% to %T%"), item = I)
