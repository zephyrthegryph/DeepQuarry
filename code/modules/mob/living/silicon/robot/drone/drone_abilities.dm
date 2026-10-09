// DRONE ABILITIES

CAPABILITY_DEF(drone_mail, CAP_DRONE_MAIL, key = NONE)

/datum/capability/def/drone_mail/entries()
	return list(
		op("set_mail_tag", label("Set mail tag"), menu(button = "Set mail tag", bind = "ability_robot_set_mail_tag"),
			asks(/datum/prompt/choice, fields = list("title" = "Set Mail Tag", "question" = "Select the desired destination.", "choices" = computed(TYPE_PROC_REF(/mob/living/silicon/robot/drone, mail_destinations)), "timeout" = 0), step = "tag"),
			on_interrupt(TYPE_PROC_REF(/mob/living/silicon/robot/drone, ability_mail_tag_cancelled)),
			then(TYPE_PROC_REF(/mob/living/silicon/robot/drone, ability_set_mail_tag))))

/// The destinations the disposals sorting knows.
/mob/living/silicon/robot/drone/proc/mail_destinations(datum/act/A)
	return GLOB.tagger_locations

/// Tag yourself for delivery through the disposals system; a cancel clears the tag (ability_mail_tag_cancelled()).
/mob/living/silicon/robot/drone/proc/ability_set_mail_tag(datum/act/op/A)
	mail_tag_chosen(A.answer?.value)
	return OP_OK

/mob/living/silicon/robot/drone/proc/ability_mail_tag_cancelled(datum/act/op/A)
	mail_tag_chosen("")

/mob/living/silicon/robot/drone/proc/mail_tag_chosen(new_tag)
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

	return TRUE
