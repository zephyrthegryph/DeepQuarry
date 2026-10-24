/datum/category_item/catalogue/fauna/reindeer
	name = "Creature - Reindeer"
	desc = "A reindeer"
	value = CATALOGUER_REWARD_EASY

/mob/living/simple_mob/vore/reindeer
	name = "reindeer"
	desc = "A large reindeer."
	catalogue_data = list(/datum/category_item/catalogue/fauna/reindeer)

	icon_state = "reindeer"
	icon_living = "reindeer"
	icon_dead = "reindeer-dead"
	icon_rest = "reindeer_rest"
	icon = 'icons/mob/vore64x32.dmi'

	endurance = 100

	melee_damage_lower = 10
	melee_damage_upper = 20
	grab_resist = 100

	meat_type = /obj/item/reagent_containers/food/snacks/meat

	response_help = "pets"
	response_disarm = "bops"
	response_harm = "hits"
	attacktext = list("chomps")
	friendly = list("nuzzles", "slobberlicks", "noses softly at", "noseboops", "headbumps against", "leans on", "nibbles affectionately on")

	old_x = -16
	old_y = 0
	default_pixel_x = -16
	pixel_x = -16
	pixel_y = 0

	minbodytemp = 200

	can_buckle = TRUE

	vore_active = TRUE
	vore_icons = SA_ICON_LIVING

CAPABILITIES(/mob/living/simple_mob/vore/reindeer)
	configure(butchery_rules(meat_amount = 5))
	configure(buckle_rules(max_mobs = 1, movable = TRUE, lying = FALSE))

/mob/living/simple_mob/vore/reindeer/festive
	desc = "A large reindeer. It is covered in festive decorations."

	icon_state = "reindeerfes"
	icon_living = "reindeerfes"
	icon_dead = "reindeerfes-dead"
	icon_rest = "reindeerfes_rest"
