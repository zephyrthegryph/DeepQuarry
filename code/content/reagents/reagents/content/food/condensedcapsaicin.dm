/datum/reagent/condensedcapsaicin
	name = REAGENT_CONDENSEDCAPSAICIN
	id = REAGENT_ID_CONDENSEDCAPSAICIN
	scannable = SCANNABLE_ADVANCED
	description = "A chemical agent used for self-defense and in police work."
	taste_description = "fire"
	dermal_absorption = 0
	taste_mult = 10
	reagent_state = LIQUID
	touch_met = 50 // Get rid of it quickly
	ingest_met = REM
	color = "#B31008"
	cup_prefix = "dangerously hot"
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_WEAPONS
	immune_species_blood = SPECIES_TAG_BIT(IS_DIONA)
	/// SPECIES_TAG_BIT mask of species whose exposed flesh the spray burns (gel bodies).
	var/skin_burned_species = SPECIES_TAG_BIT(IS_SLIME)

/datum/reagent/condensedcapsaicin/affect_blood(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 0.5 * removed, source = src)

/datum/reagent/condensedcapsaicin/affect_touch(mob/living/carbon/M, alien, removed)
	var/eyes_covered = 0
	var/mouth_covered = 0

	var/head_covered = 0
	var/arms_covered = 0 //These are used for the effects on slime-based species.
	var/legs_covered = 0
	var/hands_covered = 0
	var/feet_covered = 0
	var/chest_covered = 0
	var/groin_covered = 0

	var/obj/item/safe_thing = null

	var/effective_strength = 5
	// Species whose whole exposed surface burns (checked per body part below).
	var/skin_burns = species_in(M, skin_burned_species)


	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return
		if(H.get_equipped_item(SLOT_ID_HEAD))
			if(worn_of(H.get_equipped_item(SLOT_ID_HEAD)).covers & EYES)
				eyes_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_HEAD)
			if((worn_of(H.get_equipped_item(SLOT_ID_HEAD)).covers & FACE) && !(worn_of(H.get_equipped_item(SLOT_ID_HEAD)).flags & FLEXIBLEMATERIAL))
				mouth_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_HEAD)
		if(H.get_equipped_item(SLOT_ID_MASK))
			if(!eyes_covered && worn_of(H.get_equipped_item(SLOT_ID_MASK)).covers & EYES)
				eyes_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_MASK)
			if(!mouth_covered && (worn_of(H.get_equipped_item(SLOT_ID_MASK)).covers & FACE) && !(worn_of(H.get_equipped_item(SLOT_ID_MASK)).flags & FLEXIBLEMATERIAL))
				mouth_covered = 1
				safe_thing = H.get_equipped_item(SLOT_ID_MASK)
		if(H.get_equipped_item(SLOT_ID_EYES) && worn_of(H.get_equipped_item(SLOT_ID_EYES)).covers & EYES)
			if(!eyes_covered)
				eyes_covered = 1
				if(!safe_thing)
					safe_thing = H.get_equipped_item(SLOT_ID_EYES)
		if(skin_burns)
			for(var/obj/item/clothing/C in H.get_worn_clothing())
				if(worn_of(C).covers & HEAD)
					head_covered = 1
				if(worn_of(C).covers & UPPER_TORSO)
					chest_covered = 1
				if(worn_of(C).covers & LOWER_TORSO)
					groin_covered = 1
				if(worn_of(C).covers & LEGS)
					legs_covered = 1
				if(worn_of(C).covers & ARMS)
					arms_covered = 1
				if(worn_of(C).covers & HANDS)
					hands_covered = 1
				if(worn_of(C).covers & FEET)
					feet_covered = 1
				if(head_covered && chest_covered && groin_covered && legs_covered && arms_covered && hands_covered && feet_covered)
					break
	if(eyes_covered && mouth_covered)
		to_chat(M, span_warning("Your [safe_thing] protects you from the pepperspray!"))
		if(!skin_burns)
			return
	else if(eyes_covered)
		to_chat(M, span_warning("Your [safe_thing] protects you from most of the pepperspray!"))
		M.status_at_least(STAT_BLURRY, effective_strength * 3)
		M.status_at_least(STAT_BLINDED, effective_strength)
		M.status_at_least(STAT_STUNNED, 5)
		M.status_at_least(STAT_WEAKENED, 5)
		if(!skin_burns)
			return
	else if(mouth_covered) // Mouth cover is better than eye cover
		to_chat(M, span_warning("Your [safe_thing] protects your face from the pepperspray!"))
		M.status_at_least(STAT_BLURRY, effective_strength)
		if(!skin_burns)
			return
	else// Oh dear :D
		to_chat(M, span_warning("You're sprayed directly in the eyes with pepperspray!"))
		M.status_at_least(STAT_BLURRY, effective_strength * 5)
		M.status_at_least(STAT_BLINDED, effective_strength * 2)
		M.status_at_least(STAT_STUNNED, 5)
		M.status_at_least(STAT_WEAKENED, 5)
		if(!skin_burns)
			return
	if(skin_burns)
		if(!head_covered)
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your head burns!"))
			M.apply_effect(5 * effective_strength, AGONY, 0)
		if(!chest_covered)
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your chest burns!"))
			M.apply_effect(5 * effective_strength, AGONY, 0)
		if(!groin_covered && prob(75))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your groin burns!"))
			M.apply_effect(3 * effective_strength, AGONY, 0)
		if(!arms_covered && prob(45))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your arms burns!"))
			M.apply_effect(3 * effective_strength, AGONY, 0)
		if(!legs_covered && prob(45))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your legs burns!"))
			M.apply_effect(3 * effective_strength, AGONY, 0)
		if(!hands_covered && prob(20))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your hands burns!"))
			M.apply_effect(effective_strength / 2, AGONY, 0)
		if(!feet_covered && prob(20))
			if(prob(33))
				to_chat(M, span_warning("The exposed flesh on your feet burns!"))
			M.apply_effect(effective_strength / 2, AGONY, 0)

/datum/reagent/condensedcapsaicin/affect_ingest(mob/living/carbon/M, alien, removed)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(!H.can_feel_pain())
			return
	if(dose == metabolism)
		to_chat(M, span_danger("You feel like your insides are burning!"))
	else
		M.apply_effect(4, AGONY, 0)
		if(prob(5))
			act_message(M, null, MSG_SELF(span_danger("You feel like your insides are burning!")), \
				MSG_OTHERS(span_warning("%U% [pick("dry heaves!","coughs!","splutters!")]")))
