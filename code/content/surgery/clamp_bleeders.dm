// --- Site treatment: clamp, set, close ----------------------------------------------------

/datum/surgical_step/clamp_bleeders
	name = "Clamp Bleeders"
	finds = TRUE
	book_category = "Vascular"
	about = "Clamping the cut vessels at the edge of the incision. An open site bleeds until it is clamped, and faster in a patient whose blood does not clot."
	phase = SURGERY_PHASE_ACCESS
	priority = 1
	allowed_tools = list(
		/obj/item/surgical/hemostat = 100,
		/obj/item/stack/cable_coil = 75,
		/obj/item/assembly/mousetrap = 25,
	)
	part_biology = BIOLOGY_ORGANIC
	min_depth = INCISION_MADE
	treatments = list(TREAT_HEMOSTATIC = 30)
	duration = 3 SECONDS
	begin_text = "clamping bleeders in"
	end_text = "clamps the bleeders in"
	fail_text = "slips, tearing blood vessels in"
	pain_text = "The pain in your %PART% is maddening!"
	// A torn vessel: an arterial bleed.
	complication_kind = INJURY_CUT
	complication_amount = 10
	complication_affliction = /datum/affliction/wound/internal_bleeding

/datum/surgical_step/clamp_bleeders/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	return I?.needs_clamp()

/// The open site's own bleeders are a finding: the incision is the source.
/datum/surgical_step/clamp_bleeders/findings(mob/living/carbon/human/target, obj/item/organ/external/part, full)
	. = list()
	var/datum/affliction/surgical_incision/I = part.get_incision()
	if(I?.needs_clamp())
		. += list(surgical_finding_row("unclamped bleeders", part, I, src))
