/mob/living/simple_mob/animal/passive/honkpet
	name = "Hinkle"
	desc = "The Silence into Laughter program mass produces these excessively hardy animals for each member to raise and take care of. They often switch personalities when smacked."
	tt_desc = "Coulrian Honkus"
	icon = 'icons/mob/animal_vr.dmi'
	icon_state = "c_pet"
	icon_living = "c_pet"
	icon_dead = "c_pet_dead"

	endurance = 1500
	minbodytemp = 175 // Same as Sif mobs.

	response_help  = "pokes"
	response_disarm = "subverts"
	response_harm   = "smacks"

	harm_intent_damage = 0
	melee_damage_lower = 0
	melee_damage_upper = 0
	attacktext = list("honked")

	armor_spec = "melee=80;bullet=20"

	has_langs = list(LANGUAGE_ANIMAL)

	can_be_drop_prey = FALSE

CAPABILITIES(/mob/living/simple_mob/animal/passive/honkpet)
	op("honkpet_interaction_hand", hand(), ungated(), stance(I_DISARM), label("Swap costume"), then(PROC_REF(honkpet_interaction_hand)))

/// Old attack_hand: disarm swaps the sprite instead of the normal touch.
/mob/living/simple_mob/animal/passive/honkpet/proc/honkpet_interaction_hand(datum/act/op/A)
	icon_state = pick("c_pet", "m_pet")
	return TRUE

/mob/living/simple_mob/animal/passive/mimepet
	name = "Dave"
	desc = "That's Dave."
	tt_desc = "Polypodavesilencia"
	icon = 'icons/mob/animal_vr.dmi'
	icon_state = "dave1"
	icon_living = "dave1"
	icon_dead = "dave_dead"
	movement_cooldown = 100

	endurance = 1500
	minbodytemp = 175 // Same as Sif mobs.

	response_help  = "pokes"
	response_disarm = "shuffles"
	response_harm   = "smacks"

	harm_intent_damage = 0
	melee_damage_lower = 0
	melee_damage_upper = 0
	attacktext = list("...")

	armor_spec = "melee=80;bullet=20"

CAPABILITIES(/mob/living/simple_mob/animal/passive/mimepet)
	op("mimepet_interaction_hand", hand(), ungated(), stance(I_DISARM), label("Shuffle"), then(PROC_REF(mimepet_interaction_hand)))

/// Old attack_hand: disarm reshuffles Dave's sprite, then the normal touch follows.
/mob/living/simple_mob/animal/passive/mimepet/proc/mimepet_interaction_hand(datum/act/op/A)
	icon_state = pick("dave1", "dave2", "dave3", "dave5" , "dave6" , "dave7" , "dave8" , "dave9" , "dave10")
	return OP_DECLINE
