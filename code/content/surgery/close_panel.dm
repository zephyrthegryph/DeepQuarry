/datum/surgical_step/close_panel
	name = "Close Hatch"
	phase = SURGERY_PHASE_CLOSE
	allowed_tool_qualities = list(TOOL_SCREWDRIVER = 100)
	allowed_tools = list(/obj/item/coin = 50, /obj/item/material/knife = 50)
	min_depth = INCISION_MADE
	max_depth = FLESH_RETRACTED
	treatments = list(TREAT_PANEL_CLOSURE = 100)
	duration = 3 SECONDS
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "securing the maintenance hatch on"
	end_text = "secures the maintenance hatch on"
	fail_text = "slips, stripping a screw on"
	complication_kind = INJURY_BLUNT
	complication_amount = 3

/datum/surgical_step/close_panel/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	return I?.can_close()
