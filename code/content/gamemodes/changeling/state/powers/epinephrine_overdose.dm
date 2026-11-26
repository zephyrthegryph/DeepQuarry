//Updated
/datum/power/changeling/epinephrine_overdose
	name = "Epinephrine Overdose"
	desc = "We evolve additional sacs of adrenaline throughout our body."
	helptext = "We can instantly recover from stuns and reduce the effect of future stuns, but we will suffer toxicity in the long term.  Can be used while unconscious."
	enhancedtext = "Immunity from most disabling effects for 30 seconds."
	ability_icon_state = "ling_epinepherine_overdose"
	genomecost = 2
	verbpath = /mob/proc/changeling_epinephrine_overdose

/datum/body_effect/unstoppable
	name = "unstoppable"
	desc = "We feel limitless amounts of energy surge in our veins.  Nothing can stop us!"

	stacks = MODIFIER_STACK_EXTEND
	on_created_text = span_notice("We feel unstoppable!")
	on_expired_text = span_warning("We feel our newfound energy fade...")
	factors = alist(STAT_DISABLE_DURATION = 0)

//Recover from stuns.
/mob/proc/changeling_epinephrine_overdose()

	var/datum/changeling/changeling = changeling_power(30,0,100,UNCONSCIOUS)
	if(!changeling)
		return 0
	changeling.chem_charges -= 30

	var/mob/living/carbon/human/C = src
	to_chat(C, span_notice("Energy rushes through us.  [C.lying ? "We arise." : ""]"))
	C.set_stat(CONSCIOUS)
	C.status_set(STAT_PARALYZED, 0)
	C.status_set(STAT_STUNNED, 0)
	C.status_set(STAT_WEAKENED, 0)
	C.set_lying(0)
	C.update_canmove()
	C.reagents.add_reagent(REAGENT_ID_ADRENALINE, 20)

	if(changeling.recursive_enhancement)
		C.apply_body_effect(/datum/body_effect/unstoppable, 30 SECONDS)

	feedback_add_details("changeling_powers","UNS")
	return 1
