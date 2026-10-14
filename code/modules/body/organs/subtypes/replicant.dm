/*
 * This file contains 'synthetic' fleshy organs, intended to not reject.
 */

/obj/item/organ/internal/eyes/replicant
	name = "replicant eyes"
	desc = "A pair of rubber balls used for receiving optical information."
	can_reject = FALSE
	icon_state = "eyes_grey"
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/brain/replicant
	name = "replicant brain"
	desc = "A juicy piece of.. rubber, found in someone's head?"
	can_reject = FALSE
	icon_state = "brain_grey"
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/brain/replicant/torso
	parent_organ = BP_TORSO
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/voicebox/replicant
	name = "replicant voicebox"
	desc = "A rubbery piece of meat used for vocalizations."
	can_reject = FALSE

/obj/item/organ/internal/heart/replicant
	name = "replicant heart"
	desc = "A mass of rubber and muscle used for pumping fluid."
	can_reject = FALSE
	icon_state = "heart_grey-on"
	dead_icon = "heart_grey-off"
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/lungs/replicant
	name = "replicant lungs"
	desc = "A pair of rubbery sacs used for respiration."
	can_reject = FALSE
	icon_state = "lungs_grey"
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/liver/replicant
	name = "replicant liver"
	desc = "A mass of rubber used for filtering and breaking down chemicals."
	can_reject = FALSE
	icon_state = "liver_grey"
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/kidneys/replicant
	name = "replicant kidneys"
	desc = "A pair of small sacs used for filtering chemicals."
	can_reject = FALSE
	icon_state = "kidneys_grey"
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/xenos/plasmavessel/replicant
	name = "replicant phorogenic sac"
	desc = "A bulbous rubbery mass that converts nutrients from the host into a biological compound eerily similar to phoron."
	can_reject = FALSE
	icon_state = "plasma_grey"
	supply_conversion_value = 50 // Selling engineered organs

// D25: the crew variant differs only in data, not a copied proc.
/obj/item/organ/internal/xenos/plasmavessel/replicant/crew
	passive_plasma = 2 //Make it a decent amount so people can actually build stuff without stealing all of medbays phoron

/obj/item/organ/internal/xenos/acidgland/replicant
	name = "replicant aerosol tubule"
	desc = "A long, rubbery tube that ends in a hard plastic-like bulb."
	can_reject = FALSE
	icon_state = "acidgland_grey"

/obj/item/organ/internal/xenos/resinspinner/replicant
	name = "replicant biomesh spinner"
	desc = "A rubbery mass with protrusions for molding organic material."
	can_reject = FALSE
	icon_state = "xenode_grey"

/*
 * These are unique organs to Replicants and other Ancient Aliens, though they can be used elsewhere. They follow the same rules.
 */

/obj/item/organ/internal/immunehub
	name = "lymphomatic control web"
	desc = "A mesh of twitching strings."
	organ_tag = O_AREJECT
	parent_organ = BP_TORSO
	icon_state = "immunehub"

	var/rejection_adjust = 10
	supply_conversion_value = 50 // Selling engineered organs

/obj/item/organ/internal/immunehub/replicant
	name = "replicant assimilation web"
	desc = "A mesh of jiggling rubber strings that dig at nearby flesh."
	can_reject = FALSE

/obj/item/organ/internal/immunehub/handle_organ_proc_special(cycles)
	if(!owner)
		return

	var/list/all_organs = list()
	all_organs |= owner.internal_organ_list()
	all_organs |= owner.organs

	var/modifier = round(rejection_adjust * (1 - 0.5 * is_bruised()))

	for(var/obj/item/organ/I in all_organs)
		I.rejecting = max(0, rejecting - modifier)

/obj/item/organ/internal/metamorphgland
	name = "morphoplastic node"
	desc = "A strange clump of meat that doesn't quite stay in place."
	organ_tag = O_VENTC
	parent_organ = BP_GROIN
	icon_state = "innards"
	organ_verbs = list(
		/mob/living/proc/ventcrawl
		)
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/metamorphgland/replicant
	name = "replicant malleoshift node"
	desc = "A strange clump of rubbery meat that likes to move around."
	can_reject = FALSE
	icon_state = "vox_lung"

/obj/item/organ/internal/brainmirror	// The device that lets Replicants and other Alien Pod minds return willingly to the pods.
	name = "quantum cortical entangler"
	desc = "An ominous device."
	can_reject = FALSE
	organ_tag = O_VRLINK
	parent_organ = BP_HEAD
	icon_state = "cortical-stack"
	robotic = ORGAN_LIFELIKE

	organ_verbs = list(
		/mob/living/carbon/human/proc/perform_exit_vr
		)
	supply_conversion_value = 50 // Selling engineered organs

/*
 * These subtypes are used by the Replicant species, and provide bonuses to their owners. Even when transplanted!
 */

/obj/item/organ/internal/heart/replicant/rage/get_mechanics_info(list/additional_information)
	return ..(list("This organ, when connected properly to the body, will attempt to induce an adrenaline surge in the implantee.") + additional_information)

/obj/item/organ/internal/heart/replicant/rage
	name = "replicant adrenal heart"
	desc = "A mass of rubber, muscle, and complex chemical networks used for pumping fluid."
	var/prev_damage_tally = 0
	COOLDOWN_DECLARE(activation_cd)
	/// Minimum time between surges.
	var/activation_cooldown = 60 SECONDS
	/// How long a surge lasts.
	var/berserk_duration = 20 SECONDS
	supply_conversion_value = 10 // Selling engineered organs

/obj/item/organ/internal/heart/replicant/rage/handle_organ_proc_special(cycles)
	if(!owner)
		return

	var/damage_tally = 0
	var/pain_tally = 0
	damage_tally += owner.injury_load(INJURY_CATEGORY_PHYSICAL)
	damage_tally += owner.injury_load(INJURY_CATEGORY_THERMAL)
	pain_tally += owner.current_pain()

	if(((damage_tally >= 50 || prev_damage_tally >= 50) && prev_damage_tally - damage_tally < 0) || pain_tally >= 60)
		if(COOLDOWN_FINISHED(src, activation_cd))
			COOLDOWN_START(src, activation_cd, activation_cooldown)
			owner.apply_body_effect(/datum/body_effect/berserk, berserk_duration)
			apply_lesion_damage(5)
	prev_damage_tally = damage_tally

// D25: the crew variant differs only in data, not a copied proc.
/obj/item/organ/internal/heart/replicant/rage/crew
	activation_cooldown = 60 MINUTES //Can only be activated once every 60 minutes to prevent it being able to be spammed
	berserk_duration = 40 SECONDS //Lasts a little longer so that it can actually get some use seeing as it activates so infrequently

/obj/item/organ/internal/lungs/replicant/mending/get_mechanics_info(list/additional_information)
	return ..(list("This organ, when connected properly to the body, will attempt to keep some other organs repaired.") + additional_information)

/obj/item/organ/internal/lungs/replicant/mending
	name = "replicant hive lungs"
	desc = "A pair of rubbery sacs with large portions dedicated to honeycombed nanite filters."
	/// Restoration delivered to each listed organ per organ tick.
	var/repair_rate = 1

/// Organs these lungs keep repaired (constant).
TYPE_TABLE_DECLARE(/obj/item/organ/internal/lungs/replicant/mending, repair_list, list(O_HEART, O_KIDNEYS, O_VOICE, O_GBLADDER, O_PLASMA))

/obj/item/organ/internal/lungs/replicant/mending/handle_organ_proc_special(cycles)
	if(!owner)
		return

	var/modifier = 1 - (0.5 * is_bruised())

	if(istype(owner))
		for(var/o_tag in TYPE_TABLE_GET(src, repair_list))
			var/obj/item/organ/O = owner.organ_in(o_tag)
			if(O)
				owner.mend(TREAT_RESTORATION, repair_rate * modifier, O)

// D25: the crew variant differs only in data, not a copied proc.
/obj/item/organ/internal/lungs/replicant/mending/crew
	repair_rate = 0.01 //Very very slow regen, but still cool flavour

// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/xenos/plasmavessel/replicant/crew/life_step_idle()
	return FALSE

/obj/item/organ/internal/immunehub/life_step_idle()
	return FALSE

/obj/item/organ/internal/heart/replicant/rage/life_step_idle()
	return FALSE

/obj/item/organ/internal/lungs/replicant/mending/life_step_idle()
	return FALSE

