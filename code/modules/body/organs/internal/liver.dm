/obj/item/organ/internal/liver
	name = "liver"
	icon_state = "liver"
	organ_tag = O_LIVER
	parent_organ = BP_GROIN

/obj/item/organ/internal/liver/organ_tick(cycles)
	..()
	if(!iscarbon(owner)) return


	//High toxins levels are dangerous
	if(owner.injury_load(INJURY_CATEGORY_TOXIC) >= 50 && !owner.reagents.has_reagent(REAGENT_ID_ANTITOXIN))
		//Healthy liver suffers on its own
		if (src.damage < min_broken_damage)
			apply_lesion_damage(0.2 * cycles, /datum/affliction/lesion/toxic_injury, TRUE)
		//Damaged one shares the fun
		else
			var/obj/item/organ/internal/O = pick(owner.internal_organ_list())
			if(O)
				O.apply_lesion_damage(0.2 * cycles, /datum/affliction/lesion/toxic_injury, TRUE)


	// Get the effectiveness of the liver.
	var/filter_effect = 3
	if(is_bruised())
		filter_effect -= 1
	if(is_broken())
		filter_effect -= 2

	// Do some reagent processing.
	if(owner.factor(BF_HEPATOTOXICITY))
		apply_lesion_damage(owner.factor(BF_HEPATOTOXICITY) * 0.1 * cycles, /datum/affliction/lesion/toxic_injury, prob(1)) // Chance to warn them
		if(filter_effect < 2)	//Liver is badly damaged, you're drinking yourself to death
			owner.injure(INJURY_TOXIN, owner.factor(BF_HEPATOTOXICITY) * 0.2 * cycles, flags = INJURE_SILENT)
		if(filter_effect < 3)
			owner.injure(INJURY_TOXIN, owner.factor(BF_HEPATOTOXICITY) * 0.1 * cycles, flags = INJURE_SILENT)

	// General organ damage from withdraw
	if(prob(20) && owner.factor(BF_WITHDRAWAL))
		apply_lesion_damage(owner.factor(BF_WITHDRAWAL) * 0.05 * cycles, /datum/affliction/lesion/toxic_injury, prob(1)) // Chance to warn them
		if(filter_effect < 2)	//Withdrawls intensified
			owner.injure(INJURY_TOXIN, owner.factor(BF_WITHDRAWAL) * 0.2 * cycles, flags = INJURE_SILENT)
		if(filter_effect < 3)
			owner.injure(INJURY_TOXIN, owner.factor(BF_WITHDRAWAL) * 0.1 * cycles, flags = INJURE_SILENT)


/obj/item/organ/internal/liver/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	//Pyogenic Abscess
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("There's a sharp pain in your upper-right abdomen!",1)
	if (. >= 2)
		if(prob(1) && owner.injury_load(INJURY_CATEGORY_TOXIC) < owner.get_endurance()*0.3)
			owner.injure(INJURY_TOXIN, 5, flags = INJURE_SILENT) //Not realistic to PA but there are basically no 'real' liver infections

/obj/item/organ/internal/liver/grey
	icon_state = "liver_grey"


CAPABILITIES(/obj/item/organ/internal/liver/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/liver/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

// When this organ's organ_tick() has nothing to do: the organ clock may park (/obj/item/organ/proc/life_step_idle()).
/obj/item/organ/internal/liver/life_step_idle()
	if(!..())
		return FALSE
	if(!owner)
		return TRUE
	return owner.injury_load(INJURY_CATEGORY_TOXIC) < 50 && !owner.factor(BF_HEPATOTOXICITY) && !owner.factor(BF_WITHDRAWAL)
