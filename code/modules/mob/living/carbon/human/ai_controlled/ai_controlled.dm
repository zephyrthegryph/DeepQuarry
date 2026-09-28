/mob/living/carbon/human/ai_controlled
	name = "Nameless Joe"


	combat_mode = TRUE

	low_sorting_priority = TRUE

	var/generate_species = SPECIES_HUMAN

	var/generate_gender = FALSE
	var/generate_id_gender = FALSE

	var/to_wear_hair = "Bald"

	var/to_wear_helmet = /obj/item/clothing/head/welding
	var/to_wear_glasses = /obj/item/clothing/glasses/threedglasses
	var/to_wear_mask = /obj/item/clothing/mask/gas
	var/to_wear_l_radio = /obj/item/radio/headset
	var/to_wear_r_radio = null
	var/to_wear_uniform = /obj/item/clothing/under/color/grey
	var/to_wear_suit = /obj/item/clothing/suit/armor/material/makeshift/glass
	var/to_wear_gloves = /obj/item/clothing/accessory/ring/material/platinum
	var/to_wear_shoes = /obj/item/clothing/shoes/galoshes
	var/to_wear_belt = /obj/item/storage/belt/utility/full
	var/to_wear_l_pocket = /obj/item/soap
	var/to_wear_r_pocket = /obj/item/pda
	var/to_wear_back = /obj/item/storage/backpack
	var/to_wear_id_type = /obj/item/card/id
	var/to_wear_id_job = JOB_ALT_ASSISTANT

	var/to_wear_l_hand = null
	var/to_wear_r_hand = /obj/item/melee/baton

/mob/living/carbon/human/ai_controlled/Initialize(mapload, new_species)
	if(generate_gender)
		gender = pick(list(MALE, FEMALE, PLURAL, NEUTER))

	if(generate_id_gender)
		identifying_gender = pick(list(MALE, FEMALE, PLURAL, NEUTER))

	. = ..(mapload, generate_species)

	species.produceCopy(species.traits.Copy(),src,null,FALSE)

	h_style = to_wear_hair

	if(to_wear_uniform)
		equip_to_slot_or_del(new to_wear_uniform(src), SLOT_ID_UNIFORM)

	if(to_wear_suit)
		equip_to_slot_or_del(new to_wear_suit(src), SLOT_ID_SUIT)

	if(to_wear_shoes)
		equip_to_slot_or_del(new to_wear_shoes(src), SLOT_ID_SHOES)

	if(to_wear_gloves)
		equip_to_slot_or_del(new to_wear_gloves(src), SLOT_ID_GLOVES)

	if(to_wear_l_radio)
		equip_to_slot_or_del(new to_wear_l_radio(src), SLOT_ID_EAR_L)

	if(to_wear_r_radio)
		equip_to_slot_or_del(new to_wear_r_radio(src), SLOT_ID_EAR_R)

	if(to_wear_glasses)
		equip_to_slot_or_del(new to_wear_glasses(src), SLOT_ID_EYES)

	if(to_wear_mask)
		equip_to_slot_or_del(new to_wear_mask(src), SLOT_ID_MASK)

	if(to_wear_helmet)
		equip_to_slot_or_del(new to_wear_helmet(src), SLOT_ID_HEAD)

	if(to_wear_belt)
		equip_to_slot_or_del(new to_wear_belt(src), SLOT_ID_BELT)

	if(to_wear_r_pocket)
		equip_to_slot_or_del(new to_wear_r_pocket(src), SLOT_ID_POCKET_R)

	if(to_wear_l_pocket)
		equip_to_slot_or_del(new to_wear_l_pocket(src), SLOT_ID_POCKET_L)

	if(to_wear_back)
		equip_to_slot_or_del(new to_wear_back(src), SLOT_ID_BACK)

	if(to_wear_l_hand)
		equip_to_slot_or_del(new to_wear_l_hand(src), SLOT_ID_HAND_L)

	if(to_wear_r_hand)
		equip_to_slot_or_del(new to_wear_r_hand(src), SLOT_ID_HAND_R)

	if(to_wear_id_type)
		var/obj/item/card/id/W = new to_wear_id_type(src)
		W.name = "[real_name]'s ID Card"
		var/datum/job/jobdatum
		for(var/jobtype in typesof(/datum/job))
			var/datum/job/J = new jobtype
			if(J.title == to_wear_id_job)
				jobdatum = J
				break
		if(jobdatum)
			W.access = jobdatum.get_access()
		else
			W.access = list()
		if(to_wear_id_job)
			W.assignment = to_wear_id_job
		W.registered_name = real_name
		equip_to_slot_or_del(W, SLOT_ID_ID)

/*
 * Subtypes.
 */

/mob/living/carbon/human/ai_controlled/replicant
	generate_species = SPECIES_REPLICANT_BETA

	generate_gender = TRUE
	identifying_gender = NEUTER

	faction = FACTION_XENO

	to_wear_helmet = /obj/item/clothing/head/helmet/dermal
	to_wear_glasses = /obj/item/clothing/glasses/goggles
	to_wear_mask = /obj/item/clothing/mask/gas/half
	to_wear_l_radio = /obj/item/radio/headset
	to_wear_r_radio = null
	to_wear_uniform = /obj/item/clothing/under/color/grey
	to_wear_suit = /obj/item/clothing/suit/armor/vest
	to_wear_gloves = null
	to_wear_shoes = /obj/item/clothing/shoes/boots/combat/changeling
	to_wear_belt = /obj/item/storage/belt/utility/full
	to_wear_l_pocket = /obj/item/grenade/explosive/mini
	to_wear_r_pocket = /obj/item/grenade/explosive/mini
	to_wear_back = /obj/item/radio/electropack
	to_wear_id_type = /obj/item/card/id
	to_wear_id_job = "Experiment"

	to_wear_r_hand = null

/mob/living/carbon/human/ai_controlled/replicant/Initialize(mapload)
	. = ..()
	name = species.get_random_name(gender)
	apply_body_effect(/datum/body_effect/homeothermic, 0, null)


/mob/living/carbon/human/ai_controlled
	sensorpref = 1
