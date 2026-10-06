// Allergic reactions (was /datum/element/allergy, added to humans whose species has
// allergies). The medical life stage calls handle_allergic_reaction() directly for humans
// whose species has allergens.
/mob/living/carbon/human/proc/has_allergies()
	return species && (species.allergens || species.medallergens)

/mob/living/carbon/human/proc/handle_allergic_reaction(allergen_CE_amount)
	if(allergen_CE_amount <= 0)
		return
	//first, multiply the basic species-level value by our allergen effect rating, so consuming multiple seperate allergen typess simultaneously hurts more
	var/mob/living/carbon/human/H = src
	var/datum/species/species = H.species
	var/damage_severity = species.allergen_damage_severity * allergen_CE_amount
	var/disable_severity = species.allergen_disable_severity * allergen_CE_amount

	if(species.allergen_reaction & AG_PHYS_DMG)
		H.injure(INJURY_BLUNT, damage_severity, flags = INJURE_SILENT) // hives, swelling

	if(species.allergen_reaction & AG_BURN_DMG)
		H.injure(INJURY_CORROSIVE, damage_severity, flags = INJURE_SILENT) // blistering

	if(species.allergen_reaction & AG_TOX_DMG)
		H.injure(INJURY_TOXIN, damage_severity, flags = INJURE_SILENT)

	if(species.allergen_reaction & AG_OXY_DMG)
		// Airway swelling: an edema that can close the throat (vasopressor to reverse).
		var/datum/affliction/airway_edema/edema = H.body?.afflict(/datum/affliction/airway_edema)
		edema?.adjust_severity(damage_severity)
		if(prob(disable_severity/2))
			H.emote(pick("cough","gasp","choke"))

	if(species.allergen_reaction & AG_EMOTE)
		if(prob(disable_severity/2))
			H.emote(pick("pale","shiver","twitch"))

	if(species.allergen_reaction & AG_PAIN)
		H.injure(INJURY_PAIN, disable_severity)

	if(species.allergen_reaction & AG_WEAKEN)
		H.status_at_least(STAT_WEAKENED, disable_severity)

	if(species.allergen_reaction & AG_BLURRY)
		H.status_at_least(STAT_BLURRY, disable_severity)

	if(species.allergen_reaction & AG_SLEEPY)
		H.status_at_least(STAT_DROWSY, disable_severity)

	if(species.allergen_reaction & AG_CONFUSE)
		H.status_at_least(STAT_CONFUSED, disable_severity/4)

	if(species.allergen_reaction & AG_GIBBING)
		if(prob(disable_severity / 6))
			after(H, rand(0.3 SECONDS,0.6 SECONDS), TYPE_PROC_REF(/mob/living/carbon/human, allergy_gib))
		else if(prob(disable_severity))
			H.emote(pick(list("whimper","belch","belch","belch","choke","shiver")))
			H.status_at_least(STAT_WEAKENED, disable_severity / 3)

	if(species.allergen_reaction & AG_SNEEZE)
		if(prob(disable_severity/3))
			if(prob(20))
				to_chat(H, span_warning("You go to sneeze, but it gets caught in your sinuses!"))
			else if(prob(80))
				if(prob(30))
					to_chat(H, span_warning("You feel like you are about to sneeze!"))
				after(H, rand(0.75,3) SECOND, TYPE_PROC_REF(/mob/living/carbon/human, allergy_sneeze))

	if(species.allergen_reaction & AG_COUGH)
		if(prob(disable_severity/2))
			H.emote(pick(list("cough","cough","cough","gasp","choke")))
			if(prob(10))
				H.drop_item()

// Helpers for delayed actions
/mob/living/carbon/human/proc/allergy_sneeze()
	SHOULD_NOT_OVERRIDE(TRUE)
	var/mob/living/carbon/human/H = src
	H.emote("sneeze")
	if(prob(23))
		H.drop_item()

/mob/living/carbon/human/proc/allergy_gib(remaining)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/mob/living/carbon/human/H = src
	if(remaining > 0)
		H.emote(pick(list("whimper","belch","shiver")))
		remaining--
		after(H, rand(1,1.2) SECOND, TYPE_PROC_REF(/mob/living/carbon/human, allergy_gib), with = list(remaining))
		return
	H.emote("belch")
	H.gib()
