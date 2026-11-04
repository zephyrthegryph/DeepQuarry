/mob/living/simple_mob/slime/xenobio/metal/get_mechanics_info(list/additional_information)
	return ..(list("This slime is a lot more durable and tough to damage than the others. It also seems to provoke others to attack it over others.") + additional_information)

/mob/living/simple_mob/slime/xenobio/metal
	desc ="This slime is a lot more resilient than the others, due to having a metamorphic metallic and sloped surface."
	color = "#5F5F5F"
	slime_color = "metal"
	shiny = TRUE
	coretype = /obj/item/slime_extract/metal
	player_msg = "You are <b>more resilient and armored</b> than more slimes. Your attacks will also encourage less intelligent enemies to focus on you."

	endurance = 250
	endurance_adult = 350

	// The sloped armor.
	// It's resistant to most weapons (but a spraybottle still kills it rather fast).

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/silver,
			/mob/living/simple_mob/slime/xenobio/yellow,
			/mob/living/simple_mob/slime/xenobio/gold,
			/mob/living/simple_mob/slime/xenobio
		)

/mob/living/simple_mob/slime/xenobio/metal/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		L.taunt(src, TRUE) // We're the party tank now.

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/metal)
	configure(atom_rules(armor_spec = "melee=25;bullet=25;laser=25;energy=50;bomb=80;bio=100;rad=100"))
