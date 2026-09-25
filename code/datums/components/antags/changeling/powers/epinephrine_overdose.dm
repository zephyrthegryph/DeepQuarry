//Updated
/datum/power/changeling/epinephrine_overdose
	name = "Epinephrine Overdose"
	desc = "We evolve additional sacs of adrenaline throughout our body."
	helptext = "We can instantly recover from stuns and reduce the effect of future stuns, but we will suffer toxicity in the long term.  Can be used while unconscious."
	enhancedtext = "Immunity from most disabling effects for 30 seconds."
	ability_icon_state = "ling_epinepherine_overdose"
	genomecost = 2
	verbpath = /mob/proc/changeling_epinephrine_overdose

/datum/modifier/unstoppable
	name = "unstoppable"
	desc = "We feel limitless amounts of energy surge in our veins.  Nothing can stop us!"

	stacks = MODIFIER_STACK_EXTEND
	on_created_text = span_notice("We feel unstoppable!")
	on_expired_text = span_warning("We feel our newfound energy fade...")
	factors = alist(BF_DISABLE_DURATION = 0)

//Recover from stuns.
/mob/proc/changeling_epinephrine_overdose()
	set category = "Changeling"
	set name = "Epinephrine Overdose (30)"
	set desc = "Removes all stuns instantly, and reduces future stuns."

	var/datum/component/antag/changeling/changeling = changeling_power(30,0,100,UNCONSCIOUS)
	if(!changeling)
		return 0
	changeling.chem_charges -= 30

	var/mob/living/carbon/human/C = src
	to_chat(C, span_notice("Energy rushes through us.  [C.lying ? "We arise." : ""]"))
	C.set_stat(CONSCIOUS)
	C.status_set(EFFECT_PARALYZED, 0)
	C.status_set(EFFECT_STUNNED, 0)
	C.status_set(EFFECT_WEAKENED, 0)
	C.lying = 0
	C.update_canmove()
	C.reagents.add_reagent("epinephrine", 20)

	if(changeling.recursive_enhancement)
		C.add_modifier(/datum/modifier/unstoppable, 30 SECONDS)

	feedback_add_details("changeling_powers","UNS")
	return 1

/datum/reagent/epinephrine
	factors = alist(BF_ANALGESIA = 60, BF_SLOWDOWN = -3, BF_PENALTY_SCALE = 0.5)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_EPINEPHRINE
	id = REAGENT_ID_EPINEPHRINE
	description = "A chemically naturally produced by the body while in fight-or-flight mode. Greatly increases one's strength."
	reagent_state = LIQUID
	color = "#C8A5DC"
	metabolism = REM * 2
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/epinephrine
	treatment_tags = list(TREAT_ANALGESIC = 2.0, TREAT_STIMULANT = 1.0, TREAT_VASOPRESSOR = 1.0)

/datum/reagent/epinephrine/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_DIONA)
		return
	M.status_adjust(EFFECT_PARALYZED, -2)
	M.status_adjust(EFFECT_STUNNED, -2)
	M.status_adjust(EFFECT_WEAKENED, -2)
	M.injure(INJURY_TOXIN, removed * 2.5, source = src) //It gives you 20units of epinephrine. 50 toxins damage. 1 Toxin per tick.
	..()
	return
