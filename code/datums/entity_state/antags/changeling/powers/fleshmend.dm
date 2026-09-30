/datum/power/changeling/fleshmend
	name = "Fleshmend"
	desc = "Begins a slow regeneration of our form.  Does not effect stuns or chemicals."
	helptext = "Can be used while unconscious."
	enhancedtext = "Healing is twice as effective."
	ability_icon_state = "ling_fleshmend"
	genomecost = 1
	verbpath = /mob/proc/changeling_fleshmend

//Starts healing you every second for 50 seconds. Can be used whilst unconscious.
/mob/proc/changeling_fleshmend()
	set category = VERB_CAT_CHANGELING
	set name = "Fleshmend (10)"
	set desc = "Begins a slow rengeration of our form.  Does not effect stuns or chemicals."

	var/mob/living/C = src
	var/datum/changeling/changeling = changeling_power(10,0,100,UNCONSCIOUS)
	if(!changeling)
		return FALSE
	if(C.has_body_effect(/datum/body_effect/fleshmend))
		to_chat(src, span_notice("We are already under the effect of fleshmend."))
		return FALSE

	changeling.chem_charges -= 10

	if(changeling.recursive_enhancement)
		C.apply_body_effect(/datum/body_effect/fleshmend/recursive, 50 SECONDS)
	else
		C.apply_body_effect(/datum/body_effect/fleshmend, 50 SECONDS)

	feedback_add_details("changeling_powers","FM")
	return TRUE

/datum/body_effect/fleshmend
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = "Fleshmend"
	desc = "We are regenerating"
	on_created_text = "We have begun to regenerate our body."
	on_expired_text = "Our regeneration has ceased."

// For changelings who bought the Recursive Enhancement evolution.
/datum/body_effect/fleshmend/recursive
	name = "Advanced Fleshmend"
	desc = "We have begun regenerating our body, and more rapidly than normal."

//These were previously 2 or 4 per second, now it's 4 or 8 per 2 seconds
/datum/body_effect/fleshmend/on_tick(mob/living/L)
	L.mend(TREAT_TISSUE_REPAIR, 4)
	L.mend(TREAT_OXYGENATION, 4)
	L.mend(TREAT_BURN_CARE, 4)

/datum/body_effect/fleshmend/recursive/on_tick(mob/living/L)
	L.mend(TREAT_TISSUE_REPAIR, 8)
	L.mend(TREAT_OXYGENATION, 8)
	L.mend(TREAT_BURN_CARE, 8)
