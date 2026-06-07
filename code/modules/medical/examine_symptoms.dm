// Examine surface for externally-visible condition symptoms.
//
// When someone examines a patient, /mob/living/carbon/human/examine
// calls dq_externally_visible_symptom_lines() and renders each line as
// a warning. We walk the patient's active conditions, gather every
// active symptom whose audience bitfield includes
// SYMPTOM_AUDIENCE_PUBLIC, and emit one human-readable line per unique
// symptom.
//
// Why this exists separately from the stochastic public_emotes:
// emotes fire at low probability per tick and only happen "in the
// moment". A patient sitting still with a torn artery should still
// LOOK like they're bleeding when you stop and look at them — not
// just when the emote happens to fire.

/mob/living/carbon/human/proc/dq_externally_visible_symptom_lines()
	var/list/lines = list()
	var/list/seen = list()
	for(var/datum/medical_issue/condition/C as anything in get_all_conditions())
		if(!C.active_symptoms)
			continue
		for(var/datum/medical_symptom/S as anything in C.active_symptoms)
			if(!(S.audiences & SYMPTOM_AUDIENCE_PUBLIC))
				continue
			if(S.type in seen)
				continue
			seen[S.type] = TRUE
			if(S.examine_line)
				lines += S.examine_line
			else
				// Generic fallback if a future symptom forgets the line.
				lines += "Their [S.name] is plainly visible."
	return lines
