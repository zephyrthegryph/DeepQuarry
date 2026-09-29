/datum/power/changeling/mimicvoice
	name = "Mimic Voice"
	desc = "We shape our vocal glands to sound like a desired voice."
	helptext = "Will turn your voice into the name that you enter. We must constantly expend chemicals to maintain our form like this"
	ability_icon_state = "ling_mimic_voice"
	genomecost = 1
	verbpath = /mob/proc/changeling_mimicvoice

// Fake Voice

/mob/proc/changeling_mimicvoice()
	set category = "Changeling"
	set name = "Mimic Voice"
	set desc = "Shape our vocal glands to form a voice of someone we choose. We cannot regenerate chemicals when mimicing."


	var/datum/changeling/changeling = changeling_power()
	if(!changeling)	return

	if(changeling.mimicing)
		changeling.set_mimicing("")
		to_chat(src, span_notice("We return our vocal glands to their original location."))
		return

	var/mimic_voice = rerun_ask(src, "a1", PROC_REF(changeling_mimicvoice), args, /datum/om/prompt/text, message = "Enter a name to mimic.", title = "Mimic Voice", max_length = MAX_NAME_LEN)
	if(isnull(mimic_voice))
		return
	if(!mimic_voice)
		return

	changeling.set_mimicing(mimic_voice)

	to_chat(src, span_notice("We shape our glands to take the voice of <b>[mimic_voice]</b>, this will stop us from regenerating chemicals while active."))
	to_chat(src, span_notice("Use this power again to return to our original voice and reproduce chemicals again."))

	feedback_add_details("changeling_powers","MV")

DECLARE_REPEAT(/datum/changeling, 4 SECONDS, mimic_drain, "mimicing")

/// Mimicry costs a chemical every 4 seconds while it lasts (DECLARE_REPEAT while mimicing).
/datum/changeling/proc/mimic_drain()
	if(!owner?.mind)
		return REPEAT_STOP
	chem_charges = max(chem_charges - 1, 0)
