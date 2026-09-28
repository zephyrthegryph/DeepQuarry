/mob/living/verb/give(mob/living/target in living_mobs_in_view(1))
	set category = "IC.Game"
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
			visible_message(span_danger("\The [src] breaks their grip on [check_grab?.grab_target()]!"))
		drop_from_inventory(check_grab)
		return

	src.visible_message(span_notice("\The [src] holds out \the [I] to \the [target]."), span_notice("You hold out \the [I] to \the [target], waiting for them to accept it."))

	// The offer is answered by the target; the answer runs on us.
	om_prompt(src, target, list("message" = "[src] wants to give you \a [I]. Will you accept it?", "title" = "Item Offer", "choices" = list("Yes","No"), "data" = list("item" = I)), PROC_REF(give_answered))

/mob/living/proc/give_answered(mob/living/carbon/human/target, answer, datum/om/prompt/ask)
	var/obj/item/I = ask.get("item")
	if(answer != "Yes")
		target.visible_message(span_notice("\The [src] tried to hand \the [I] to \the [target], but \the [target] didn't want it."))
		return
	if(incapacitated() || target.incapacitated())
		return

	if(!Adjacent(target))
		to_chat(src, span_warning("You need to stay in reaching distance while giving an object"))
		to_chat(target, span_warning("\The [src] moved too far away."))
		return

	if(I.loc != src || !src.item_is_in_hands(I))
		to_chat(src, span_warning("You need to keep the item in your hands."))
		to_chat(target, span_warning("\The [src] seems to have given up on passing \the [I] to you."))
		return

	if(target.hands_are_full())
		to_chat(target, span_warning("Your hands are full."))
		to_chat(src, span_warning("Their hands are full."))
		return

	if(src.unEquip(I))
		target.put_in_hands(I) // If this fails it will just end up on the floor, but that's fitting for things like dionaea.
		target.visible_message(span_notice("\The [src] handed \the [I] to \the [target]"))
