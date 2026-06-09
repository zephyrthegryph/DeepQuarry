// Gygaxes are tough but also fast.
// Their AI, unlike most, will advance towards their target instead of remaining in place.

/datum/category_item/catalogue/technology/gygax
	name = "Exosuit - Gygax"
	desc = "The Gygax is a relatively modern exosuit, built to be lightweight and agile, while still being fairly durable. \
	These traits have made them rather popular among well funded private and corporate security forces, who desire \
	the ability to rapidly respond to conflict.\
	<br><br>\
	One special feature of this model is that the actuators that \
	drive the exosuit can have their safeties disabled in order to achieve a short-term burst of unparalleled speed, \
	at the expense of damaging the exosuit considerably."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/mechanical/mecha/combat/gygax
	name = "gygax"
	desc = "A lightweight, security exosuit. Popular among private and corporate security."
	catalogue_data = list(/datum/category_item/catalogue/technology/gygax)
	icon_state = "gygax"
	movement_cooldown = -1
	wreckage = /obj/structure/loot_pile/mecha/gygax

	maxHealth = 300
	armor = list(
				"melee"		= 25,
				"bullet"	= 20,
				"laser"		= 30,
				"energy"	= 15,
				"bomb"		= 0,
				"bio"		= 100,
				"rad"		= 100
				)

	projectile_dispersion = 8
	projectiletype = /obj/item/projectile/beam/midlaser

	ai_holder_type = /datum/ai_holder/simple_mob/intentional/adv_dark_gygax

/mob/living/simple_mob/mechanical/mecha/combat/gygax/manned
	pilot_type = /mob/living/simple_mob/humanoid/merc/ranged // Carries a pistol.


// A stronger variant.

/datum/category_item/catalogue/technology/dark_gygax
	name = "Exosuit - Dark Gygax"
	desc = "This exosuit is a variant of the regular Gygax. It is generally referred to as the Dark Gygax, \
	due to being constructed from different materials that give it a darker appearance. Beyond merely looking \
	cosmetically different, the Dark Gygax also has various upgrades compared to the Gygax. It is much more \
	resilient, yet retains the agility and speed of the Gygax.\
	<br><br>\
	These are relatively rare compared to the other security exosuits, as most security forces are content with \
	a regular Gygax. Instead, this exosuit is often used by high-end asset protection teams, and mercenaries."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/mechanical/mecha/combat/gygax/dark
	name = "dark gygax"
	desc = "A significantly upgraded Gygax security mech, often utilized by corporate asset protection teams and \
	PMCs."
	catalogue_data = list(/datum/category_item/catalogue/technology/dark_gygax)
	icon_state = "darkgygax"
	wreckage = /obj/structure/loot_pile/mecha/gygax/dark

	maxHealth = 400
	deflect_chance = 25
	has_repair_droid = TRUE
	armor = list(
				"melee"		= 40,
				"bullet"	= 40,
				"laser"		= 50,
				"energy"	= 35,
				"bomb"		= 20,
				"bio"		= 100,
				"rad"		= 100
				)

/mob/living/simple_mob/mechanical/mecha/combat/gygax/medgax
	name = "medgax"
	desc = "An unorthodox fusion of the Gygax and Odysseus exosuits, this one is fast, sturdy, and carries a wide array of \
	potent chemicals and delivery mechanisms. The doctor is in!"
	icon_state = "medgax"
	wreckage = /obj/structure/loot_pile/mecha/gygax/medgax

	projectile_dispersion = 8


// === merged from gygax_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
/mob/living/simple_mob/mechanical/mecha/combat/gygax
	movement_cooldown = 0 //Because normal Gygaxes are tougher then ths boss version with 0 speed
	projectiletype = /obj/item/projectile/energy/mob/midlaser

/mob/living/simple_mob/mechanical/mecha/combat/gygax/dark/advanced
	movement_cooldown = -2 //Because AADG needs all the help it can get.

/mob/living/simple_mob/mechanical/mecha/combat/gygax/aerostat
	desc = "A Vir System Authority automated combat mech with an aged apperance."
	ai_holder_type = /datum/ai_holder/simple_mob/intentional/adv_dark_gygax
	say_list = /datum/say_list/gygax_aerostat

/datum/say_list/gygax_aerostat
	speak = list("ALERT.","Hostile-ile-ile entities dee-twhoooo-wected.","Threat parameterszzzz- szzet.","Bring sub-sub-sub-systems uuuup to combat alert alpha-a-a.")
	emote_see = list("beeps menacingly","whirrs threateningly","scans its immediate vicinity")

	say_understood = list("Affirmative.", "Positive.")
	say_cannot = list("Denied.", "Negative.")
	say_maybe_target = list("Possible threat detected. Investigating.", "Motion detected.", "Investigating.")
	say_got_target = list("Threat detected.", "New task: Remove threat.", "Threat removal engaged.", "Engaging target.")
	say_threaten = list("This area is condemned by Vir System Authority. Please leave immediately. You have 20 seconds to comply.")
	say_stand_down = list("Visual lost.", "Error: Target not found.")
	say_escalate = list("Intruder is tresspassing. Maximum force authorized by Vir System Suthority.")
	threaten_sound = 'sound/mob/robots/GygaxIntruder4.ogg'
	stand_down_sound = 'sound/mob/robots/GygaxDanger.ogg'

/datum/ai_holder/simple_mob/ranged/kiting/threatening/drone_aerostat
	threaten_delay = 20 SECOND
	threaten_timeout = 30 SECONDS
