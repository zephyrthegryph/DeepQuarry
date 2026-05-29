/mob/living/simple_mob/vore/scrubble
	name = "scrubble"
	desc = "A small skittish animal with some features resembling rodents and foxes. Usually seen coated with beige and brown fur, the scrubble has four ears that pivot quickly, two long fluffy tails and dark red eyes."
	catalogue_data = list(/datum/category_item/catalogue/fauna/scrubble)
	tt_desc = "vuldentia"
	icon = 'icons/mob/vore.dmi'
	icon_dead = "scrubble-dead"
	icon_living = "scrubble"
	icon_state = "scrubble"
	icon_rest = "scrubble_rest"
	faction = FACTION_SCRUBBLE
	friendly = list("nudges", "sniffs on", "rumbles softly at", "nuzzles")
	response_help = "bumps"
	response_disarm = "shoves"
	response_harm = "attacks"
	movement_cooldown = 0
	harm_intent_damage = 2
	melee_damage_lower = 1
	melee_damage_upper = 4
	maxHealth = 50
	attacktext = list("bites")
	see_in_dark = 8
	minbodytemp = 0
	say_list_type = /datum/say_list/scrubble

	vore_bump_chance = 25
	vore_digest_chance = 50
	vore_escape_chance = 5
	vore_pounce_chance = 1000
	vore_active = 1
	vore_icons = 1
	vore_icons = SA_ICON_LIVING | SA_ICON_REST
	vore_capacity = 1
	swallowTime = 50
	vore_ignores_undigestable = TRUE
	vore_default_mode = DM_DIGEST
	vore_pounce_maxhealth = 1000
	vore_bump_emote = "pounces on"
	vore_pounce_falloff = 0 //Always eat someone at full health
	vore_standing_too = 1

/mob/living/simple_mob/vore/scrubble/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "Despite the small size of the scrubble, it seems to have a lot of energy behind it. The critter dives atop you in a panic, its maw quickly engulfing your head as its paws flail scrabble against you, hot slobber slathering across your tightly trapped face. It takes a little repositioning to get itself in the right position, but soon the creature is gulping its way down your entire body. Somehow it manages to squeeze you completely into a gut that should rightly be far too small for anything but a mouse, bundling up your body into a tight ball as the walls around you clench in tightly to keep you nice and compact. The sounds of burbling and glorping echo through the intensely tight space as the stomach lining grinds in thick oozes against your skin, pressure so high that you can barely move a muscle."
	B.mode_flags = DM_FLAG_THICKBELLY
	B.belly_fullscreen = "VBO_fleshs"
	B.digest_brute = 1
	B.digest_burn = 1
	B.digest_oxy = 0
	B.digestchance = 100
	B.absorbchance = 0
	B.escapechance = 15
	B.selective_preference = DM_DIGEST
	B.escape_stun = 5

/datum/say_list/scrubble
	emote_hear = list("yips","squeaks","chirps")
	emote_see = list("looks around frantically","sniffs at the air","wafts its tails","flickers its four ears")

/datum/category_item/catalogue/fauna/scrubble
	name = "Extra-Realspace Fauna - Scrubble"
	desc = "Classification: Vuldentia\
	<br><br>\
	The Scrubble is a small creature found in redgate locations that has properties resembling those of rodents and vulpines. \
	Primarily a scavanger, the scrubble is known to eat all sorts of organic material, whether it's vegetable or meat, but generally does not hunt on its own. Largely defenseless against larger creature, the scrubble is certainly a prey species. \
	Their geneneral behaviour supports this, as they will heavily avoid interaction with any other species that approach it, usually darting away rapidly and keeping a distance. However, they have been known to act defensively should they be completely cornered."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/vore/scrubble/PounceTarget(mob/living/M, successrate = 100)
	vore_pounce_cooldown = world.time + 20 SECONDS // don't attempt another pounce for a while
	if(prob(successrate)) // pounce success!
		M.Weaken(5)
		M.visible_message(span_danger("\The [src] pounces on \the [M]!"))
	else // pounce misses!
		M.visible_message(span_danger("\The [src] attempts to pounce \the [M] but misses!"))
		playsound(src, 'sound/weapons/punchmiss.ogg', 25, 1, -1)

	if(will_eat(M) && (!M.canmove || vore_standing_too)) //if they're edible then eat them too
		return EatTarget(M)
	else
		return //just leave them

//AI
