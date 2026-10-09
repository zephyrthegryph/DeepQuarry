// DRONE ABILITIES

CAPABILITY_DEF(drone_mail, CAP_DRONE_MAIL, key = NONE)

/datum/capability/def/drone_mail/entries()
	return list(
		op("set_mail_tag", label("Set mail tag"), menu(button = "Set mail tag", bind = "ability_robot_set_mail_tag"),
			then(TYPE_PROC_REF(/mob/living/silicon/robot/drone, ability_set_mail_tag))))

/// Tag yourself for delivery through the disposals system.
/mob/living/silicon/robot/drone/proc/ability_set_mail_tag(datum/act/op/A)
	// A cancel answers "": the tag is cleared.
	open_request(src, /datum/prompt/choice, PROC_REF(mail_tag_chosen), answerer = src, title = "Set Mail Tag", question = "Select the desired destination.", choices = GLOB.tagger_locations, timeout = 0)
	return OP_OK

/mob/living/silicon/robot/drone/proc/mail_tag_chosen(datum/act/request/A)
	var/new_tag = A.answer ? A.answer.value : ""
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
