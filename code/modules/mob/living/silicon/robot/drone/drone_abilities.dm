// DRONE ABILITIES
/mob/living/silicon/robot/drone/verb/set_mail_tag()
	set name = "Set Mail Tag"
	set desc = "Tag yourself for delivery through the disposals system."
	set category = "Abilities.Silicon"

	om_prompt(src, src, list("kind" = "list", "message" = "Select the desired destination.", "title" = "Set Mail Tag", "choices" = GLOB.tagger_locations, "on_cancel" = PROC_REF(mail_tag_cleared)), PROC_REF(mail_tag_chosen))

/mob/living/silicon/robot/drone/proc/mail_tag_cleared(mob/user, datum/om/prompt/ask)
	mail_destination = ""

/mob/living/silicon/robot/drone/proc/mail_tag_chosen(mob/user, new_tag, datum/om/prompt/ask)
	to_chat(src, span_notice("You configure your internal beacon, tagging yourself for delivery to '[new_tag]'."))
	mail_destination = new_tag

	//Auto flush if we use this verb inside a disposal chute.
	var/obj/machinery/disposal/D = src.loc
	if(istype(D))
		to_chat(src, span_notice("\The [D] acknowledges your signal."))
		D.flush_count = D.flush_every_ticks

	return

/mob/living/silicon/robot/drone/MouseDrop(atom/over_object)
	var/mob/living/carbon/human/H = over_object
	if(!istype(H) || !Adjacent(H))
		return ..()
	if(IS_GRABBING(H) && hat && !(H.get_equipped_item(SLOT_ID_HAND_L) && H.get_equipped_item(SLOT_ID_HAND_R)))
		var/obj/item/removed_hat = remove_hat(get_turf(src))
		H.put_in_hands(removed_hat)
		H.visible_message(span_danger("\The [H] removes \the [src]'s [removed_hat]."))
		return
	else
		return ..()
