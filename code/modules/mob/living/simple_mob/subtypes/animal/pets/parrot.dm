// Parrots can talk, and may repeat things it hears.
/mob/living/simple_mob/animal/passive/bird/parrot
	name = "parrot"
	has_langs = list(LANGUAGE_GALCOM, LANGUAGE_ANIMAL)


	// A headset, so that talking parrots can yell at the crew over comms.
	// If set to a type, on initialize it will be instantiated into that type.
	var/obj/item/radio/headset/my_headset = null

// Say list
/datum/say_list/bird/poly
	speak = list(
		"Poly wanna cracker!",
		"Check the singulo, you chucklefucks!",
		"Wire the solars, you lazy bums!",
		"WHO TOOK THE DAMN HARDSUITS?",
		"OH GOD ITS FREE CALL THE SHUTTLE",
		"Danger! Crystal hyperstructure instability!",
		"CRYSTAL DELAMINATION IMMINENT.",
		"Tweet tweet, I'm a Teshari.",
		"Chitters.",
		"Meteors have been detected on a collision course with the station!"
		)

// Lets the AI use headsets.
// Player-controlled parrots will need to do it manually.
/mob/living/simple_mob/animal/passive/bird/parrot/ISay(message)
	if(my_headset && prob(50))
		var/list/keys = list()
		for(var/channel in my_headset.channels)
			var/key = get_radio_key_from_channel(channel)
			if(key)
				keys += key
		if(keys.len)
			var/key_used = pick(keys)
			return say("[key_used] [message]")
	return say(message)

// Ugly saycode so parrots can use their headsets.
/mob/living/simple_mob/animal/passive/bird/parrot/handle_message_mode(message_mode, message, verb, used_radios, whispering)
	..()
	if(message_mode)
		if(my_headset && istype(my_headset, /obj/item/radio))
			my_headset.talk_into(src, message, message_mode, verb, whispering)
			used_radios += my_headset

// Clicked on while holding an object.
EXTEND_INTERACTIONS(/mob/living/simple_mob/animal/passive/bird/parrot, \
	INTERACT_ITEM(null, PROC_REF(parrot_interaction_item)), \
	INTERACT_HAND_UNGATED_AS(I_GRAB, "Take headset", PROC_REF(parrot_interaction_hand)))

/// Old attackby: give a headset.
/mob/living/simple_mob/animal/passive/bird/parrot/proc/parrot_interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	. = TRUE
	if(istype(I, /obj/item/radio/headset))
		give_headset(I, user)
		return
	return FALSE

// Clicked on by empty hand.
/// Old attack_hand: grab the headset off.
/mob/living/simple_mob/animal/passive/bird/parrot/proc/parrot_interaction_hand(mob/living/L, obj/item/held, datum/interaction/interaction)
	. = TRUE
	if(interaction.stance == I_GRAB && my_headset)
		remove_headset(L)
	else
		return FALSE


/mob/living/simple_mob/animal/passive/bird/parrot/proc/give_headset(obj/item/radio/headset/new_headset, mob/living/user)
	if(!istype(new_headset))
		to_chat(user, span_warning("\The [new_headset] isn't a headset."))
		return
	if(my_headset)
		to_chat(user, span_warning("\The [src] is already wearing \a [my_headset]."))
		return
	else
		if(!move_into(src, nameof(src.my_headset), new_headset, user))
			return
		to_chat(user, span_warning("You place \a [new_headset] on \the [src]. You monster."))
		to_chat(src, span_notice("\The [user] gives you \a [new_headset]. You should put it to good use immediately."))
		return

/mob/living/simple_mob/animal/passive/bird/parrot/proc/remove_headset(mob/living/user)
	if(!my_headset)
		to_chat(user, span_warning("\The [src] doesn't have a headset to remove, thankfully."))
	else
		ISay("BAWWWWWK LEAVE THE HEADSET BAWKKKKK!")
		var/obj/item/radio/headset/old_headset = rel_take(src, nameof(my_headset))
		old_headset.forceMove(get_turf(src))
		user.put_in_hands(old_headset)
		to_chat(user, span_notice("You take away \the [src]'s [old_headset.name]. Finally."))
		to_chat(src, span_warning("\The [user] takes your [old_headset.name] away! How cruel!"))

/mob/living/simple_mob/animal/passive/bird/parrot/examine(mob/user)
	. = ..()
	if(my_headset)
		. += "It is wearing \a [my_headset]."

// Subtypes.

// Best Bird
/mob/living/simple_mob/animal/passive/bird/parrot/poly
	name = "Poly"
	desc = "It's a parrot. An expert on quantum cracker theory."
	icon_state = "poly"
	icon_rest = "poly-held"
	icon_dead = "poly-dead"
	tt_desc = "E Ara macao"
	attack_armor_pen = 20	//HE HAS THE B E A K
	my_headset = /obj/item/radio/headset/headset_eng
	say_list_type = /datum/say_list/bird/poly

// Best Bird with best headset.
/mob/living/simple_mob/animal/passive/bird/parrot/poly/ultimate
	my_headset = /obj/item/radio/headset/omni

/mob/living/simple_mob/animal/passive/bird/parrot/kea
	name = "kea"
	desc = "A species of parrot. On Earth, they are unique among other parrots for residing in alpine climates. \
	They are known to be intelligent and curious, which has made some consider them a pest."
	icon_state = "kea"
	icon_rest = "kea-held"
	icon_dead = "kea-dead"
	tt_desc = "E Nestor notabilis"

/mob/living/simple_mob/animal/passive/bird/parrot/eclectus
	name = "eclectus"
	desc = "A species of parrot, this species features extreme sexual dimorphism in their plumage's colors. \
	A male eclectus has emerald green plumage, where as a female eclectus has red and purple plumage."
	icon_state = "eclectus"
	icon_rest = "eclectus-held"
	icon_dead = "eclectus-dead"
	tt_desc = "E Eclectus roratus"

CAPABILITIES(/mob/living/simple_mob/animal/passive/bird/parrot/eclectus)
	rolls(nameof(gender), pick_one(list(MALE, FEMALE)))
	rolls(nameof(icon_state), PROC_REF(roll_gendered_look), from = list(nameof(gender)))
	rolls(nameof(icon_rest), PROC_REF(roll_gendered_rest), from = list(nameof(gender)))
	rolls(nameof(icon_dead), PROC_REF(roll_gendered_dead), from = list(nameof(gender)))

/// Rolled before init (rolls()): a female eclectus has her own sprites.
/mob/living/simple_mob/animal/passive/bird/parrot/eclectus/proc/roll_gendered_look(datum/roller/R)
	return gender == FEMALE ? "eclectusf" : icon_state

/mob/living/simple_mob/animal/passive/bird/parrot/eclectus/proc/roll_gendered_rest(datum/roller/R)
	return gender == FEMALE ? "eclectusf-held" : icon_rest

/mob/living/simple_mob/animal/passive/bird/parrot/eclectus/proc/roll_gendered_dead(datum/roller/R)
	return gender == FEMALE ? "eclectusf-dead" : icon_dead

/mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot
	name = "grey parrot"
	desc = "A species of parrot. This one is predominantly grey, but has red tail feathers."
	icon_state = "agrey"
	icon_rest = "agrey-held"
	icon_dead = "agrey-dead"
	tt_desc = "E Psittacus erithacus"

/mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique
	name = "black-headed caique"
	desc = "A species of parrot, these birds have a distinct black color on their heads, distinguishing them from their relative Caiques."
	icon_state = "bcaique"
	icon_rest = "bcaique-held"
	icon_dead = "bcaique-dead"
	tt_desc = "E Pionites melanocephalus"

/mob/living/simple_mob/animal/passive/bird/parrot/white_caique
	name = "white-bellied caique"
	desc = "A species of parrot, they are also known as the Green-Thighed Parrot."
	icon_state = "wcaique"
	icon_rest = "wcaique-held"
	icon_dead = "wcaique-dead"
	tt_desc = "E Pionites leucogaster"

/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar
	name = "budgerigar"
	desc = "A species of parrot, they are also known as the common parakeet, or in some circles, the budgie. \
	This one is has its natural colors of green and yellow."
	icon_state = "gbudge"
	icon_rest = "gbudge-held"
	icon_dead = "gbudge-dead"
	tt_desc = "E Melopsittacus undulatus"

/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue
	icon_state = "bbudge"
	icon_rest = "bbudge-held"
	icon_dead = "bbudge-dead"
	desc = "A species of parrot, they are also known as the common parakeet, or in some circles, the budgie. \
	This one has a mutation which altered its color to be blue instead of green and yellow."

/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen
	icon_state = "bgbudge"
	icon_rest = "bgbudge-held"
	icon_dead = "bgbudge-dead"
	desc = "A species of parrot, they are also known as the common parakeet, or in some circles, the budgie. \
	This one has a mutation which altered its color to be a mix of blue and green."

/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel
	name = "cockatiel"
	desc = "A species of parrot. This one has a highly visible crest."
	icon_state = "tiel"
	icon_rest = "tiel-held"
	icon_dead = "tiel-dead"
	tt_desc = "E Nymphicus hollandicus"

/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white
	icon_state = "wtiel"
	icon_rest = "wtiel-held"
	icon_dead = "wtiel-dead"

/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish
	icon_state = "luttiel"
	icon_rest = "luttiel-held"
	icon_dead = "luttiel-dead"

/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey
	icon_state = "blutiel" // idk why this is blu.
	icon_rest = "blutiel-held"
	icon_dead = "blutiel-dead"

// This actually might be the yellow-crested cockatoo but idk.
/mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo
	name = "sulphur-crested cockatoo"
	desc = "A species of parrot. This one has an expressive yellow crest. Their underwing and tail feathers are also yellow."
	icon_state = "too"
	icon_rest = "too-held"
	icon_dead = "too-dead"
	tt_desc = "E Cacatua galerita"

// This was originally called 'hooded_too', which might not mean the unbrella cockatoo but idk.
/mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo
	name = "white cockatoo"
	desc = "A species of parrot. This one is also known as the Umbrella Cockatoo, due to the semicircular shape of its crest."
	icon_state = "utoo"
	icon_rest = "utoo-held"
	icon_dead = "utoo-dead"
	tt_desc = "E Cacatua alba"

/mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo
	name = "pink cockatoo"
	desc = "A species of parrot. This one is also known as Major Mitchell's cockatoo, \
	in honor of a human surveyor and explorer who existed before humans fully explored their home planet."
	icon_state = "mtoo"
	icon_rest = "mtoo-held"
	icon_dead = "mtoo-dead"
	tt_desc = "E Lophochroa leadbeateri"


// AI

// The worn headset sits in the parrot's contents.
/mob/living/simple_mob/animal/passive/bird/parrot/ownership()
	. = ..()
	. += owns(nameof(my_headset), policy = OWN_CONTAINED, starts = nameof(my_headset))
