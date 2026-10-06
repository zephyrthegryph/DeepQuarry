/obj/item/organ/internal/kidneys
	name = "kidneys"
	icon_state = "kidneys"
	gender = PLURAL
	organ_tag = O_KIDNEYS
	parent_organ = BP_GROIN

/obj/item/organ/internal/kidneys/organ_tick(cycles)
	..()

	if(!owner) return

	// Coffee is really bad for you with busted kidneys.
	// This should probably be expanded in some way, but fucked if I know
	// what else kidneys can process in our reagent list.
	var/datum/reagent/coffee = locate_in_list(owner.reagents.reagent_list, /datum/reagent/drink/coffee)
	if(coffee)
		if(is_bruised())
			owner.injure(INJURY_TOXIN, 0.1 * ORGAN_LEGACY_BURST * cycles, flags = INJURE_SILENT)
		else if(is_broken())
			owner.injure(INJURY_TOXIN, 0.3 * ORGAN_LEGACY_BURST * cycles, flags = INJURE_SILENT)

	// General organ damage from withdraw, kidneys do a lot of the work
	if(prob(70) && owner.factor(BF_WITHDRAWAL))
		apply_lesion_damage(owner.factor(BF_WITHDRAWAL) * 0.05 * ORGAN_LEGACY_BURST * cycles, /datum/affliction/lesion/toxic_injury, prob(1)) // Chance to warn them
		owner.injure(INJURY_TOXIN, owner.factor(BF_WITHDRAWAL) * 0.3 * ORGAN_LEGACY_BURST * cycles, flags = INJURE_SILENT)

/obj/item/organ/internal/kidneys/handle_organ_proc_special(cycles)
	. = ..()

	if(owner)
		owner.mend(TREAT_ANTITOXIN, kidney_clearance() * cycles)

/// Toxin the kidneys clear per Life cycle: under a light load (a tenth of endurance) they purge it at load x 2% a cycle
/// (the mean of the old prob(load) roll of 1-3); a heavier load overwhelms them.
/obj/item/organ/internal/kidneys/proc/kidney_clearance()
	var/load = owner.injury_load(INJURY_CATEGORY_TOXIC)
	if(!load || load > owner.get_endurance() * 0.1)
		return 0
	return load * 0.02

/obj/item/organ/internal/kidneys/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	//Pyelonephritis
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("There's a stabbing pain in your lower back!",1)
	if (. >= 2)
		if(prob(1))
			owner.custom_pain("You feel extremely tired, like you can't move!",1)
			owner.m_intent = I_WALK
			owner.hud_used.move_intent.icon_state = "walking"

/obj/item/organ/internal/kidneys/grey
	icon_state = "kidneys_grey"


CAPABILITIES(/obj/item/organ/internal/kidneys/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/kidneys/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

// When this organ's organ_tick() has nothing to do: the organ clock may park (/obj/item/organ/proc/life_step_idle()).
/obj/item/organ/internal/kidneys/life_step_idle()
	if(!..())
		return FALSE
	if(!owner)
		return TRUE
	return !is_bruised() && !owner.injury_load(INJURY_CATEGORY_TOXIC) && !owner.factor(BF_WITHDRAWAL)
