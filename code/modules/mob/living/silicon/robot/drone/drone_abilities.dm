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
	om_prompt(src, src, list("kind" = "list", "message" = "Select the desired destination.", "title" = "Set Mail Tag", "choices" = GLOB.tagger_locations, "on_cancel" = PROC_REF(mail_tag_cleared)), PROC_REF(mail_tag_chosen))
	return TRUE

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

	return TRUE
