// Harm a crew member, making an example of them
/datum/objective/harm
	var/already_completed = 0

/datum/objective/harm/find_target()
	..()
	if(target && target.current)
		set_explanation_text("Make an example of [target.current.real_name], the [target.assigned_role]. Break one of their bones, detach one of their limbs or disfigure their face. Make sure they're alive when you do it.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/harm/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("Make an example of [target.current.real_name], the [!role_type ? target.assigned_role : target.special_role]. Break one of their bones, detach one of their limbs or disfigure their face. Make sure they're alive when you do it.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/harm/check_completion()
	if(already_completed)
		return 1

	if(target && target.current && ishuman(target.current))
		if(target.current.stat == DEAD)
			return 0

		var/mob/living/carbon/human/H = target.current
		for(var/obj/item/organ/external/E in H.organs)
			if(E.is_fractured())
				return 1
		for(var/limb_tag in H.species.has_limbs) //todo check prefs for robotic limbs and amputations.
			var/list/organ_data = H.species.has_limbs[limb_tag]
			var/limb_type = organ_data["path"]
			var/found
			for(var/obj/item/organ/external/E in H.organs)
				if(limb_type == E.type)
					found = 1
					break
			if(!found)
				return 1

		var/obj/item/organ/external/head/head = H.get_organ(BP_HEAD)
		if(head.disfigured)
			return 1
	return 0
