CAPABILITIES(/mob/living/carbon/human/ai_controlled/greytide)
	rolls(nameof(to_wear_r_hand), pick_weighted(list(/obj/item/storage/toolbox/electrical = 20, /obj/item/storage/toolbox/mechanical = 20, /obj/item/storage/toolbox/emergency = 20, /obj/item/melee/baton/cattleprod = 50)))
	rolls(nameof(to_wear_mask), PROC_REF(roll_mask))
	rolls(nameof(to_wear_helmet), PROC_REF(roll_helmet))
	rolls(nameof(to_wear_gloves), PROC_REF(roll_gloves))

/// Rolled before init (rolls()): half wear a gas mask.
/mob/living/carbon/human/ai_controlled/greytide/proc/roll_mask(datum/roller/R)
	return R.chance(50) ? /obj/item/clothing/mask/gas : null

/// Rolled before init (rolls()): the odd one wears a cone.
/mob/living/carbon/human/ai_controlled/greytide/proc/roll_helmet(datum/roller/R)
	return R.chance(5) ? /obj/item/clothing/head/cone : null

/// Rolled before init (rolls()): most have insulated gloves, and now and then the real ones.
/mob/living/carbon/human/ai_controlled/greytide/proc/roll_gloves(datum/roller/R)
	if(!R.chance(70))
		return null
	return R.weighted(list(/obj/item/clothing/gloves/fyellow = 20, /obj/item/clothing/gloves/yellow = 1))

/mob/living/carbon/human/ai_controlled/greytide
	name = "John Greytide" //theyll get a normal name on spawn
	to_wear_glasses = null
	//to_wear_mask =
	to_wear_l_radio = /obj/item/radio/headset
	to_wear_r_radio = null
	to_wear_uniform = /obj/item/clothing/under/color/grey
	to_wear_suit = null
	to_wear_shoes = /obj/item/clothing/shoes/black
	to_wear_belt = /obj/item/storage/belt/utility/full
	to_wear_l_pocket = /obj/item/soap
	to_wear_r_pocket = /obj/item/pda
	to_wear_back = /obj/item/storage/backpack
	to_wear_id_type = /obj/item/card/id
	to_wear_id_job = "Assistant"

	to_wear_l_hand = null
	faction = "syndicate"
