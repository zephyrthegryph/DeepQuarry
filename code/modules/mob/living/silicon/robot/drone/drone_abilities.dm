// DRONE ABILITIES

/datum/interaction/ability/self/robot_set_mail_tag
	id = ABILITY_ID_ROBOT_SET_MAIL_TAG
	name = "Set mail tag"
	category = ABILITY_CAT_UTILITY
	effect = /mob/living/silicon/robot/drone/proc/dq_do_set_mail_tag

/datum/interaction/ability/self/robot_set_mail_tag/applies_to(atom/target)
	return istype(target, /mob/living/silicon/robot/drone)

/// Tag yourself for delivery through the disposals system.
/mob/living/silicon/robot/drone/proc/dq_do_set_mail_tag(mob/actor, obj/item/held, datum/interaction/ability/interaction)
	// A cancel answers "": the tag is cleared.
	open_request(src, /datum/prompt/choice, PROC_REF(mail_tag_chosen), answerer = src, title = "Set Mail Tag", question = "Select the desired destination.", choices = GLOB.tagger_locations, timeout = 0)
	return TRUE

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
