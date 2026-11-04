/mob/living/simple_mob/humanoid/cultist/hunter // This Mob is not meant to be fair, he is not meant to fight regular crew he is to be pitted against heavily armed explo teams to see if he can wipe them out.
	name = "Blood Hunter" // TO BE CLEAR: DO NOT SPAWN THIS GUY ON THE SHIP/STATION HE WILL MURDER EVERYTHING.
	desc = "The smell of blood fills the air, how delicious it tastes. Let the hunt begin." // He is a horrifying lovechild of Caleb and a blooborne hunter.
	icon_state = "hunterb" // He probably shouldn't even have other mobs supporting him.
	icon_living = "hunterb"


	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_BLADESLICE

	projectiletype = /obj/item/projectile/bullet/pellet/shotgun


	// loot_list = list(/obj/item/material/butterfly/saw = 100, /obj/item/gun/projectile/shotgun/doublebarrel/sawn/alt = 100) // Downstream

	needs_reload = TRUE
	reload_max = 2
	projectilesound = SFX_WEAPONS_GUNSHOT_SHOTGUN

/mob/living/simple_mob/humanoid/cultist/hunter

/mob/living/simple_mob/humanoid/cultist/hunter/on_death(gibbed)
	new /obj/effect/decal/cleanable/blood/gibs (src.loc)
	..()
	ghostize()

////////////////////////////
//		Hunter AI
////////////////////////////

////////////////////////////
//		Ash Hunter
////////////////////////////


/mob/living/simple_mob/humanoid/cultist/hunter/surt // This Mob is not meant to be fair, he is not meant to fight regular crew he is to be pitted against heavily armed explo teams to see if he can wipe them out.
	name = "Itinerant Blood Hunter"
	desc = "This Blood Hunter is far from home. Strange energies course around him, protecting him from the environment. What eldritch influence drew him to this place?" // Blood Hunter on vacation.

	heat_resist = 1 //Might make this 0.75 if 1 is too much resistance for a boss monster. This guy's just a placeholder until we get the Miner in anyways.

/mob/living/simple_mob/humanoid/cultist/hunter
	endurance = 175 //Ehhh, this AI is like mini-boss at best //Old 87
	movement_cooldown = 0
	melee_damage_lower = 21	//Saw Cleaver Brutality
	melee_damage_upper = 21

/// Immune to incapacitation by nature (stun, weakness, paralysis).

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/hunter)
	configure(atom_rules(armor_spec = "melee=60;bullet=50;laser=50;energy=80;bomb=30;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/hunter)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(delete_on_death = TRUE))
	configure(mob_kind(attack_cooldown = 7.5, death_message = "laughs as he melts away. His laughs echo through the air even after only a dense red goo remains."))
	immune_to_incapacitation()
