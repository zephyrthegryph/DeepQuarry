/mob/living/carbon/human/ai_controlled
	name = "Nameless Joe"


	combat_mode = TRUE


	species_at_make = SPECIES_HUMAN // its species (a constructor argument still wins)

	var/generate_gender = FALSE
	var/generate_id_gender = FALSE


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

// Its outfit: each to_wear_* var names what it starts wearing in that slot (null: nothing), so a subtype only changes the vars.
CAPABILITIES(/mob/living/carbon/human/ai_controlled)
	configure(human_abilities(low_sorting_priority = TRUE))
	profile(nameof(bio), /datum/record/identity, fields = list("sensorpref" = 1))
	profile(nameof(looks), /datum/record/appearance, fields = list("hair_style" = "Bald"))
	wears(nameof(to_wear_uniform), SLOT_ID_UNIFORM)
	wears(nameof(to_wear_suit), SLOT_ID_SUIT)
	wears(nameof(to_wear_shoes), SLOT_ID_SHOES)
	wears(nameof(to_wear_gloves), SLOT_ID_GLOVES)
	wears(nameof(to_wear_l_radio), SLOT_ID_EAR_L)
	wears(nameof(to_wear_r_radio), SLOT_ID_EAR_R)
	wears(nameof(to_wear_glasses), SLOT_ID_EYES)
	wears(nameof(to_wear_mask), SLOT_ID_MASK)
	wears(nameof(to_wear_helmet), SLOT_ID_HEAD)
	wears(nameof(to_wear_belt), SLOT_ID_BELT)
	wears(nameof(to_wear_r_pocket), SLOT_ID_POCKET_R)
	wears(nameof(to_wear_l_pocket), SLOT_ID_POCKET_L)
	wears(nameof(to_wear_back), SLOT_ID_BACK)
	wears(nameof(to_wear_l_hand), SLOT_ID_HAND_L)
	wears(nameof(to_wear_r_hand), SLOT_ID_HAND_R)
	wears(nameof(to_wear_id_type), SLOT_ID_ID, each = PROC_REF(fit_id_card))

TYPE_TABLE(/mob/living/carbon/human/ai_controlled, initial_species_copy, TRUE)

// Its genders are picked before the human init names it after its gender
/mob/living/carbon/human/ai_controlled/Initialize(mapload)
	if(generate_gender)
		gender = pick(list(MALE, FEMALE, PLURAL, NEUTER))
	if(generate_id_gender)
		identifying_gender = pick(list(MALE, FEMALE, PLURAL, NEUTER))
	return ..()

/// Its ID card carries its name and its job's access (wears(each =)).
/mob/living/carbon/human/ai_controlled/proc/fit_id_card(obj/item/card/id/W)
	W.name = "[real_name]'s ID Card"
	var/datum/job/jobdatum
	for(var/jobtype in typesof(/datum/job))
		var/datum/job/J = new jobtype
		if(J.title == to_wear_id_job)
			jobdatum = J
			break
	if(jobdatum)
		W.set_access(jobdatum.get_access())
	else
		W.set_access(list())
	if(to_wear_id_job)
		W.set_assignment(to_wear_id_job)
	W.set_registered_name(real_name)

/*
 * Subtypes.
 */

/mob/living/carbon/human/ai_controlled/replicant
	species_at_make = SPECIES_REPLICANT_BETA

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

CAPABILITIES(/mob/living/carbon/human/ai_controlled/replicant)
	body_effect(/datum/body_effect/homeothermic)


/mob/living/carbon/human/ai_controlled
