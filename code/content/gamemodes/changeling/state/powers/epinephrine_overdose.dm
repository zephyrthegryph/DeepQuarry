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
	C.reagents.add_reagent("epinephrine", 20)

	if(changeling.recursive_enhancement)
		C.apply_body_effect(/datum/body_effect/unstoppable, 30 SECONDS)

	feedback_add_details("changeling_powers","UNS")
	return 1

/datum/reagent/epinephrine
	// Anaphylaxis: the allergic reaction is blunted. Open wounds bleed half again as fast while it drives the pulse up.
	factors = alist(STAT_ANALGESIA = 60, STAT_SLOWDOWN = -3, STAT_PENALTY_SCALE = 0.5, STAT_ALLERGY = -15, STAT_BLEEDING = 1.5)
	strains = alist(O_HEART = DRUG_STRAIN_MODERATE)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_EPINEPHRINE
	id = REAGENT_ID_EPINEPHRINE
	description = "Adrenaline: a vasopressor for cardiac arrest (it coaxes asystole toward a shockable rhythm during chest compressions), for anaphylaxis and for shock. It makes open wounds bleed faster and strains the heart, and it must never be given with synaptizine."
	reagent_state = LIQUID
	color = "#C8A5DC"
	metabolism = REM * 2
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/epinephrine
	treatment_tags = list(TREAT_ANALGESIC = 2.0, TREAT_STIMULANT = 1.0, TREAT_VASOPRESSOR = 1.0, TREAT_CIRCULATORY = 0.5)
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)

/datum/reagent/epinephrine/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_adjust(STAT_PARALYZED, -2)
	M.status_adjust(STAT_STUNNED, -2)
	M.status_adjust(STAT_WEAKENED, -2)
	M.injure(INJURY_TOXIN, removed * 2.5, source = src) //It gives you 20units of epinephrine. 50 toxins damage. 1 Toxin per tick.
	..()
	return
