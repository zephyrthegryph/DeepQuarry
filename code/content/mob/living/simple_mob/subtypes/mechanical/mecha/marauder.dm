// Marauders are even tougher than Durands.

/datum/category_item/catalogue/technology/marauder
	name = "Exosuit - Marauder"
	desc = "Marauders are the more modern descendants of the Durand model. Stronger, faster, and \
	more resilient than their predecessor, they have replaced the Durand's role entirely, and are generally seen in service \
	for various militaries across human space. As such, they are generally unavailable to civilians, including \
	corporations and most Trans-Stellars."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/mechanical/mecha/combat/marauder
	name = "marauder"
	desc = "A heavy-duty, combat exosuit, developed after the Durand model. This is rarely found among civilian populations."
	icon_state = "marauder"
	movement_cooldown = 1.5
	wreckage = /obj/structure/loot_pile/mecha/marauder

	deflect_chance = 25
	sight = SEE_SELF | SEE_MOBS



/datum/category_item/catalogue/technology/seraph
	name = "Exosuit - Seraph"
	desc = "The Seraph line of combat exosuit is essentially a Marauder with incremental improvements, making \
	it slightly better. Due to the relatively minor improvements over its predecessor, and the cost of \
	said improvements, Seraphs have not made the Marauder obsolute. Instead, they have generally filled the \
	role of housing important commanders, and as such they generally contain specialized communications \
	equipment to aid in receiving and relaying orders.\
	<br><br>\
	Due to this role, they are generally not expected to see combat frequently. Despite this, they often have \
	one or more weapons attached, to allow for retaliation in case it is attacked directly."
	value = CATALOGUER_REWARD_HARD

// Slightly stronger, used to allow comdoms to frontline without dying instantly, I guess.
/mob/living/simple_mob/mechanical/mecha/combat/marauder/seraph
	name = "seraph"
	desc = "A heavy-duty, combat/command exosuit. This one is specialized towards housing important commanders such as high-ranking \
	military personnel. It's stronger than the regular Marauder model, but not by much."
	icon_state = "seraph"
	wreckage = /obj/structure/loot_pile/mecha/marauder/seraph


/mob/living/simple_mob/mechanical/mecha/combat/marauder/mauler
	name = "mauler"
	desc = "A heavy duty, combat exosuit that is based off of the Marauder model."
	icon_state = "mauler"
	wreckage = /obj/structure/loot_pile/mecha/marauder/mauler

CAPABILITIES(/mob/living/simple_mob/mechanical/mecha/combat/marauder/seraph)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/technology/seraph)))
