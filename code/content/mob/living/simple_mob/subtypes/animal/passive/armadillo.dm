//Straight import from Mexico and a direct hit to your heart
/mob/living/simple_mob/animal/passive/armadillo
	name = "armadillo"
	desc = "A small, armored mammal. It seems to enjoy rolling around and sleep as a ball."
	tt_desc = "Dasypus novemcinctus"
	//faction = "mexico" //They are from Mexico. //Amusing but this prompts aggression from crew-aligned mobs.

	icon = 'icons/mob/animal.dmi'
	icon_state = "armadillo"
	item_state = "armadillo_rest"
	icon_living = "armadillo"
	icon_rest = "armadillo_rest"
	icon_dead = "armadillo_dead"

	endurance = 30

	mob_size = MOB_SMALL
	pass_flags = PASSTABLE
	layer = MOB_LAYER
	density = 0
	movement_cooldown = 0.75 //roughly a bit faster than a person

	response_help  = "pets"
	response_disarm = "rolls aside"
	response_harm   = "stomps"

	melee_damage_lower = 2
	melee_damage_upper = 1
	attacktext = list("nips", "bumps", "scratches")


	min_oxy = 16 //Require atleast 16kPA oxygen
	minbodytemp = 223		//Below -50 Degrees Celcius
	maxbodytemp = 523	//Above 80 Degrees Celcius
	heat_damage_per_tick = 3
	cold_damage_per_tick = 3

	holder_type = /obj/item/holder/armadillo

	speak_emote = list("rumbles", "chirr?", "churr")


	var/obj/item/clothing/head/hat = null // The hat the armadillo may be wearing.

//Hat simulator stolen from slime code.
CAPABILITIES(/mob/living/simple_mob/animal/passive/armadillo)
	configure(living_rules(say_list_type = /datum/say_list/armadillo))
	configure(butchery_rules(meat_amount = 2))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("vore_taste" = "sand"))
	configure(mob_movement(pull_size = ITEMSIZE_TINY, pull_mobs = MOB_PULL_NONE))
	owns_one(nameof(hat), on_destroy = ON_DESTROY_SPILL)
	hat_bearer(nameof(hat))

/// The hat it wears, drawn over the legacy provider's state (look.hat() reads the hat's own sprite and hears it change).
/mob/living/simple_mob/animal/passive/armadillo/draw(datum/look/look)
	..()
	look.hat(hat, -7) // Smol

/obj/item/holder/armadillo
	//item_state = "armadillo_rest" //Commented here as a reminder that holders will always set the item_state to icon_rest. You cannot override it like this.

CAPABILITIES(/obj/item/holder/armadillo)
	configure(item_worn(worn_icon = 'icons/mob/head.dmi'))

/mob/living/simple_mob/animal/passive/armadillo/torta
	name = "Torta"
	desc = "A small, armored mammal. It seems to be territorial and protective of the dorms."

/datum/say_list/armadillo
	emote_hear = list("churrs","rumbles","chirrs")
	emote_see = list("rolls in place", "shuffles", "scritches at something")

CAPABILITIES(/mob/living/simple_mob/animal/passive/armadillo/torta)
	owns_one(nameof(hat), starts = /obj/item/clothing/head/sombrero, on_destroy = ON_DESTROY_SPILL)

