/mob/living/simple_mob/vore/blaidd
	name = "blaidd"
	desc = "A wolf like creature with a large, spikey mane."
	tt_desc = "Canis glamoris"
	icon = 'icons/mob/vore64x32.dmi'
	icon_dead = "blaidd-dead"
	icon_living = "blaidd"
	icon_state = "blaidd"
	icon_rest = "blaidd_rest"
	old_x = -16
	old_y = 0
	default_pixel_x = -16
	pixel_x = -16
	pixel_y = 0
	faction = FACTION_GLAMOUR
	catalogue_data = list(/datum/category_item/catalogue/fauna/blaidd)

	harm_intent_damage = 10
	melee_damage_lower = 10
	melee_damage_upper = 20
	maxHealth = 300

	minbodytemp = 0

	max_buckled_mobs = 1
	mount_offset_y = 14
	mount_offset_x = 2
	can_buckle = TRUE
	buckle_movable = TRUE
	buckle_lying = FALSE
	var/blaidd_invisibility

	vore_bump_chance = 25
	vore_digest_chance = 50
	vore_escape_chance = 5
	vore_pounce_chance = 100
	vore_active = 1
	vore_icons = 1
	vore_icons = SA_ICON_LIVING | SA_ICON_REST
	vore_capacity = 1
	swallowTime = 50
	vore_ignores_undigestable = TRUE
	vore_default_mode = DM_SELECT
	vore_pounce_maxhealth = 125
	vore_bump_emote = "tries to devour"

/mob/living/simple_mob/vore/blaidd/Login()
	. = ..()
	if(!riding_datum)
		riding_datum = new /datum/riding/simple_mob(src)
	verbs |= /mob/living/simple_mob/proc/animal_mount
	verbs |= /mob/living/proc/toggle_rider_reins
	verbs |= /mob/living/simple_mob/vore/blaidd/proc/blaidd_invis
	movement_cooldown = -1

/mob/living/simple_mob/vore/blaidd/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The canine pounces atop you and wastes now time in wrapping its jaws around your entire head. The beast is strong and determined, there is no wriggling out of it's iron grip. Within its maw, the tongue slathers canine drool across you, hot doglike breaths wash across your face, triangular teeth hold you firmly in place. It doesn't take long before the blaidd is gulping you down aggressively, like a big chunk of meat. The creature's stomach distends and hangs beneath it with your weight, swaying heavily not just with your movements, but every step from the wolf. Bound up uncomfortably tight in this sweltering, dark gut, movement is almost impossible and it's hard to tell which way is up."
	B.vore_sound = "Tauric Swallow"
	B.release_sound = "Pred Escape"
	B.mode_flags = DM_FLAG_THICKBELLY
	B.fancy_vore = 1
	B.selective_preference = DM_DIGEST
	B.vore_verb = "devour"
	B.digest_brute = 1
	B.digest_burn = 1
	B.digest_oxy = 0
	B.selectchance = 50
	B.absorbchance = 0
	B.escapechance = 10
	B.escape_stun = 5
	B.contamination_color = "grey"
	B.contamination_flavor = "Wet"
	B.emote_lists[DM_DIGEST] = list(
		"The blaidd growls as the gut squeeze over your body, smearing caustic oozes into your form!",
		"You are turned over and walls clench around you as the beast moves about, tossing more digestive juices over your body.",
		"You can't make out any sound from the outside as the gut grumbled and reverberates over your body.",
		"As the thinning air begins to make you feel dizzy, menacing bworps and grumbles fill that dark, constantly shifting organ!",
		"The constant, rhythmic kneading and massaging starts to take its toll along with the muggy heat, making you feel weaker and weaker!",
		"The blaidd presses its gut against the floor, giving you a full body crush deep within its gut. The strain on your body aids digestion, making you all the easier to work down.")

/datum/category_item/catalogue/fauna/blaidd
	name = "Extra-Realspace Fauna - Blaidd"
	desc = "Classification: Canis glamoris\
	<br><br>\
	A large canine found in whitespace or the Glamour, distinguished easily by a large spikey mane and lightly striped pattern. The Blaidd, named from the glamourspeak word for wolf, is known to be a ferocious hunter and predator. It is a carnivore that stalks prey from a distance silently, whilst its otherwise quite striking fur blends it well into the environment through some sort of active camouflage, a less powerful version of that seen in the local Lleill. It generally avoids attacking its prey when it feels it is being watched, but once it is able to finally pounce on a target, it will not retreat until forced."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/vore/blaidd/update_icon()
	. = ..()
	if(vore_active)
		var/voremob_awake = FALSE
		if(icon_state == icon_living)
			voremob_awake = TRUE
			if(blaidd_invisibility)
				icon_state = "[icon_living]_cloaked"
		update_fullness()
		if(!vore_fullness)
			update_transform()
			return 0
		else if((stat == CONSCIOUS) && (!icon_rest || !resting || !incapacitated(INCAPACITATION_DISABLED)) && (vore_icons & SA_ICON_LIVING))
			if(blaidd_invisibility)
				icon_state = "[icon_living]_cloaked-[vore_fullness]"
			else
				icon_state = "[icon_living]-[vore_fullness]"
		else if(stat >= DEAD && (vore_icons & SA_ICON_DEAD))
			icon_state = "[icon_dead]-[vore_fullness]"
		else if(((stat == UNCONSCIOUS) || resting || incapacitated(INCAPACITATION_DISABLED) ) && icon_rest && (vore_icons & SA_ICON_REST))
			icon_state = "[icon_rest]-[vore_fullness]"
		if(vore_eyes && voremob_awake) //Update eye layer if applicable.
			remove_eyes()
			add_eyes()
	update_transform()

/mob/living/simple_mob/vore/blaidd/proc/blaidd_invis()
	set name = "Invisibility"
	set desc = "Change your appearance to match your surroundings, becoming somewhat invisible to the naked eye."
	set category = "Abilities"

	if(blaidd_invisibility)
		blaidd_invisibility = 0
	else
		blaidd_invisibility = 1

	update_icon()

// DQEdit - legacy /datum/ai_brain/.../can_attack and /engage_target overrides
// removed in the combat migration. Behaviors now handled by the brain.

/mob/living/simple_mob/vore/blaidd/hostile
