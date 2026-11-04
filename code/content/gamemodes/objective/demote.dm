/datum/objective/anti_revolution/demote/find_target()
	..()
	if(target && target.current)
		set_explanation_text("[target.current.real_name], the [target.assigned_role]  has been classified as harmful to [using_map.company_name]'s goals. Demote [target.p_them()] to assistant.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/anti_revolution/demote/find_target_by_role(role, role_type=0)
	..(role, role_type)
	if(target && target.current)
		set_explanation_text("[target.current.real_name], the [!role_type ? target.assigned_role : target.special_role] has been classified as harmful to [using_map.company_name]'s goals. Demote [target.p_them()] to assistant.")
	else
		set_explanation_text("Free Objective")
	return target

/datum/objective/anti_revolution/demote/check_completion()
	if(target && target.current && ishuman(target.current))
		var/mob/living/carbon/human/H = target.current
		var/obj/item/card/id/I = H.get_equipped_item(SLOT_ID_ID)
		if(istype(I, /obj/item/pda))
			var/obj/item/pda/P = I
			I = P.id

		if(!istype(I)) return 1

		if(I.assignment == JOB_ALT_VISITOR) // Visitor not Assistant
			return 1
		else
			return 0
	return 1
