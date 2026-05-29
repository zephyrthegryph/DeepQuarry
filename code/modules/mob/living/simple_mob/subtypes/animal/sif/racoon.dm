// Sakimm are small scavengers with an adoration for shiny things. They won't attack you for them, but you will be their friend holding something like a coin.

/datum/category_item/catalogue/fauna/sakimm
	name = "Sivian Fauna - Sakimm"
	desc = "Classification: S Procyon cogitae \
	<br><br>\
	Small, social omnivores known to collect objects within their dens. \
	The Sakimm form colonies that have been known to grow up to a hundred individuals. Primarily carnivorous hunters, \
	they often supplement their diets with nuts, roots, and other fruits. \
	Individuals are known to steal food and reflective objects from unsuspecting Sivian residents. \
	It is advised to keep any valuable items within dull wraps when venturing near the den of a Sakimm."
	value = CATALOGUER_REWARD_EASY

/mob/living/simple_mob/animal/sif/sakimm
	name = "sakimm"
	desc = "What appears to be an oversized rodent with hands."
	tt_desc = "S Procyon cogitae"
	catalogue_data = list(/datum/category_item/catalogue/fauna/sakimm)

	faction = FACTION_SAKIMM

	icon_state = "raccoon"
	icon_living = "raccoon"
	icon_dead = "raccoon_dead"
	icon_rest = "raccoon_dead"
	icon = 'icons/mob/animal.dmi'

	maxHealth = 50
	health = 50
	has_hands = TRUE
	humanoid_hands = TRUE
	minbodytemp = 175
	pass_flags = PASSTABLE

	universal_understand = 1

	movement_cooldown = -1

	melee_damage_lower = 5
	melee_damage_upper = 15
	base_attack_cooldown = 1 SECOND
	attacktext = list("nipped", "bit", "cut", "clawed")
	meat_amount = 3

	armor = list(
		"melee" = 15,
		"bullet" = 5,
		"laser" = 5,
		"energy" = 0,
		"bomb" = 10,
		"bio" = 100,
		"rad" = 100
		)

	say_list_type = /datum/say_list/sakimm

	var/obj/item/clothing/head/hat = null // The hat the Sakimm may be wearing.
	var/list/friend_loot_list = list(/obj/item/coin)	// What will make this animal non-hostile if held?
	var/randomize_size = TRUE
	can_be_drop_prey = TRUE
	species_sounds = "Raccoon"
	pain_emote_1p = list("chitter")
	pain_emote_3p = list("chitters")

/mob/living/simple_mob/animal/sif/sakimm/verb/remove_hat()
	set name = "Remove Hat"
	set desc = "Remove the animal's hat. You monster."
	set category = "Abilities.Sakimm"
	set src in view(1)

	drop_hat(usr)

/mob/living/simple_mob/animal/sif/sakimm/proc/drop_hat(mob/user)
	if(hat)
		hat.forceMove(get_turf(user))
		hat = null
		update_icon()
		if(user == src)
			to_chat(user, span_notice("You removed your hat."))
			return
		to_chat(user, span_warning("You removed \the [src]'s hat. You monster."))
	else
		if(user == src)
			to_chat(user, span_notice("You are not wearing a hat!"))
			return
		to_chat(user, span_notice("\The [src] is not wearing a hat!"))

/mob/living/simple_mob/animal/sif/sakimm/verb/give_hat()
	set name = "Give Hat"
	set desc = "Give the animal a hat. You hero."
	set category = "Abilities.Sakimm"
	set src in view(1)

	take_hat(usr)

/mob/living/simple_mob/animal/sif/sakimm/proc/take_hat(mob/user)
	if(hat)
		if(user == src)
			to_chat(user, span_notice("You already have a hat!"))
			return
		to_chat(user, span_notice("\The [src] already has a hat!"))
	else
		if(user == src)
			if(istype(get_active_hand(), /obj/item/clothing/head))
				hat = get_active_hand()
				drop_from_inventory(hat, src)
				hat.forceMove(src)
				to_chat(user, span_notice("You put on the hat."))
				update_icon()
			return
		else if(ishuman(user))
			var/mob/living/carbon/human/H = user

			if(istype(H.get_active_hand(), /obj/item/clothing/head) && !get_active_hand())
				var/obj/item/clothing/head/newhat = H.get_active_hand()
				H.drop_from_inventory(newhat, get_turf(src))
				if(!stat)
					a_intent = I_HELP
					newhat.attack_hand(src)
			else if(src.get_active_hand())
				to_chat(user, span_notice("\The [src] seems busy with \the [get_active_hand()] already!"))

			else
				to_chat(user, span_warning("You aren't holding a hat..."))

/datum/say_list/sakimm
	speak = list("Shurr.", "|R|rr?", "Hss.")
	emote_see = list("sniffs","looks around", "rubs its hands")
	emote_hear = list("chitters", "clicks")

/mob/living/simple_mob/animal/sif/sakimm/Destroy()
	if(hat)
		drop_hat(src)
	. = ..()

/mob/living/simple_mob/animal/sif/sakimm/update_icon()
	cut_overlays()
	..()
	if(hat)
		var/hat_state = hat.item_state ? hat.item_state : hat.icon_state
		var/image/I = image('icons/inventory/head/mob.dmi', src, hat_state)
		I.pixel_y = -15 // Sakimm are tiny!
		I.appearance_flags = RESET_COLOR
		add_overlay(I)

/mob/living/simple_mob/animal/sif/sakimm/Initialize(mapload)
	. = ..()

	add_verb(src, /mob/living/proc/ventcrawl)
	add_verb(src, /mob/living/proc/hide)

	if(randomize_size)
		adjust_scale(rand(8, 11) / 10)

/mob/living/simple_mob/animal/sif/sakimm/IIsAlly(mob/living/L)
	. = ..()

	var/mob/living/carbon/human/H = L
	if(!istype(H))
		return .

	if(!.)
		var/has_loot = FALSE
		var/obj/item/I = H.get_active_hand()
		if(I)
			for(var/item_type in friend_loot_list)
				if(istype(I, item_type))
					has_loot = TRUE
					break
		return has_loot

/mob/living/simple_mob/animal/sif/sakimm/intelligent
	desc = "What appears to be an oversized rodent with hands. This one has a curious look in its eyes."
	randomize_size = FALSE	// Most likely to have a hat.
	melee_attack_delay = 0	// For some reason, having a delay makes item pick-up not work.
