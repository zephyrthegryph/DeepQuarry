/datum/reagent/adrenaline
	// The code-blue drug: restarts electrical activity in a flatlined heart
	// and shrinks swollen airway tissue. The allergic reaction is blunted; open wounds bleed half again as fast while it drives the pulse up.
	treatment_tags = list(TREAT_VASOPRESSOR = 1.2, TREAT_STIMULANT = 0.3)
	factors = alist(STAT_ANALGESIA = 60, STAT_SLOWDOWN = -3, STAT_PENALTY_SCALE = 0.5, STAT_ALLERGY = -15, STAT_BLEEDING = 1.5)
	strains = alist(O_HEART = DRUG_STRAIN_MODERATE)
	species_factors = alist(IS_DIONA = null)
	name = REAGENT_ADRENALINE
	id = REAGENT_ID_ADRENALINE
	description = "Adrenaline is a hormone used as a drug to treat cardiac arrest (it coaxes asystole toward a shockable rhythm during chest compressions), anaphylaxis and shock. It makes open wounds bleed faster and strains the heart, and it must never be given with synaptizine."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	scannable = SCANNABLE_BENEFICIAL
	color = "#C8A5DC"
	mrate_static = TRUE
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/adrenaline
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/adrenaline/affect_blood(mob/living/carbon/M, alien, removed)
	M.status_set(STAT_PARALYZED, 0)
	M.status_set(STAT_WEAKENED, 0)
	M.injure(INJURY_TOXIN, rand(3), source = src)
