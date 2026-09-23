// DRONE ABILITIES
/mob/living/silicon/robot/drone/verb/set_mail_tag()
	set name = "Set Mail Tag"
	set desc = "Tag yourself for delivery through the disposals system."
	set category = "Abilities.Silicon"

	var/new_tag = tgui_input_list(src, "Select the desired destination.", "Set Mail Tag", GLOB.tagger_locations)

	if(!new_tag)
		mail_destination = ""
		return

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
	if(IS_GRABBING(H) && hat && !(H.l_hand && H.r_hand))
		var/obj/item/removed_hat = remove_hat(get_turf(src))
		H.put_in_hands(removed_hat)
		H.visible_message(span_danger("\The [H] removes \the [src]'s [removed_hat]."))
		return
	else
		return ..()
