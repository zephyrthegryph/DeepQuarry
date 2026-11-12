/datum/reagent/corophizine
	treatment_tags = list(TREAT_ANTIMICROBIAL = 1.3)
	factors = alist(STAT_ANTIMICROBIAL = ANTIBIO_SUPER)
	name = REAGENT_COROPHIZINE
	id = REAGENT_ID_COROPHIZINE
	description = "A wide-spectrum antibiotic drug. Powerful and uncomfortable in equal doses."
	taste_description = "burnt toast"
	reagent_state = LIQUID
	dermal_absorption = 0.2
	color = "#FFB0B0"
	mrate_static = TRUE
	overdose = 10
	overdose_mod = 1.5
	scannable = SCANNABLE_BENEFICIAL
	var/last_message_at = 0 // when the last status message was sent (-1: the effect ended)
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_DRUG

/datum/reagent/corophizine/affect_blood(mob/living/carbon/M, alien, removed)
	..()

	var/mob/living/carbon/human/H = M

	if(ishuman(M) && alien == IS_SLIME) //Everything about them is treated like a targetted organism. Widespread bodily function begins to fail.
		if(volume <= 0.1 && last_message_at != -1)
			last_message_at = -1
			to_chat(M, span_notice("Your body ceases its revolt."))
		else
			var/delay = (3 MINUTES)
			if(ELAPSED(src, last_message_at, CLOCK_WORLD) > delay)
				STAMP(src, last_message_at, CLOCK_WORLD)
				to_chat(M, span_critical("It feels like your body is revolting!"))
		M.status_at_least(STAT_CONFUSED, 7)
		M.injure(INJURY_BURN, removed * 2, source = src)
		M.injure(INJURY_TOXIN, removed * 2, source = src)
		var/toxic_load = M.injury_load(INJURY_CATEGORY_TOXIC)
		if(dose >= 5 && toxic_load >= 10) //It all starts going wrong.
			M.injure(INJURY_BLUNT, removed * 3, source = src)
			M.status_set(STAT_BLURRY, min(20, max(0, M.status_units(STAT_BLURRY) + 10)))
			if(prob(25))
				if(prob(25))
					to_chat(M, span_danger("Your pneumatic fluids seize for a moment."))
				M.status_at_least(STAT_STUNNED, 2)
				after(M, 3 SECONDS, TYPE_PROC_REF(/mob, status_at_least), with = list(STAT_WEAKENED, 2))
		if(dose >= 10 || toxic_load >= 25) //Internal skeletal tubes are rupturing, allowing the chemical to breach them.
			M.injure(INJURY_TOXIN, removed * 4, source = src)
			M.status_adjust(STAT_JITTERY, 5)
		if(dose >= 20 || toxic_load >= 60) //Core disentigration, cellular mass begins treating itself as an enemy, while maintaining regeneration. Slime-cancer.
			M.injure(INJURY_NEURAL, 2 * removed, source = src)
			M.adjust_nutrition(-20)
		if(M.injury_load(INJURY_CATEGORY_PHYSICAL) >= 60 && toxic_load >= 60 && M.injury_load(INJURY_CATEGORY_NEURAL) >= 30) //Total Structural Failure. Limbs start splattering.
			var/obj/item/organ/external/O = pick(H.organs)
			if(prob(20) && O.variant != LIMB_VARIANT_SLIME_CHEST && O.variant != LIMB_VARIANT_SLIME_GROIN)
				to_chat(M, span_critical("You feel your [O] begin to dissolve, before it sloughs from your body."))
				O.droplimb(TRUE, DROPLIMB_ACID)
		return

	//Based roughly on Levofloxacin's rather severe side-effects
	if(prob(20))
		M.status_at_least(STAT_CONFUSED, 5)
	if(prob(20))
		M.status_at_least(STAT_WEAKENED, 5)
	if(prob(20))
		M.status_adjust(STAT_DIZZY, 5)
	if(prob(20))
		M.status_at_least(STAT_HALLUCINATING, 10)

	//One of the levofloxacin side effects is 'spontaneous tendon rupture', which I'll immitate here. 1:1000 chance, so, pretty darn rare.
	if(ishuman(M) && rand(1,10000) == 1) //Adjusted to 1:10000
		var/obj/item/organ/external/eo = pick(H.organs) //Misleading variable name, 'organs' is only external organs
		// P2-K5: an injury the body resolves into a fracture, not a direct write.
		H.injure(INJURY_BLUNT, eo.min_broken_damage, eo, source = src, affliction = /datum/affliction/untreated_fracture)
