// Glitterflies! Little butterfly-like creatures that float around and be cute.

/datum/category_item/catalogue/fauna/glitterfly
	name = "Sivian Fauna - Glitterfly"
	desc = "Classification: S Lepidoptera adamas \
	<br><br>\
	An herbivorous insectoid beloved for its glittering wings. \
	<br>\
	The creature has four wings mirrored laterally, which reflect \
	the ambient light to provide a measure of camouflage. \
	Their wings appearance does not come free, causing them to \
	produce large amounts of reflective flake-like dandruff."
	value = CATALOGUER_REWARD_TRIVIAL

/datum/category_item/catalogue/fauna/glitterfly_rare
	name = "Sivian Fauna - Adela's Glitterfly"
	desc = "Classification: S Lepidoptera adamas \
	<br><br>\
	This mutation of the glitterfly is incredibly rare, one of the few and first known individuals\
	known to exist with it is owned by little-known Sivian ecologist Adela Svingelm, and kept within its own \
	climate-controlled habitat."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/animal/sif/glitterfly
	name = "glitterfly"
	desc = "A large, shiny butterfly!"
	description_fluff = "Glitterflies tend to have a wingspan equivalent to the length of an average human head."
	tt_desc = "S Lepidoptera adamas"
	catalogue_data = list(/datum/category_item/catalogue/fauna/glitterfly)

	faction = FACTION_NEUTRAL

	icon_state = "butterfly"
	icon_living = "butterfly"
	icon_dead = "butterfly_dead"
	icon = 'icons/mob/animal.dmi'

	endurance = 10

	movement_cooldown = -2
	// dq_get_hovering(src) type-default moved to GLOB.dq_hovering_by_type

	melee_damage_lower = 1
	melee_damage_upper = 2
	attack_armor_pen = 80
	attack_injury_kind = INJURY_PIERCE

	density = FALSE	// Non-dense, so things can walk through their groups unhindered.

	pass_flags = PASSTABLE

	attacktext = list("bit", "buffeted", "slashed")

	organ_names = /datum/decl/mob_organ_names/smallflying

	tame_items = list(
	/obj/item/reagent_containers/food/snacks/grown = 90,
	/obj/item/reagent_containers/food/snacks/crabmeat = 10,
	/obj/item/reagent_containers/food/snacks/meat = 5
	)

	say_list_type = /datum/say_list/glitterfly

CAPABILITIES(/mob/living/simple_mob/animal/sif/glitterfly)
	rolls(nameof(color), PROC_REF(roll_colour))
	rolls(nameof(default_pixel_y), range_of(5, 12))
	rolls(nameof(pixel_y), PROC_REF(roll_pixel_y), from = list(nameof(default_pixel_y)))
	trait(TRAIT_AMBIENT_PEST_MOB)

/// Mostly a bright colour, sometimes a dark one, rarely near-black (rolls()).
/mob/living/simple_mob/animal/sif/glitterfly/proc/roll_colour(datum/roller/R)
	var/list/colours = list(rgb(R.number(100, 255), R.number(100, 255), R.number(100, 255)) = 10, rgb(R.number(5, 100), R.number(5, 100), R.number(5, 100)) = 2, "#222222" = 1)
	return R.weighted(colours)

/// It hovers at its own height (rolls()).
/mob/living/simple_mob/animal/sif/glitterfly/proc/roll_pixel_y(datum/roller/R)
	return default_pixel_y

/mob/living/simple_mob/animal/sif/glitterfly/rare
	name = "sparkling glitterfly"
	desc = "A large, incredibly shiny butterfly!"
	catalogue_data = list(/datum/category_item/catalogue/fauna/glitterfly, /datum/category_item/catalogue/fauna/glitterfly_rare)
	endurance = 30

	movement_cooldown = -3

	melee_damage_upper = 5

	plane = PLANE_LIGHTING_ABOVE

/mob/living/simple_mob/animal/sif/glitterfly/unique_tame_check(obj/O, mob/user)
	. = ..()

	if(.)
		if(istype(O, /obj/item/reagent_containers/food/snacks/grown))
			var/obj/item/reagent_containers/food/snacks/grown/G = O

			if(G.seed() && G.seed().kitchen_tag == PLANT_BERRIES)
				return TRUE
			return FALSE

/datum/say_list/glitterfly
	speak = list("Pi..","Po...", "Pa...")
	emote_see = list("vibrates","flutters", "twirls")
	emote_hear = list("pips", "clicks", "chirps")

/datum/decl/mob_organ_names/smallflying
//For flying things too tiny to be granular
TYPE_TABLE(/datum/decl/mob_organ_names/smallflying, mob_organ_hit_zones, list("body", "left wing", "right wing"))

/// The explorers' pet glitterfly on Southern Cross: leaves no dirt (the map edit `makes_dirt = 0` it carried before makes_dirt became the
/// mob_movement() trait; a compiled map cannot name a var that left the type).
/mob/living/simple_mob/animal/sif/glitterfly/tidy

CAPABILITIES(/mob/living/simple_mob/animal/sif/glitterfly/tidy)
	configure(mob_movement(makes_dirt = FALSE))
