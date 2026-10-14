/obj/item/organ/internal/spleen
	name = "spleen"
	icon_state = "spleen"
	organ_tag = O_SPLEEN
	parent_organ = BP_TORSO
	w_class = ITEMSIZE_TINY

	var/spleen_tick = 20 // The number of ticks between Spleen cycles.
	var/spleen_efficiency = 1 // A multiplier for how efficient this spleen is.

/obj/item/organ/internal/spleen/organ_tick(cycles)
	..()
	if(!owner) return

	// The spleen works in bursts: once every spleen_tick cycles on average.
	if(prob(100 * cycles / spleen_tick))

		//High toxins levels are dangerous
		if(owner.injury_load(INJURY_CATEGORY_TOXIC) >= 30 && !owner.reagents.has_reagent(REAGENT_ID_ANTITOXIN))
			//Healthy liver suffers on its own
			if(src.damage < min_broken_damage)
				apply_lesion_damage(0.2 * spleen_tick, /datum/affliction/lesion/toxic_injury, TRUE)
				owner.mend(TREAT_ANTITOXIN, 0.2) //The spleen takes damage but reduces toxins, up until it's broken.
			//Damaged one shares the fun
			else
				var/obj/item/organ/internal/O = pick(owner.internal_organ_list())
				if(O)
					O.apply_lesion_damage(0.2 * spleen_tick, /datum/affliction/lesion/toxic_injury, TRUE)
					owner.mend(TREAT_ANTITOXIN, 0.1) //Only half as effective.

		else if(!src.is_broken()) // If the spleen isn't severely damaged, it can help fight infections. Key word, can.
			var/obj/item/organ/external/OEx = pick(owner.organs)
			OEx.adjust_germ_level(round(rand(0 * spleen_efficiency,-10 * spleen_efficiency)))

			if(!src.is_bruised() && owner.organ_in(O_BRAIN)) // If it isn't bruised, it helps with brain infections.
				var/obj/item/organ/internal/brain/B = owner.organ_in(O_BRAIN)
				B.adjust_germ_level(round(rand(-3 * spleen_efficiency, -10 * spleen_efficiency)))


		// General organ damage from withdraw
		if(prob(20) && owner.factor(BF_WITHDRAWAL))
			apply_lesion_damage(owner.factor(BF_WITHDRAWAL) * 0.05 * ORGAN_LEGACY_BURST, /datum/affliction/lesion/toxic_injury, prob(1)) // Chance to warn them
			owner.injure(INJURY_TOXIN, owner.factor(BF_WITHDRAWAL) * 0.2 * ORGAN_LEGACY_BURST, flags = INJURE_SILENT)

/obj/item/organ/internal/spleen/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	// Low levels can cause pain and haemophilia, high levels can cause brain infections.
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("There's a sharp pain in your [owner.get_organ(parent_organ)]!",1)
			owner.apply_body_effect(/datum/body_effect/trait/haemophilia, 2 MINUTES * spleen_efficiency)
	if (. >= 2)
		if(prob(1))
			if(owner.injury_load(INJURY_CATEGORY_TOXIC) < owner.get_endurance() * 0.2 * spleen_efficiency)
				owner.injure(INJURY_TOXIN, 2 * spleen_efficiency, flags = INJURE_SILENT)
			else if(owner.organ_in(O_BRAIN))
				var/obj/item/organ/internal/brain/Brain = owner.organ_in(O_BRAIN)
				Brain.adjust_germ_level(round(rand(5 * spleen_efficiency,20 * spleen_efficiency)))

/obj/item/organ/internal/spleen/die()
	..()
	if(owner)
		owner.apply_body_effect(/datum/body_effect/trait/haemophilia, round(15 MINUTES * spleen_efficiency))
		var/obj/item/organ/external/target = owner.get_organ(parent_organ)
		owner.injure(INJURY_TOXIN, 15 * spleen_efficiency, flags = INJURE_SILENT)
		if(target)
			target.add_wound(new /datum/affliction/wound/internal_bleeding(target, round(20 * spleen_efficiency)))
			target.update_damages()

/obj/item/organ/internal/spleen/minor
	name = "vestigial spleen"
	parent_organ = BP_GROIN
	spleen_efficiency = 0.3
	spleen_tick = 15

CAPABILITIES(/obj/item/organ/internal/spleen/minor)
	after_init(0, then(PROC_REF(minor_spleen_scale)))

/obj/item/organ/internal/spleen/minor/proc/minor_spleen_scale(datum/act/timer/A)
	adjust_scale(0.7)

// When this organ's organ_tick() has nothing to do: the organ clock may park (/obj/item/organ/proc/life_step_idle()).
/obj/item/organ/internal/spleen/life_step_idle()
	if(!..())
		return FALSE
	if(!owner)
		return TRUE
	return owner.injury_load(INJURY_CATEGORY_TOXIC) < 30 && !owner.factor(BF_WITHDRAWAL)
