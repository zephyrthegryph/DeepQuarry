/mob/living/simple_mob/vore/wolftaur
	name = "wolftaur"
	desc = "A large creature with a humanoid upperbody and more feral formed lower body, with four legs and two arms."

	icon_state = "wolftaurwhite"
	icon = 'icons/mob/vore64x32.dmi'

	harm_intent_damage = 5
	melee_damage_lower = 2
	melee_damage_upper = 5

	response_help = "heavily pets"
	response_disarm = "shoves"
	response_harm = "bites"

	attacktext = list("kicked","bit")

	say_list_type = /datum/say_list/wolftaur

	var/random_skin = 1
	var/list/skins = list( // ALLOW(instance_list): d: per-mob skins with starting entries, edited at runtime; mobs are few
		"wolftaurwhite",
		"wolftaurwhitec",
		"wolftaurbrown",
		"wolftaurbrownc",
		"wolftaurblack",
		"wolftaurblackc",
		"wolftaurwood",
		"wolftaurwoodc",
		"wolftaurdark"
	)

	old_x = -16
	old_y = 0
	default_pixel_x = -16
	pixel_x = -16
	pixel_y = 0
	faction = FACTION_WOLFTAUR

CAPABILITIES(/mob/living/simple_mob/vore/wolftaur)
	rolls(nameof(icon_living), nameof(skins), when = nameof(random_skin))
	look_from(nameof(icon_living), rest = "*_rest", dead = "*-dead", only_if = nameof(random_skin))
	rolls(nameof(size_multiplier), range_of(0.9, 2, 0.01)) // the larger roll of the two old overrides (syndimobs.dm ran last)

// Activate Noms!
/mob/living/simple_mob/vore/wolftaur
	vore_active = 1
	vore_bump_chance = 10
	vore_pounce_chance = 50
	vore_standing_too = 1
	vore_ignores_undigestable = 0 // Catgirls just want to eat yoouuu
	vore_default_mode = DM_DIGEST // Chance that catgirls just wanna bellycuddle yoouuuu!
	vore_digest_chance = 25 // But squirming might make them gurgle...
	vore_icons = SA_ICON_LIVING | SA_ICON_REST

/datum/say_list/wolftaur
	speak = list("Grrr.","Huff","What do you want?","Hmm.","One thing after another.","Where's the food?")
	emote_hear = list("grumbles","barks","sighs")
	emote_see = list("shakes her head","stomps","stretches","rolls her eyes")

/mob/living/simple_mob/vore/wolftaur/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected_of(src)
	B.name = "stomach"
	B.desc = "After a gruelling compressive traversal down through the taur's gullet, you briefly get deposited in an oppressively tight stomach at it's humanoid waist. However, the wolf has little interest in keeping you here, instead treating you as a mere snack, an orifice opens beneath you and you're soon dragged deeper into her depths. Soon you're splashing into an active, waiting caustic slurry, and the world around you drops as though you're trapped in a hammock. The taur's underbelly sags with your weight, and you feel a heavy pat from the woman outside settling in to make the most of her meal."
	B.set_mode_flags(DM_FLAG_THICKBELLY)
	B.set_digest_brute(2)
	B.set_digest_burn(2)
	B.set_digest_oxy(1)
	B.set_digestchance(100)
	B.set_absorbchance(0)
	B.set_escapechance(5)
	B.set_selective_preference(DM_DIGEST)
	B.escape_stun = 5

/mob/living/simple_mob/vore/wolftaur/clown
	name = "wolftaur"
	desc = "What the hell is this outfit!?"
	icon_state = "wolftaurclown"
	random_skin = 0
	icon_living = "wolftaurclown"
	icon_rest = "wolftaurclown_rest"
	icon_dead = "wolftaurclown-dead"

/mob/living/simple_mob/vore/wolftaur/white
	icon_state = "wolftaurwhite"
	random_skin = 0
	icon_living = "wolftaurwhite"
	icon_rest = "wolftaurwhite_rest"
	icon_dead = "wolftaurwhite-dead"

/mob/living/simple_mob/vore/wolftaur/whiteclothed
	icon_state = "wolftaurwhitec"
	random_skin = 0
	icon_living = "wolftaurwhitec"
	icon_rest = "wolftaurwhitec_rest"
	icon_dead = "wolftaurwhitec-dead"

/mob/living/simple_mob/vore/wolftaur/brown
	icon_state = "wolftaurbrown"
	random_skin = 0
	icon_living = "wolftaurbrown"
	icon_rest = "wolftaurbrown_rest"
	icon_dead = "wolftaurbrown-dead"

/mob/living/simple_mob/vore/wolftaur/brownclothed
	icon_state = "wolftaurbrownc"
	random_skin = 0
	icon_living = "wolftaurbrownc"
	icon_rest = "wolftaurbrownc_rest"
	icon_dead = "wolftaurbrownc-dead"

/mob/living/simple_mob/vore/wolftaur/black
	icon_state = "wolftaurblack"
	random_skin = 0
	icon_living = "wolftaurblack"
	icon_rest = "wolftaurblack_rest"
	icon_dead = "wolftaurblack-dead"

/mob/living/simple_mob/vore/wolftaur/blackclothed
	icon_state = "wolftaurblackc"
	random_skin = 0
	icon_living = "wolftaurblackc"
	icon_rest = "wolftaurblackc_rest"
	icon_dead = "wolftaurblackc-dead"

/mob/living/simple_mob/vore/wolftaur/red
	icon_state = "wolftaurwood"
	random_skin = 0
	icon_living = "wolftaurwood"
	icon_rest = "wolftaurwood_rest"
	icon_dead = "wolftaurwood-dead"

/mob/living/simple_mob/vore/wolftaur/redclothed
	icon_state = "wolftaurwoodc"
	random_skin = 0
	icon_living = "wolftaurwoodc"
	icon_rest = "wolftaurwoodc_rest"
	icon_dead = "wolftaurwoodc-dead"

/mob/living/simple_mob/vore/wolftaur/dark
	icon_state = "wolftaurdark"
	random_skin = 0
	icon_living = "wolftaurdark"
	icon_rest = "wolftaurdark_rest"
	icon_dead = "wolftaurdark-dead"
