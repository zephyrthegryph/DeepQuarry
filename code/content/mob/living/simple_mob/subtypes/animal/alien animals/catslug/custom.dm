//Custom Catslugs and the Rascal's Pass bunch

/mob/living/simple_mob/vore/alienanimals/catslug/custom
	desc = "A noodley bodied creature with thin arms and legs, and gloomy dark eyes. You shouldn't ever see this."
	humanoid_hands = 1	//These should all be ones requiring admin-intervention to play as, so they can get decent tool-usage, as a treat.
	var/siemens_coefficient = 1 		//Referenced later by others.
	can_wear_hat = FALSE

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom)
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("digestable" = 0))
	configure(mob_movement(makes_dirt = 0))
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)
	verb_entry(/mob/living/simple_mob/vore/alienanimals/catslug/proc/catslug_color, hidden = TRUE) //Most of these have custom sprites with colour already, so we'll not let them have this.

/mob/living/simple_mob/vore/alienanimals/catslug/custom/gatslug
	name = "Officer Gatslug"
	desc = "A light red-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one seems to be wearing a security cap, bandolier and holobadge."
	tt_desc = "Mollusca Felis Magistratus"
	icon_state = "gatslug"
	icon_living = "gatslug"
	icon_rest = "gatslug_rest"
	icon_dead = "gatslug_dead"
	holder_type = /obj/item/holder/catslug/custom/gatslug
	endurance = 75
	melee_damage_lower = 5
	melee_damage_upper = 10		//"Trained" security member, so they can hit that little bit harder
	taser_kill = 0		//Shouldn't be weak to accidental friendly fire from other officers
	myid_access = list(ACCESS_SECURITY, ACCESS_SEC_DOORS, ACCESS_FORENSICS_LOCKERS, ACCESS_MAINT_TUNNELS)

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/gatslug)
	configure(atom_rules(armor_spec = "melee=15", catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/gatslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/gatslug))

/mob/living/simple_mob/vore/alienanimals/catslug/custom/medislug
	name = "Doctor Mlemulon"
	desc = "A pale blue-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one appears to have a nurses hat perched upon it's head and a medi-hud."
	tt_desc = "Mollusca Felis Medicus"
	icon_state = "medislug"
	icon_living = "medislug"
	icon_rest = "medislug_rest"
	icon_dead = "medislug_dead"
	holder_type = /obj/item/holder/catslug/custom/medislug
	myid_access = list(ACCESS_MEDICAL, ACCESS_MORGUE, ACCESS_SURGERY, ACCESS_CHEMISTRY, ACCESS_VIROLOGY, ACCESS_GENETICS)

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/medislug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/medislug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/medislug))

/mob/living/simple_mob/vore/alienanimals/catslug/custom/scienceslug
	name = "Professor Nubbins"
	desc = "A purple-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one looks to be wearing a swanky white science beret, as well as a pair of goggles."
	tt_desc = "Mollusca Felis Inquisitorem"
	icon_state = "scienceslug"
	icon_living = "scienceslug"
	icon_rest = "scienceslug_rest"
	icon_dead = "scienceslug_dead"
	holder_type = /obj/item/holder/catslug/custom/scienceslug
	myid_access = list(ACCESS_ROBOTICS, ACCESS_TOX, ACCESS_TOX_STORAGE, ACCESS_RESEARCH, ACCESS_XENOBIOLOGY, ACCESS_XENOARCH)

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/scienceslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/scienceslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/scienceslug))

/mob/living/simple_mob/vore/alienanimals/catslug/custom/cargoslug
	name = "Technician Nermley"
	desc = "A brown-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one has a flipped-round baseball cap on their head and a pair of black mittens."
	tt_desc = "Mollusca Felis Quisquiliae"
	icon_state = "cargoslug"
	icon_living = "cargoslug"
	icon_rest = "cargoslug_rest"
	icon_dead = "cargoslug_dead"
	holder_type = /obj/item/holder/catslug/custom/cargoslug
	myid_access = list(ACCESS_MAINT_TUNNELS, ACCESS_MAILSORTING, ACCESS_CARGO, ACCESS_CARGO_BOT, ACCESS_MINING, ACCESS_MINING_STATION)

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/cargoslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/cargoslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/cargoslug))

/mob/living/simple_mob/vore/alienanimals/catslug/custom/capslug
	name = "Captain Crumsh"
	desc = "A regal-blue furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one wears an impressive tower of hats upon it's head. Exudes a sense of superiority, clearly this 'slug has more porl than you."
	tt_desc = "Mollusca Felis Praefectus"
	icon_state = "capslug"
	icon_living = "capslug"
	icon_rest = "capslug_rest"
	icon_dead = "capslug_dead"
	holder_type = /obj/item/holder/catslug/custom/capslug
	myid_access = list(ACCESS_HEADS, ACCESS_KEYCARD_AUTH)		//Same access as a bridge secretary.

//Royal slug

/mob/living/simple_mob/vore/alienanimals/catslug/custom/royalslug
	name = "Ruler Purrton"
	desc = "A golden-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one is adorned with a crown and red cloak, very fancy."
	tt_desc = "Mollusca Felis Royallis"
	icon_state = "catslugking"
	icon_living = "catslugking"
	icon_rest = "catslugking_rest"
	icon_dead = "catslugking_dead"

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/royalslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/royalslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/royalslug))

//crypt slug

/mob/living/simple_mob/vore/alienanimals/catslug/custom/cryptslug
	name = "Keeper Sluguloth"
	desc = "A dark-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one is adorned with a dark cloak that obscures most of it's body."
	tt_desc = "Mollusca Felis Necrosis"
	icon_state = "cryptslug"
	icon_living = "cryptslug"
	icon_rest = "cryptslug_rest"
	icon_dead = "cryptslug_dead"

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/cryptslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/cryptslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/cryptslug))

//jungle slug

/mob/living/simple_mob/vore/alienanimals/catslug/custom/exploslug
	name = "Explorer Pawdiana"
	desc = "A green-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one is adorned with an explorers hat and vest."
	tt_desc = "Mollusca Felis Exploris"
	icon_state = "exploslug"
	icon_living = "exploslug"
	icon_rest = "exploslug_rest"
	icon_dead = "exploslug_dead"

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/exploslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/exploslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/exploslug))

//xmas slug

/mob/living/simple_mob/vore/alienanimals/catslug/custom/santaslug
	name = "Santa Claws"
	desc = "A green-furred noodley bodied creature with thin arms and legs, and gloomy dark eyes. This one is adorned with a festive coat, hat, boots and ribbons on it's tail."
	tt_desc = "Mollusca Felis Solstice"
	icon_state = "santaslug"
	icon_living = "santaslug"
	icon_rest = "santaslug_rest"
	icon_dead = "santaslug_dead"

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/santaslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/santaslug)))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/santaslug))

//=============================
//Admin-spawn only catslugs end
//=============================

//Suslug's below
/* Removing among us meme
/mob/living/simple_mob/vore/alienanimals/catslug/suslug
	name = "suslug"
	desc = "A noodley bodied creature wearing a colorful space suit. Suspicious..."
	tt_desc = "Mollusca Felis Amogus"
	icon_state = "suslug"
	icon_living = "suslug"
	icon_rest = "suslug_rest"
	icon_dead = "suslug_dead"
	var/is_impostor = FALSE
	var/kill_cooldown = 0
	can_wear_hat = FALSE

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/impostor
	is_impostor = TRUE

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/suslug)
	verb_entry(/mob/living/simple_mob/vore/alienanimals/catslug/suslug/proc/assussinate)

/// Its glowing-free eyes, untinted by the body colour.
/mob/living/simple_mob/vore/alienanimals/catslug/suslug/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image(icon, "[look.state_so_far(src)]-eyes", appearance_flags = (RESET_COLOR|KEEP_APART|PIXEL_SCALE)))

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/can_ventcrawl()
	if(!is_impostor)
		to_chat(src, span_notice("You are not an impostor! You can't vent!"))
		return FALSE
	.=..()

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/examine(mob/user)
	. = ..()

	if(istype(user, /mob/living/simple_mob/vore/alienanimals/catslug/suslug))
		var/mob/living/simple_mob/vore/alienanimals/catslug/suslug/us = user
		if(us.is_impostor)
			if(src.is_impostor)
				. += span_notice("They appear to be a fellow impostor!")
			else
				. += span_notice("They appear to be a filthy innocent!")

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/proc/assussinate()
	set name = "Kill Innocent"
	set category = VERB_CAT_ABILITIES_CATSLUG
	set desc = "Kill an innocent suslug!"
	if(!is_impostor)
		to_chat(src, span_notice("You are not an impostor! You can't kill like that!"))
		return
	if(ELAPSED(src, kill_cooldown, CLOCK_WORLD) < 1 MINUTE)
		to_chat(src, span_notice("You cannot kill so soon after previous kill!"))
		return

	var/mob/living/simple_mob/vore/alienanimals/catslug/suslug/target
	var/list/victims = list()
	for(var/mob/living/simple_mob/vore/alienanimals/catslug/suslug/S in range(1))
		if(!S.is_impostor)
			victims += S
	if(!victims || !victims.len)
		to_chat(src, span_warning("There are no innocent suslugs nearby!"))
		return
	if(victims.len == 1)
		target = victims[1]
	else
		target = tgui_input_list(src, "Kill", "Pick a victim", victims)

	if(target && istype(target))
		target.injure(INJURY_BLUNT, target.get_endurance() * 30, source = src, flags = INJURE_IGNORE_RESISTANCE)
		act_message(src, target, null, MSG_OTHERS(span_warning("%U% kills %T%!")))
		STAMP(src, kill_cooldown, CLOCK_WORLD)

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color
	picked_color = TRUE

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/white
	color = COLOR_WHITE

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/red
	color = COLOR_RED

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/blue
	color = COLOR_BLUE

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/lime
	color = COLOR_LIME

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/cyan
	color = COLOR_CYAN

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/pink
	color = COLOR_PINK

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/yellow
	color = COLOR_YELLOW

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/orange
	color = COLOR_ORANGE

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/green
	color = COLOR_GREEN

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/violet
	color = COLOR_VIOLET

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/orange
	color = COLOR_ORANGE

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/brown
	color = COLOR_DARK_BROWN

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/grey
	color = COLOR_GRAY

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/black
	color = COLOR_DARK_GRAY

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/beige
	color = COLOR_BEIGE

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/maroon
	color = COLOR_MAROON

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/navy
	color = COLOR_NAVY

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/light_pink
	color = COLOR_LIGHT_PINK

/mob/living/simple_mob/vore/alienanimals/catslug/suslug/color/light_yellow
	color = COLOR_WHEAT
*/

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug/custom/capslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug/custom/capslug)))
	configure(mob_rules(faction = FACTION_NEUTRAL))
	configure(living_rules(say_list_type = /datum/say_list/catslug/custom/capslug))
	owns_one(nameof(mob_radio), /obj/item/radio/headset, starts = /obj/item/radio/headset/mob_headset/capslug)
