/mob/living/simple_mob/vore/cookiegirl
	name = "cookiegirl"
	desc = "A woman made with a combination of, well... Whatever you put in a cookie. What were the chefs thinking?"

	icon_state = "cookiegirl"
	icon_living = "cookiegirl"
	icon_rest = "cookiegirl_rest"
	icon_dead = "cookiegirl-dead"
	icon = 'icons/mob/vore.dmi'

	maxHealth = 10
	health = 10

	harm_intent_damage = 2
	melee_damage_lower = 2
	melee_damage_upper = 5

	meat_amount = 10
	meat_type = /obj/item/reagent_containers/food/snacks/cookie

	say_list_type = /datum/say_list/cookiegirl

	faction = FACTION_COOKIEGIRL

	// Activate Noms!
/mob/living/simple_mob/vore/cookiegirl
	vore_active = 1
	vore_bump_chance = 2
	vore_pounce_chance = 25
	vore_standing_too = 1
	vore_ignores_undigestable = 0 // Do they look like they care?
	vore_default_mode = DM_HOLD // They're cookiepeople, what do you expect?
	vore_digest_chance = 10 // Gonna become as sweet as sugar, soon.
	vore_icons = SA_ICON_LIVING | SA_ICON_REST
	can_be_drop_prey = FALSE

/datum/say_list/cookiegirl
	speak = list("Hi!","Are you hungry?","Got milk~?","What to do, what to do...")
	emote_hear = list("hums","whistles")
	emote_see = list("shakes her head","shivers", "picks a bit of crumb off of her body and sticks it in her mouth.")
