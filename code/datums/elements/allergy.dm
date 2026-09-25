// Element for handling allergic reactions. This is only added to humans with allergies actually set in their species datum.
// Is added to the mob in species.produceCopy() after all traits have been resolved.
/datum/element/allergy/Attach(datum/target)
	. = ..()
	if(!ishuman(target))
		return ELEMENT_INCOMPATIBLE
	RegisterSignal(target, COMSIG_HANDLE_ALLERGENS, PROC_REF(handle_allergic_reaction), override = TRUE)

/datum/element/allergy/Detach(datum/target)
	. = ..()
	UnregisterSignal(target, COMSIG_HANDLE_ALLERGENS)

/datum/element/allergy/proc/handle_allergic_reaction(datum/source,allergen_CE_amount)
	SIGNAL_HANDLER
	if(allergen_CE_amount <= 0)
		return
	//first, multiply the basic species-level value by our allergen effect rating, so consuming multiple seperate allergen typess simultaneously hurts more
	var/mob/living/carbon/human/H = source
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
		H.status_at_least(EFFECT_WEAKENED, disable_severity)

	if(species.allergen_reaction & AG_BLURRY)
		H.status_at_least(EFFECT_BLURRY, disable_severity)

	if(species.allergen_reaction & AG_SLEEPY)
		H.status_at_least(EFFECT_DROWSY, disable_severity)

	if(species.allergen_reaction & AG_CONFUSE)
		H.status_at_least(EFFECT_CONFUSED, disable_severity/4)

	if(species.allergen_reaction & AG_GIBBING)
		if(prob(disable_severity / 6))
			addtimer(CALLBACK(src, PROC_REF(allergy_gib), H), rand(3,6), TIMER_DELETE_ME)
		else if(prob(disable_severity))
			H.emote(pick(list("whimper","belch","belch","belch","choke","shiver")))
			H.status_at_least(EFFECT_WEAKENED, disable_severity / 3)

	if(species.allergen_reaction & AG_SNEEZE)
		if(prob(disable_severity/3))
			if(prob(20))
				to_chat(H, span_warning("You go to sneeze, but it gets caught in your sinuses!"))
			else if(prob(80))
				if(prob(30))
					to_chat(H, span_warning("You feel like you are about to sneeze!"))
				addtimer(CALLBACK(src, PROC_REF(allergy_sneeze), H), rand(0.75,3) SECOND, TIMER_DELETE_ME)

	if(species.allergen_reaction & AG_COUGH)
		if(prob(disable_severity/2))
			H.emote(pick(list("cough","cough","cough","gasp","choke")))
			if(prob(10))
				H.drop_item()

// Helpers for delayed actions
/datum/element/allergy/proc/allergy_sneeze(mob/living/carbon/human/H)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	H.emote("sneeze")
	if(prob(23))
		H.drop_item()

/datum/element/allergy/proc/allergy_gib(mob/living/carbon/human/H,remaining)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(remaining > 0)
		H.emote(pick(list("whimper","belch","shiver")))
		remaining--
		addtimer(CALLBACK(src, PROC_REF(allergy_gib), H, remaining), rand(1,1.2) SECOND, TIMER_DELETE_ME)
		return
	H.emote("belch")
	H.gib()
