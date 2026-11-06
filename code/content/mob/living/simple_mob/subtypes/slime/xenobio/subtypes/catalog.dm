// Here are where all the other colors of slime live.
// They will generally fight each other if not Unified, meaning the xenobiologist has to seperate them.

// Tier 1.

/mob/living/simple_mob/slime/xenobio/purple/get_mechanics_info(list/additional_information)
	return ..(list("This slime spreads a toxin when it attacks. A biosuit or other thick armor can protect from the toxic attack.") + additional_information)

/mob/living/simple_mob/slime/xenobio/purple
	desc ="This slime is rather toxic to handle, as it is poisonous."
	color = "#CC23FF"
	slime_color = "purple"
	coretype = /obj/item/slime_extract/purple
	reagent_injected = REAGENT_ID_TOXIN
	player_msg = "You <b>inject a harmful toxin</b> when attacking."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark_purple,
			/mob/living/simple_mob/slime/xenobio/dark_blue,
			/mob/living/simple_mob/slime/xenobio/green,
			/mob/living/simple_mob/slime/xenobio
		)

/mob/living/simple_mob/slime/xenobio/blue/get_mechanics_info(list/additional_information)
	return ..(list("The slime is resistant to the cold, and attacks from this slime can inject cryotoxin into you. \
	A biosuit or other thick armor can protect from the injection.") + additional_information)

/mob/living/simple_mob/slime/xenobio/blue
	desc ="This slime produces 'cryotoxin' and uses it against their foes.  Very deadly to other slimes."
	color = "#19FFFF"
	slime_color = "blue"
	coretype = /obj/item/slime_extract/blue
	reagent_injected = REAGENT_ID_CRYOTOXIN
	cold_resist = 0.50 // Not as strong as dark blue, which has immunity.
	player_msg = "You <b>inject cryotoxin on attack</b>, which causes them to get very cold, slowing them down and harming them over time.<br>\
	You are also resistant to cold attacks."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark_blue,
			/mob/living/simple_mob/slime/xenobio/silver,
			/mob/living/simple_mob/slime/xenobio/pink,
			/mob/living/simple_mob/slime/xenobio
		)

/mob/living/simple_mob/slime/xenobio/silver/get_mechanics_info(list/additional_information)
	return ..(list("Tasers, including the slime version, are ineffective against this slime. The slimebaton still works.") + additional_information)

/mob/living/simple_mob/slime/xenobio/silver
	desc ="This slime is shiny, and can deflect lasers or other energy weapons directed at it."
	color = "#AAAAAA"
	slime_color = "silver"
	coretype = /obj/item/slime_extract/silver
	shiny = TRUE
	player_msg = "You <b>automatically reflect</b> lasers, beams, and tasers that hit you."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/metal,
			/mob/living/simple_mob/slime/xenobio/blue,
			/mob/living/simple_mob/slime/xenobio/amber,
			/mob/living/simple_mob/slime/xenobio/amber
		)

CAPABILITY(/mob/living/simple_mob/slime/xenobio/silver, reflects(list(/obj/item/projectile/beam, /obj/item/projectile/energy), 100))

/mob/living/simple_mob/slime/xenobio/cerulean
	desc = "This slime is generally superior in a wide range of attributes, compared to the common slime.  The jack of all trades, but master of none."
	color = "#4F7EAA"
	slime_color = "cerulean"
	coretype = /obj/item/slime_extract/cerulean

	// Less than the specialized slimes, but higher than the rest.
	endurance = 200
	endurance_adult = 250

	melee_damage_lower = 10
	melee_damage_upper = 30

	movement_cooldown = -1 // This actually isn't any faster due to AI limitations that hopefully the timer subsystem can fix in the future.

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/dark_blue,
		/mob/living/simple_mob/slime/xenobio/dark_blue,
		/mob/living/simple_mob/slime/xenobio/cerulean,
		/mob/living/simple_mob/slime/xenobio/cerulean
	)

// Tier 4

/mob/living/simple_mob/slime/xenobio/red/get_mechanics_info(list/additional_information)
	return ..(list("This slime is faster than the others. Attempting to discipline this slime will always cause it to go rabid and berserk.") + additional_information)

/mob/living/simple_mob/slime/xenobio/red
	desc ="This slime is full of energy, and very aggressive.  'The red ones go faster.' seems to apply here."
	color = "#FF3333"
	slime_color = "red"
	coretype = /obj/item/slime_extract/red
	movement_cooldown = -1 // See above.
	untamable = TRUE // Will enrage if disciplined.

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/red,
			/mob/living/simple_mob/slime/xenobio/oil,
			/mob/living/simple_mob/slime/xenobio/oil,
			/mob/living/simple_mob/slime/xenobio/orange
		)

/mob/living/simple_mob/slime/xenobio/sapphire/get_mechanics_info(list/additional_information)
	return ..(list("This slime uses more robust tactics when fighting and won't hold back, so it is dangerous to be alone \
	with one if hostile, and especially dangerous if they outnumber you.") + additional_information)

/mob/living/simple_mob/slime/xenobio/sapphire
	desc ="This slime seems a bit brighter than the rest, both figuratively and literally."
	color = "#2398FF"
	slime_color = "sapphire"
	shiny = TRUE
	glow_toggle = TRUE
	coretype = /obj/item/slime_extract/sapphire

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/sapphire,
		/mob/living/simple_mob/slime/xenobio/sapphire,
		/mob/living/simple_mob/slime/xenobio/gold,
		/mob/living/simple_mob/slime/xenobio/gold
	)

/mob/living/simple_mob/slime/xenobio/light_pink/get_mechanics_info(list/additional_information)
	return ..(list("This slime is effectively always disciplined initially.") + additional_information)

/mob/living/simple_mob/slime/xenobio/light_pink
	desc ="This slime seems a lot more peaceful than the others."
	color = "#FF8888"
	slime_color = "light pink"
	coretype = /obj/item/slime_extract/light_pink

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/pink,
		/mob/living/simple_mob/slime/xenobio/pink,
		/mob/living/simple_mob/slime/xenobio/light_pink,
		/mob/living/simple_mob/slime/xenobio/light_pink
	)

// Special
/mob/living/simple_mob/slime/xenobio/rainbow/get_mechanics_info(list/additional_information)
	return ..(list("This slime is considered to be the same color as all other slime colors at the same time for the purposes of \
	other slimes being friendly to them, and therefore will never be harmed by another slime. \
	Attacking this slime will provoke the wrath of all slimes within range.") + additional_information)

/mob/living/simple_mob/slime/xenobio/rainbow
	desc ="This slime changes colors constantly."
	color = null // Uses a special icon_state.
	slime_color = "rainbow"
	coretype = /obj/item/slime_extract/rainbow
	icon_state_override = "rainbow"
	unity = TRUE
	player_msg = "You are <b>considered to be the same color as every slime</b>, \
	meaning that you are considered an ally to all slimes."

	slime_mutation = list(
		/mob/living/simple_mob/slime/xenobio/rainbow,
		/mob/living/simple_mob/slime/xenobio/rainbow,
		/mob/living/simple_mob/slime/xenobio/rainbow,
		/mob/living/simple_mob/slime/xenobio/rainbow
	)

/mob/living/simple_mob/slime/xenobio/rainbow
	unity = TRUE // what unify() sets: it counts every colour as its own

// The RD's pet slime.
/mob/living/simple_mob/slime/xenobio/rainbow/kendrick
	name = "Kendrick"
	desc = "The " + JOB_RESEARCH_DIRECTOR + "'s pet slime.  It shifts colors constantly."
	rainbow_core_candidate = FALSE
	// Doing pacify() in initialize() won't actually pacify the AI due to the ai_brain not existing due to parent initialize() not being called yet.
	// Instead lets just give them an ai_brain that does that for us.

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/rainbow/kendrick)
	configure(mob_rules(faction = FACTION_NEUTRAL))

/mob/living/simple_mob/slime/xenobio/rainbow/kendrick
	// born pacified (what pacify() sets on the mob; the slime base's update_mood() at init takes its mood and vore settings from it)
	harmless = TRUE
	melee_damage_upper = 0
	melee_damage_lower = 0
