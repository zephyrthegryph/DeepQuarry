/*
	Wards are a specific type of mechanical simplemob that generally fill a support role for their faction or for a specific mob.
	Generally they are helpless by themselves and are fragile, but can do very useful things if protected. This makes them a high priority target.
*/

/mob/living/simple_mob/mechanical/ward
	name = "ward"
	desc = "A small floating machine. This one seems rather useless..."
	icon = 'icons/mob/critter.dmi'
	icon_state = "ward"
	icon_living = "ward"
	response_help   = "pets"
	response_disarm = "swats away"
	response_harm   = "punches"
	faction = FACTION_WARDS // Needed as most human mobs are in neutral faction. The owner is generally except from any ward hostility regardless.

	organ_names = /datum/decl/mob_organ_names/ward

	endurance = 15
	movement_cooldown = -1


	melee_damage_lower = 0
	melee_damage_upper = 0

	var/mob/living/owner = null // The mob that made the ward, if any. Used to ensure the ward does not interfere with its creator.

CAPABILITIES(/mob/living/simple_mob/mechanical/ward)
	configure(mob_movement(hovering = TRUE))
	configure(mob_kind(death_message = "is smashed into pieces!"))
	configure(mob_movement(bump = 0))

/mob/living/simple_mob/mechanical/ward
	delete_on_death = TRUE

/mob/living/simple_mob/mechanical/ward/on_death(gibbed)
	..()

/mob/living/simple_mob/mechanical/ward/IIsAlly(mob/living/L)
	if(owner == L)
		return TRUE
	return ..()

/datum/decl/mob_organ_names/ward
TYPE_TABLE(/datum/decl/mob_organ_names/ward, mob_organ_hit_zones, list("chassis", "sensor array", "hover thruster"))

