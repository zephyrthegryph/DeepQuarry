/datum/surgical_step/cauterize
	name = "Cauterize Incision"
	phase = SURGERY_PHASE_CLOSE
	allowed_tools = list(
		/obj/item/surgical/cautery = 100,
		/obj/item/clothing/mask/smokable/cigarette = 75,
		/obj/item/flame/lighter = 50,
		/obj/item/weldingtool = 25,
	)
	part_biology = BIOLOGY_ORGANIC
	min_depth = INCISION_MADE
	max_depth = FLESH_RETRACTED
	treatments = list(TREAT_SURGICAL_CLOSURE = 100)
	duration = 4 SECONDS
	begin_text = "cauterizing the incision on"
	end_text = "cauterizes the incision on"
	fail_text = "slips, leaving a burn on"
	pain_text = "Your %PART% is being burned!"
	complication_kind = INJURY_BURN
	complication_amount = 3

/datum/surgical_step/cauterize/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	return I?.can_close()
