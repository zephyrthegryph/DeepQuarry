/datum/power/changeling/mimicvoice
	name = "Mimic Voice"
	desc = "We shape our vocal glands to sound like a desired voice."
	helptext = "Will turn your voice into the name that you enter. We must constantly expend chemicals to maintain our form like this"
	ability_icon_state = "ling_mimic_voice"
	genomecost = 1
	verbpath = /mob/proc/changeling_mimicvoice

// Fake Voice

/mob/proc/changeling_mimicvoice()
	set category = VERB_CAT_CHANGELING
	set name = "Mimic Voice"
	set desc = "Shape our vocal glands to form a voice of someone we choose. We cannot regenerate chemicals when mimicing."


	return changeling_mimicvoice_review()

/mob/proc/changeling_mimicvoice_review(answered = FALSE, reply)
	var/datum/changeling/changeling = changeling_power()
	if(!changeling)	return

	if(changeling.mimicing)
		changeling.set_mimicing("")
		to_chat(src, span_notice("We return our vocal glands to their original location."))
		return

	if(!answered)
		open_request(src, /datum/prompt/text, PROC_REF(changeling_mimicvoice_answered), answerer = src, title = "Mimic Voice", question = "Enter a name to mimic.", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)
		return
	var/mimic_voice = reply
	if(isnull(mimic_voice))
		return
	if(!mimic_voice)
		return

	changeling.set_mimicing(mimic_voice)

	to_chat(src, span_notice("We shape our glands to take the voice of <b>[mimic_voice]</b>, this will stop us from regenerating chemicals while active."))
	to_chat(src, span_notice("Use this power again to return to our original voice and reproduce chemicals again."))

	feedback_add_details("changeling_powers","MV")

/// Mimicry costs a chemical every 4 seconds while it lasts (every() while mimicing).
/datum/changeling/proc/mimic_drain(datum/act/timer/A)
	if(!owner?.mind)
		return
	chem_charges = max(chem_charges - 1, 0)

/// Replay the current changeling state and choices after an accepted native answer.
/mob/proc/changeling_mimicvoice_answered(datum/act/request/context)
	if(!context.answer)
		return
	changeling_mimicvoice_review(TRUE, context.answer.value)
	if(!QDELETED(src))
		SStgui.update_uis(src)
