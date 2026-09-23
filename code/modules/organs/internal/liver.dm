/obj/item/organ/internal/liver
	name = "liver"
	icon_state = "liver"
	organ_tag = O_LIVER
	parent_organ = BP_GROIN

/obj/item/organ/internal/liver/process()
	..()
	if(!iscarbon(owner)) return

	if(owner.life_tick % PROCESS_ACCURACY == 0)

		//High toxins levels are dangerous
		if(owner.injury_load(INJURY_CATEGORY_TOXIC) >= 50 && !owner.reagents.has_reagent(REAGENT_ID_ANTITOXIN))
			//Healthy liver suffers on its own
			if (src.damage < min_broken_damage)
				apply_lesion_damage(0.2 * PROCESS_ACCURACY, /datum/affliction/lesion/toxic_injury, TRUE)
			//Damaged one shares the fun
			else
				var/obj/item/organ/internal/O = pick(owner.internal_organs)
				if(O)
					O.apply_lesion_damage(0.2 * PROCESS_ACCURACY, /datum/affliction/lesion/toxic_injury, TRUE)


		// Get the effectiveness of the liver.
		var/filter_effect = 3
		if(is_bruised())
			filter_effect -= 1
		if(is_broken())
			filter_effect -= 2

		// Do some reagent processing.
		if(owner.factor(BF_HEPATOTOXICITY))
			apply_lesion_damage(owner.factor(BF_HEPATOTOXICITY) * 0.1 * PROCESS_ACCURACY, /datum/affliction/lesion/toxic_injury, prob(1)) // Chance to warn them
			if(filter_effect < 2)	//Liver is badly damaged, you're drinking yourself to death
				owner.injure(INJURY_TOXIN, owner.factor(BF_HEPATOTOXICITY) * 0.2 * PROCESS_ACCURACY, flags = INJURE_SILENT)
			if(filter_effect < 3)
				owner.injure(INJURY_TOXIN, owner.factor(BF_HEPATOTOXICITY) * 0.1 * PROCESS_ACCURACY, flags = INJURE_SILENT)

		// General organ damage from withdraw
		if(prob(20) && owner.factor(BF_WITHDRAWAL))
			apply_lesion_damage(owner.factor(BF_WITHDRAWAL) * 0.05 * PROCESS_ACCURACY, /datum/affliction/lesion/toxic_injury, prob(1)) // Chance to warn them
			if(filter_effect < 2)	//Withdrawls intensified
				owner.injure(INJURY_TOXIN, owner.factor(BF_WITHDRAWAL) * 0.2 * PROCESS_ACCURACY, flags = INJURE_SILENT)
			if(filter_effect < 3)
				owner.injure(INJURY_TOXIN, owner.factor(BF_WITHDRAWAL) * 0.1 * PROCESS_ACCURACY, flags = INJURE_SILENT)


/obj/item/organ/internal/liver/handle_germ_effects()
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	//Pyogenic Abscess
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("There's a sharp pain in your upper-right abdomen!",1)
	if (. >= 2)
		if(prob(1) && owner.injury_load(INJURY_CATEGORY_TOXIC) < owner.get_endurance()*0.3)
			//to_chat(owner, "") //Toxins provide their own messages for pain
			owner.injure(INJURY_TOXIN, 5, flags = INJURE_SILENT) //Not realistic to PA but there are basically no 'real' liver infections

/obj/item/organ/internal/liver/grey
	icon_state = "liver_grey"

/obj/item/organ/internal/liver/grey/colormatch/Initialize(mapload, internal)
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/item/organ/internal/liver/grey/colormatch/LateInitialize()
	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		color = H.species.blood_color
