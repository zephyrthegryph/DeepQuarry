/datum/category_item/catalogue/fauna/mothroach
	name = "Alien Wildlife - Mothroach"
	desc = "The Mothroach is a terrestrial creature that is a hybrid between a mothperson and a cockroach."
	value = CATALOGUER_REWARD_MEDIUM

/mob/living/simple_mob/animal/passive/mothroach
	name = "mothroach"
	desc = "This is the adorable by-product of multiple attempts at genetically mixing mothpeople with cockroaches."
	catalogue_data = list(/datum/category_item/catalogue/fauna/mothroach)

	icon = 'icons/mob/animal.dmi'
	icon_state = "mothroach"
	icon_living = "mothroach"
	icon_dead = "mothroach_dead"
	icon_rest = "mothroach_rest"

	faction = FACTION_MOTHROACH
	endurance = 50
	movement_cooldown = -1

	see_in_dark = 10

	meat_amount = 2
	meat_type = /obj/item/reagent_containers/food/snacks/meat
	holder_type = /obj/item/holder/mothroach

	response_help   = "pats"
	response_disarm = "shoos"
	response_harm   = "hits"
	speak_emote = list("flutters")

	harm_intent_damage = 1
	melee_damage_lower = 1
	melee_damage_upper = 2
	attacktext = list("hits")

	mob_size = MOB_SMALL
	pass_flags = PASSTABLE
	density = FALSE
	friendly = list("pats")
	can_climb = TRUE
	climbing_delay = 2.0

	say_list_type = /datum/say_list/mothroach

	allow_mind_transfer = TRUE

CAPABILITIES(/mob/living/simple_mob/animal/passive/mothroach)
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)
	op("mothroach_item", item(/obj/item), then(PROC_REF(mothroach_interaction_item)))
	op("mothroach_hand_help", hand(), stance(I_HELP), label("Pet"), then(PROC_REF(mothroach_interaction_hand_help)))
	op("mothroach_hand_hurt", hand(), stance(I_HURT), label("Hit"), then(PROC_REF(mothroach_interaction_hand_hurt)))
	op("mothroach_hand_disarm", hand(), stance(I_DISARM), label("Shove"), then(PROC_REF(mothroach_interaction_hand_disarm)))
	op("mothroach_hand_grab", hand(), stance(I_GRAB), label("Grab"), then(PROC_REF(mothroach_interaction_hand_grab)))

/// The help-stance input of mothroach_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/mothroach/proc/mothroach_interaction_hand_help(datum/act/op/A)
	return mothroach_interaction_hand(A, I_HELP)

/// The hurt-stance input of mothroach_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/mothroach/proc/mothroach_interaction_hand_hurt(datum/act/op/A)
	return mothroach_interaction_hand(A, I_HURT)

/// The disarm-stance input of mothroach_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/mothroach/proc/mothroach_interaction_hand_disarm(datum/act/op/A)
	return mothroach_interaction_hand(A, I_DISARM)

/// The grab-stance input of mothroach_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/mothroach/proc/mothroach_interaction_hand_grab(datum/act/op/A)
	return mothroach_interaction_hand(A, I_GRAB)

/mob/living/simple_mob/animal/passive/mothroach/Initialize(mapload)
	. = ..()


	real_name = name

/// Old attack_hand: the normal touch, then a scream.
/mob/living/simple_mob/animal/passive/mothroach/proc/mothroach_interaction_hand(datum/act/op/A, stance)
	var/mob/user = A.actor
	. = OP_OK
	unarmed_touch(user, stance)

	if(stat != DEAD)
		play_sfx(src, SFX_VOICE_SCREAM_MOTH_MOTH_SCREAM)

/// Old attackby: the normal attack, then a scream.
/mob/living/simple_mob/animal/passive/mothroach/proc/mothroach_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	. = OP_OK
	hit_with_item(O, user)

	if(stat != DEAD)
		play_sfx(src, SFX_VOICE_SCREAM_MOTH_MOTH_SCREAM)

/datum/say_list/mothroach
	emote_hear = list("flutters")

/obj/item/holder/mothroach
	name = "mothroach"
	desc = "This is the adorable by-product of multiple attempts at genetically mixing mothpeople with cockroaches."

	icon = 'icons/mob/animal.dmi'
	icon_state = "mothroach"

	item_state = "mothroach"
	slot_flags = SLOT_HEAD
	w_class = ITEMSIZE_TINY
	item_icons = list(
		slot_l_hand_str = 'icons/mob/lefthand_holder.dmi',
		slot_r_hand_str = 'icons/mob/righthand_holder.dmi',
		slot_head_str = 'icons/mob/head.dmi',
	)

/mob/living/simple_mob/animal/passive/mothroach/bar
	name = "mothroach bartender"
	desc = "A mothroach serving drinks. Look at him go."
	icon_state = "barroach"
	icon_living = "barroach"
	icon_dead = "barroach_dead"

	holder_type = /obj/item/holder/mothroach/bar

/obj/item/holder/mothroach/bar
	item_state = "barroach"
