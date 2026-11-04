/datum/surgical_step/set_bone
	name = "Set Bone"
	phase = SURGERY_PHASE_CLOSE
	priority = 1
	allowed_tools = list(
		/obj/item/surgical/bonesetter = 100,
		/obj/item/surgical/bonegel = 100,
		/obj/item/surgical/bone_clamp = 100,
	)
	allowed_tool_qualities = list(TOOL_WRENCH = 75, TOOL_SCREWDRIVER = 60)
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_BONE_SETTING = 100)
	duration = 4 SECONDS
	pain = 50
	begin_text = "setting the bone in"
	end_text = "sets the bone in"
	fail_text = "slips, grinding the broken bone in"
	pain_text = "Something in your %PART% is causing you a lot of pain!"
	complication_kind = INJURY_BLUNT
	complication_amount = 10

/// Needed for an open bone layer or a fracture. TREAT_BONE_SETTING mends the
/// fracture affliction, and with it the fracture.
/datum/surgical_step/set_bone/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	if(I?.needs_bone_setting())
		return TRUE
	if(part.is_fractured())
		return TRUE
	return ..()
