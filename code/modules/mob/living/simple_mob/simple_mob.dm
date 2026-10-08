// Reorganized and somewhat cleaned up.
// AI code has been made into a datum, inside the AI module folder.

/mob/living/simple_mob
	name = "animal"
	desc = ""
	icon = 'icons/mob/animal.dmi'
	endurance = 20

	// Generally we don't want simple_mobs to get displaced when bumped into due to it trivializing combat with windup attacks.
	// Some subtypes allow displacement, like passive animals.
	mob_bump_flag = HEAVY
	mob_swap_flags = ~HEAVY
	mob_push_flags = ~HEAVY

	has_huds = TRUE // We do show AI status huds for buildmode players

	digest_leave_remains = TRUE

	var/tt_desc = null //Tooltip description

	//Settings for played mobs
	var/show_stat_health = 1		// Does the percentage health show in the stat panel for the mob
	var/draws_life_state = TRUE		// FALSE: the type keeps its mapped icon_state and its base draw adds no life state, hands, fullness, pounce or eyes
	var/has_hands = 0				// Set to 1 to enable the use of hands and the hands hud
	var/humanoid_hands = 0			// Can a player in this mob use things like guns or AI cards?
	var/hand_form = "hands"			// Used in IsHumanoidToolUser. 'Your X are not fit-'.
	var/list/hud_gears				// Slots to show on the hud (typically none)
	var/ui_icons					// Icon file path to use for the HUD, otherwise generic icons are used
	var/image/r_hand_sprite				// If they have hands,
	var/image/l_hand_sprite				// they could use some icons.
	var/player_msg					// Message to print to players about 'how' to play this mob on login.

	//Mob icon/appearance settings
	var/icon_living = ""			// The iconstate if we're alive, required
	var/icon_dead = ""				// The iconstate if we're dead, required
	var/icon_gib = "generic_gib"	// The iconstate for being gibbed, optional. Defaults to a generic gib animation.
	var/icon_rest = null			// The iconstate for resting, optional
	var/has_eye_glow = FALSE		// If true, adds an overlay over the lighting plane for [icon_state]-eyes.
	var/custom_eye_color = null
	attack_icon = 'icons/effects/effects.dmi' //Just the default, played like the weapon attack anim
	attack_icon_state = "slash" //Just the default

	//Mob talking settings
	universal_speak = 0				// Can all mobs in the entire universe understand this one?
	var/has_langs = list(LANGUAGE_GALCOM)// Text name of their language if they speak something other than galcom. They speak the first one.

	//Movement things.
	var/movement_cooldown = 1 // 1 is slower than normal human speed // Lower is faster.
	var/movement_sound = null			// If set, will play this sound when it moves on its own will.
	var/turn_sound = null				// If set, plays the sound when the mob's dir changes in most cases.
	var/movement_shake_radius = 0		// If set, moving will shake the camera of all living mobs within this radius slightly.
	var/aquatic_movement = 0			// If set, the mob will move through fluids with no hinderance.

	//Mob interaction
	var/response_help   = "tries to help"	// If clicked on help intent
	var/response_disarm = "tries to disarm" // If clicked on disarm intent
	var/response_harm   = "tries to hurt"	// If clicked on harm intent
	var/list/friends		// Mobs on this list wont get attacked regardless of faction status. Lazy.
	var/harm_intent_damage = 3		// How much an unarmed harm click does to this mob.
	var/list/loot_list		// The list of lootable objects to drop, with "/path = prob%" structure. Interned per subtype in Initialize().
	var/obj/item/card/id/myid// An ID card if they have one to give them access to stuff.
	var/organ_names = /datum/decl/mob_organ_names //'False' bodyparts that can be shown as hit by projectiles in place of the default humanoid bodyplan.

	//Mob environment settings
	var/minbodytemp = 250			// Minimum "okay" temperature in kelvin
	var/maxbodytemp = 350			// Maximum of above
	var/heat_damage_per_tick = 3	// Amount of damage applied if animal's body temperature is higher than maxbodytemp
	var/cold_damage_per_tick = 2	// Same as heat_damage_per_tick, only if the bodytemperature it's lower than minbodytemp

	var/min_oxy = 5					// Oxygen in moles, minimum, 0 is 'no minimum'
	var/max_oxy = 0					// Oxygen in moles, maximum, 0 is 'no maximum'
	var/min_tox = 0					// Phoron min
	var/max_tox = 1					// Phoron max
	var/min_co2 = 0					// CO2 min
	var/max_co2 = 5					// CO2 max
	var/min_n2 = 0					// N2 min
	var/max_n2 = 0					// N2 max
	var/min_ch4 = 0					// CH4 min
	var/max_ch4 = 5					// CH4 max
	var/unsuitable_atoms_damage = 2	// This damage is taken when atmos doesn't fit all the requirements above

	//Hostility settings
	var/taser_kill = 1				// Is the mob weak to tasers

	//Attack ranged settings
	var/projectiletype				// The projectiles I shoot
	var/projectilesound				// The sound I make when I do it
	var/projectile_accuracy = 0		// Accuracy modifier to add onto the bullet when its fired.
	var/projectile_dispersion = 0	// How many degrees to vary when I do it.
	var/casingtype					// What to make the hugely laggy casings pile out of

	// Reloading settings, part of ranged code
	var/needs_reload = FALSE							// If TRUE, mob needs to reload occasionally
	var/reload_max = 1									// How many shots the mob gets before it has to reload, will not be used if needs_reload is FALSE
	var/reload_count = 0								// A counter to keep track of how many shots the mob has fired so far. Reloads when it hits reload_max.
	var/reload_time = 4 SECONDS							// How long it takes for a mob to reload. This is to buy a player a bit of time to run or fight.
	var/reload_sound = SFX_WEAPONS_FLIPBLADE	// What sound gets played when the mob successfully reloads. Defaults to the same sound as reloading guns. Can be null.

	//Mob melee settings
	var/melee_damage_lower = 2		// Lower bound of randomized melee damage
	var/melee_damage_upper = 6		// Upper bound of randomized melee damage
	// ALLOW(instance_list): d: per-mob attacktext with starting entries, edited at runtime; mobs are few
	var/list/attacktext = list("attacked") // "You are [attacktext] by the mob!"
	// ALLOW(instance_list): d: per-mob friendly with starting entries, edited at runtime; mobs are few
	var/list/friendly = list("nuzzles") // "The mob [friendly] the person."
	var/attack_sound = null				// Sound to play when I attack
	var/melee_miss_chance = 0			// percent chance to miss a melee attack.
	var/attack_armor_pen = 0			// How much armor pen this attack has.
	var/attack_injury_kind = INJURY_BLUNT	// What the melee attack inflicts (INJURY_*); armour is looked up by it.

	var/melee_attack_delay = 2			// If set, the mob will do a windup animation and can miss if the target moves out of the way.
	var/ranged_attack_delay = null
	var/special_attack_delay = null
	EXPIRY_DECLARE(ranged_cooldown)
	var/ranged_cooldown_time = 0
	var/picked_color = FALSE
	var/picked_size = FALSE

	//Special attacks
//	var/special_attack_prob = 0				// The chance to ATTEMPT a special_attack_target(). If it fails, it will do a regular attack instead.
											// This is commented out to ease the AI attack logic by being (a bit more) determanistic.
											// You should instead limit special attacks using the below vars instead.
	var/special_attack_min_range = null		// The minimum distance required for an attempt to be made.
	var/special_attack_max_range = null		// The maximum for an attempt.
	var/special_attack_charges = null		// If set, special attacks will work off of a charge system, and won't be usable if all charges are expended. Good for grenades.
	var/special_attack_cooldown = null		// If set, special attacks will have a cooldown between uses.
	COOLDOWN_DECLARE(special_attack_cooldown_until)			// world.time when a special attack occured last, for cooldown calculations.

	//Damage resistances
	var/grab_resist = 0				// Chance for a grab attempt to fail. Note that this is not a true resist and is just a prob() of failure.
	var/resistance = 0				// Damage reduction for all types
	armor_spec = "bio=100;rad=100" // Innate armour, read by injury_armor() through get_armor().
	// Protection against heat/cold/electric/water effects.
	// 0 is no protection, 1 is total protection. Negative numbers increase vulnerability.
	var/heat_resist = 0.0
	var/cold_resist = 0.0
	var/shock_resist = 0.0
	var/water_resist = 1.0
	var/poison_resist = 0.0
	var/thick_armor = FALSE // Stops injections and "injections".
	var/supernatural = FALSE		// Ditto.

	// don't process me if there's nobody around to see it
	low_priority = TRUE
	// Used for if the mob can drop limbs. Overrides species dmi.
	var/limb_icon
	// Used for if the mob can drop limbs. Overrides the icon cache key, so it doesn't keep remaking the icon needlessly.
	var/limb_icon_key
	var/understands_common = TRUE // Makes it so that simplemobs can understand galcomm without being able to speak it.
	var/heal_countdown = 5 // A cooldown ticker for passive healing
	var/list/myid_access	// Lazy per-subtype constant.
	var/ID_provided = FALSE
	// Move/Shoot/Attack delays based on damage
	var/damage_fatigue_mult = 1			// Our multiplier for how heavily mobs are affected by injury. [UPDATE THIS IF THE FORMULA CHANGES]: Formula = injury_level = round(rand(1,3) * damage_fatigue_mult * clamp(((rand(2,5) * vitality()) - rand(0,2)), 1, 5))
	var/injury_level = 0 				// What our injury level is. Rather than being the flat damage, this is the amount added to various delays to simulate injuries in a manner as lightweight as possible.
	var/threshold = 0.6					// When we start slowing down. Configure this setting per-mob. Default is 60%
	var/injury_enrages = FALSE			// Do injuries enrage (aka strengthen) our mob? If yes, we'll interpret how hurt we are differently.

	var/has_recoloured = FALSE
	COOLDOWN_DECLARE(hunting_cooldown)
	var/hasthermals = TRUE
	var/isthermal = 0

	//vars for vore_icons toggle control
	var/vore_icons_cache = null // null by default. Going from ON to OFF should store vore_icons val here, OFF to ON reset as null

	var/obj/movement_target //Used by some mobs to hunt down food. Mainly noodle and Ian.

	//no stripping of simplemobs
	strip_pref = FALSE
	blocks_emissive = EMISSIVE_BLOCK_UNIQUE // Note, this should be refactored to drop priority overlays

TRACKED(/mob/living/simple_mob, icon_living)
TRACKED(/mob/living/simple_mob, icon_dead)
TRACKED(/mob/living/simple_mob, icon_rest)
TRACKED(/mob/living/simple_mob, spitting)
TRACKED(/mob/living/simple_mob, pouncing)
TRACKED(/mob/living/simple_mob, r_hand_sprite)
TRACKED(/mob/living/simple_mob, l_hand_sprite)

CAPABILITIES(/mob/living/simple_mob)
	op("reload", ai(), wait(PROC_REF(reload_wait)), then(PROC_REF(reload_done)))
	mob_attacks()
	ref_many(nameof(tamers))
	owns_one(nameof(myid), /obj/item/card/id)
	owns_one(nameof(mob_radio), /obj/item/radio/headset)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(synthetic_emp_surge)))
	on_notice(/datum/notice/hit, then(PROC_REF(thrown_reaction_sound)))
	verb_entry(/mob/verb/observe, hidden = TRUE)
	verb_entry(/mob/living/simple_mob/proc/animal_nom, when = nameof(vore_active)) // useable before the vorgans initialise
	verb_entry(/mob/living/proc/shred_limb, when = nameof(vore_active))
	op("nutrition_heal", menu(button = "Nutrition Heal"), needs(req(PROC_REF(hungry_enough_to_heal), because = PROC_REF(too_hungry_to_heal_text))),
		asks(/datum/prompt/number/animal_nutrition_heal, fields = list("question" = computed(PROC_REF(nutrition_heal_question))), ends_on_no = TRUE, step = "amount"),
		wait(PROC_REF(nutrition_heal_time)), then(PROC_REF(nutrition_heal_done)))
	verb_entry(/mob/living/simple_mob/proc/use_headset) // TGPanel
	verb_entry(/mob/living/simple_mob/proc/use_pda) // TGPanel
	verb_entry(/mob/living/simple_mob/proc/pick_size, login = TRUE)
	verb_entry(/mob/living/simple_mob/proc/pick_color, login = TRUE)
	verb_entry(/mob/living/simple_mob/proc/set_name, login = TRUE)
	verb_entry(/mob/living/simple_mob/proc/set_desc, login = TRUE)
	verb_entry(/mob/living/simple_mob/proc/set_gender, login = TRUE)
	// a ghost becomes a ghost-joinable mob after a yes (the old attack_ghost; a mob nobody may join is not offered)
	op("ghost_join", observer(), label("Inhabit"), when(nameof(ghostjoin)), needs(req(PROC_REF(can_ghost_join), because = PROC_REF(ghost_join_reason))),
		asks(/datum/prompt/yes_no, fields = list("title" = "Become Mob", "question" = computed(PROC_REF(ghost_join_question)), "timeout" = 20 SECONDS), keeps = TARGET_PRESENT),
		then(PROC_REF(reply_ghost_join)))

// Verbs every simple mob has, or doesn't, by what it is (code/datums/om/grant_verbs.dm).

/mob/living/simple_mob/Initialize(mapload)
	// Per-subtype constant tables: share one list across every instance of
	// this type instead of allocating a fresh copy per mob. attacktext can
	// be a single string on some subtypes, so only intern the list form;
	// subtypes that mutate their attacktext list (e.g. synx) copy it first.
	if(islist(attacktext))
		attacktext = shared_type_list(type, "attacktext", attacktext)
	if(islist(friendly))
		friendly = shared_type_list(type, "friendly", friendly)
	if(islist(loot_list))
		loot_list = shared_type_list(type, "loot_list", loot_list)
	if(islist(myid_access))
		myid_access = shared_type_list(type, "myid_access", myid_access)

	if(ID_provided)
		rel_set(src, nameof(myid), new /obj/item/card/id(src)) // ALLOW(decl): conditional on ID_provided
		myid.access = myid_access ? myid_access.Copy() : list()

	for(var/L in has_langs)
		languages |= GLOB.all_languages[L]
	if(languages.len)
		default_language = languages[1]

	if(!icon_living) // Prevent the mob from turning invisible if icon_living is null.
		set_icon_living(initial(icon_state))

	if(organ_names)
		organ_names = GET_DECL(organ_names)

	if(CONFIG_GET(flag/allow_simple_mob_recolor))
		grant(src, granted_verb(/mob/living/simple_mob/proc/ColorMate), verb_source(VERB_SOURCE_CONFIG))

	enable_footsteps(FOOTSTEP_MOB_SHOE, 1, -6) // Need to go through all of the mobs to give them proper footsteps...

	return ..()


// eye glow comes off and belly contents are released.
/mob/living/simple_mob/on_destroy(force)
	release_vore_contents()
	..()

//Client attached

/mob/living/simple_mob/Login()
	. = ..()
	to_chat(src,span_boldnotice("You are \the [src].") + " [player_msg]")
	if(vore_active && !voremob_loaded)
		init_vore(TRUE)
	if(hasthermals)
		grant(src, granted_verb(/mob/living/simple_mob/proc/hunting_vision), src) //So that maint preds can see prey through walls, to make it easier to find them.

/mob/living/simple_mob/proc/pick_size()
	set name = "Pick Size"
	set category = VERB_CAT_ABILITIES_SETTINGS

	if(picked_size)
		to_chat(src, span_notice("You have already picked a size! If you picked the wrong size, ask an admin to change your picked_size variable to 0."))
		return
	if(!resizable)
		to_chat(src, span_warning("You are immune to resizing!"))
		return

	var/nagmessage = "Pick a size between [RESIZE_MINIMUM * 100] to [RESIZE_MAXIMUM * 100]%. (Only usable once!)"
	open_request(src, /datum/prompt/number, PROC_REF(size_picked), answerer = src, title = "Pick a Size", question = nagmessage, default = size_multiplier*100, max_value = RESIZE_MAXIMUM * 100, min_value = RESIZE_MINIMUM * 100, timeout = 0)

/mob/living/simple_mob/proc/size_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/new_size = A.answer.value
	if(!picked_size && size_range_check(new_size))
		resize(new_size/100, uncapped = has_large_resize_bounds(), ignore_prefs = TRUE)
		picked_size = TRUE

/mob/living/simple_mob/proc/pick_color()
	set name = "Pick Color"
	set category = VERB_CAT_ABILITIES_SETTINGS
	set desc = "You can set your color!"
	if(picked_color)
		to_chat(src, span_notice("You have already picked a color! If you picked the wrong color, ask an admin to change your picked_color variable to 0."))
		return
	open_request(src, /datum/prompt/color, PROC_REF(color_picked), answerer = usr, question = "Choose a color.", default = color, timeout = 0)

/mob/living/simple_mob/proc/color_picked(datum/act/request/A)
	if(!A.answer)
		return
	if(!picked_color)
		color = A.answer.value
	picked_color = TRUE

/mob/living/simple_mob/SelfMove(turf/n, direct, movetime)
	var/turf/old_turf = get_turf(src)
	var/old_dir = dir
	. = ..()
	if(. && movement_shake_radius)
		for(var/mob/living/L in range(movement_shake_radius, src))
			shake_camera(L, 1, 1)
	if(turn_sound && dir != old_dir)
		playsound(src, turn_sound, 50, 1)
	else if(movement_sound && old_turf != get_turf(src)) // Playing both sounds at the same time generally sounds bad.
		playsound(src, movement_sound, 50, 1)
/*
/mob/living/simple_mob/set_dir(new_dir)
	if(dir != new_dir)
		playsound(src, turn_sound, 50, 1)
	return ..()
*/
/mob/living/simple_mob/movement_delay()
	. = movement_cooldown

	if(force_max_speed)
		return -3

	if(factor(BF_HASTE))
		return -3
	. += factor(BF_SLOWDOWN)
	var/penalty_scale = factor(BF_PENALTY_SCALE)
	if(penalty_scale != 1 && . > movement_cooldown)
		. = movement_cooldown + (. - movement_cooldown) * penalty_scale

	// Turf related slowdown
	var/turf/T = get_turf(src)
	if(T && T.movement_cost && !(dq_get_hovering(src) || flying || is_incorporeal())) // Flying mobs ignore turf-based slowdown. Aquatic mobs ignore water slowdown, and can gain bonus speed in it.
		if(istype(T,/turf/simulated/floor/water) && aquatic_movement)
			. -= aquatic_movement - 1
		else
			. += T.movement_cost
		if(flying)
			adjust_nutrition(-0.5)

	if(purge)//Purged creatures will move more slowly. The more time before their purge stops, the slower they'll move.
		if(. <= 0)
			. = 1
		. *= purge

	if(m_intent == I_WALK)
		. *= 1.5

	if(injury_enrages) // If we enrage, then do this, else
		. -= injury_level
	else
		. += injury_level
	// Stop

	. += CONFIG_GET(number/animal_delay)

	. += ..()

/mob/living/simple_mob/get_status_tab_items()
	. = ..()
	. += ""
	. += "Health: [round(vitality() * 100)]%"

/mob/living/simple_mob/proc/chase_target(ticker)
	if(QDELETED(movement_target))
		rel_clear(src, nameof(movement_target))
		return

	if(ticker < 10 && (get_dist(src, movement_target) > 1)) //We only chase our target for 10 tiles or until we are next to them.
		step_to(src,movement_target,1)
		after(src, 0.3 SECONDS, PROC_REF(chase_target), with = list(++ticker))
		return

	face_atom(movement_target)

	if(isturf(movement_target.loc))
		UnarmedAttack(movement_target, TRUE, I_HELP)
	else if(ishuman(movement_target.loc) && prob(20))
		visible_emote("stares at the [movement_target] that [movement_target.loc] has with an unknowable gaze.")
	rel_clear(src, nameof(movement_target))

/mob/living/simple_mob/say_quote(message, datum/language/speaking = null)
	if(speak_emote.len)
		. = pick(speak_emote)
	else if(speaking)
		. = ..()

/mob/living/simple_mob/get_speech_ending(verb, ending)
	return verb

/mob/living/simple_mob/is_sentient()
	return mob_class & (MOB_CLASS_HUMANOID|MOB_CLASS_ANIMAL|MOB_CLASS_SLIME) // Update this if needed.

/mob/living/simple_mob/get_nametag_desc(mob/user)
	return span_italics("[tt_desc]")

/mob/living/simple_mob/make_hud_overlays()
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.buildmode_hud, src, "ai_0", plane = PLANE_BUILDMODE), STATUS_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.buildmode_hud, src, "ais_1", plane = PLANE_BUILDMODE), LIFE_HUD)
	add_overlay(hud_list)

//Makes it so that simplemobs can understand galcomm without being able to speak it.
/mob/living/simple_mob/say_understands(mob/other, datum/language/speaking = null)
	if(understands_common && (speaking?.name == LANGUAGE_GALCOM || !speaking))
		return TRUE
	return ..()

/datum/decl/mob_organ_names
//When in doubt, it's probably got a body.
TYPE_TABLE_DECLARE(/datum/decl/mob_organ_names, mob_organ_hit_zones, list("body"))

/*
 * How injured are we? Returns a number that is then added to movement cooldown and firing/melee delay respectively.
 * Called by movement_delay and our firing/melee delay checks
*/
/mob/living/simple_mob/proc/get_injury_level(mob/living/simple_mob/M)
	var/h = vitality() // 0..1 wellness left (pain-free: simple bodies don't feel pain)
	if(h > 0) 												// Safety: nothing to compute for a dead/zeroed body
		if(h <= threshold) 									// Did our health go below our threshold %?
			var/totaldelay = round(rand(1,3) * damage_fatigue_mult * clamp(((rand(2,5) * h) - rand(0,2)), 1, 5)) 	// totaldelay is how much delay we're going to feed into attacks and movement. Do NOT change this formula unless you know how to math.
			injury_level = totaldelay 						// Adds our returned slowdown to the mob's injury level
		else												// Healed back over our threshold percentage: reset
			injury_level = 0								// Reset to no slowdown

/mob/living/simple_mob/proc/ColorMate()
	set name = "Recolour"
	set category = VERB_CAT_ABILITIES_SETTINGS
	set desc = "Allows to recolour once."

	if(has_recoloured)
		to_chat(src, "You've already recoloured yourself once. You are only allowed to recolour yourself once during a around.")
		return

	// The window paints us in place (and sets has_recoloured); there's no answer to act on.
	open_request(src, /datum/prompt/colormatrix, null, answerer = src, title = "Animal Recolor", question = "Allows you to recolor yourself", preview = src, ui_state = GLOB.tgui_conscious_state)

//Thermal vision adding

/mob/living/simple_mob/proc/hunting_vision()
	set name = "Track Prey Through Walls"
	set category = VERB_CAT_ABILITIES_MOB
	set desc = "Uses you natural predatory instincts to seek out prey even through walls, or your natural survival instincts to spot predators from a distance."

	if(COOLDOWN_FINISHED(src, hunting_cooldown))
		to_chat(src, "You can sense other creatures by focusing carefully on your surroundings.")
		sight |= SEE_MOBS
		COOLDOWN_START(src, hunting_cooldown, 5 MINUTES)
		after(src, 1 MINUTE, PROC_REF(hunting_vision_ends))
	else if(COOLDOWN_TIMELEFT(src, hunting_cooldown))
		to_chat(src, "You must wait for a while before using this again.")

/mob/living/simple_mob/proc/hunting_vision_plus()
	set name = "Thermal vision toggle"
	set category = VERB_CAT_ABILITIES_MOB
	set desc = "Uses you natural predatory instincts to seek out prey even through walls, or your natural survival instincts to spot predators from a distance."

	if(!isthermal)
		to_chat(src, "You can sense other creatures by focusing carefully on your surroundings.")
		sight |= SEE_MOBS
	else
		to_chat(src, "You stop sensing creatures beyond the walls.")
		sight -= SEE_MOBS

/mob/living/simple_mob/proc/character_directory_species()
	return "simplemob"

/mob/living/simple_mob/verb/toggle_vore_icons()

	set name = "Toggle Vore Sprite"
	set desc = "Toggle visibility of changed mob sprite when you have eaten other things."
	set category = VERB_CAT_ABILITIES_VORE

	if(!vore_icons && !vore_icons_cache)
		to_chat(src,span_warning("This simplemob has no vore sprite."))
	else if(isnull(vore_icons_cache))
		vore_icons_cache = vore_icons
		set_vore_icons(0)
		to_chat(src,span_warning("Vore sprite disabled."))
	else
		set_vore_icons(vore_icons_cache)
		vore_icons_cache = null
		to_chat(src,span_warning("Vore sprite enabled."))

/// Simple mob slip logic, should be overriden if you want the simple mob to slip under certain conditions
/mob/living/simple_mob/proc/animal_slip(wet_level, dirtslip)
	return FALSE

// === merged from simple_mob_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob
	melee_attack_delay = 1
	base_attack_cooldown = 10
	melee_miss_chance = 25

	var/temperature_range = 40			// How close will they get to environmental temperature before their body stops changing its heat

	var/vore_active = 0					// If vore behavior is enabled for this mob

	vore_capacity = 1					// The capacity (in people) this person can hold
	var/vore_max_size = RESIZE_HUGE		// The max size this mob will consider eating
	var/vore_min_size = RESIZE_TINY 	// The min size this mob will consider eating
	var/vore_bump_chance = 0			// Chance of trying to eat anyone that bumps into them, regardless of hostility
	var/vore_bump_emote	= "grabs hold of"				// Allow messages for bumpnom mobs to have a flavorful bumpnom
	var/vore_pounce_chance = 5			// Chance of this mob knocking down an opponent
	EXPIRY_DECLARE(vore_pounce_cooldown) // Cooldown timer - if it fails a pounce it won't pounce again for a while
	var/vore_pounce_successrate	= 100	// Chance of a pounce succeeding against a theoretical 0-health opponent
	var/vore_pounce_falloff = 1			// Success rate falloff per %health of target mob.
	var/vore_pounce_maxhealth = 80		// Mob will not attempt to pounce targets above this %health
	var/vore_standing_too = 0			// Can also eat non-stunned mobs
	var/vore_ignores_undigestable = FALSE	// If set to true, will refuse to eat mobs who are undigestable by the prefs toggle.
	var/swallowsound = null				// What noise plays when you succeed in eating the mob.

	var/vore_default_mode = DM_DIGEST	// Default bellymode (DM_DIGEST, DM_HOLD, DM_ABSORB)
	var/vore_default_flags = 0			// No flags
	var/vore_digest_chance = 25			// Chance to switch to digest mode if resisted
	var/vore_absorb_chance = 0			// Chance to switch to absorb mode if resisted
	var/vore_escape_chance = 25			// Chance of resisting out of mob
	var/vore_escape_chance_absorbed = 20// Chance of absorbed prey finishing an escape. Requires a successful escape roll against the above as well.

	var/vore_stomach_name				// The name for the first belly if not "stomach"
	var/vore_stomach_flavor				// The flavortext for the first belly if not the default

	var/vore_default_item_mode = IM_DIGEST_FOOD			//How belly will interact with items
	var/vore_default_contaminates = TRUE // Will it contaminate? // Put back to true like it always was.
	var/vore_default_contamination_flavor = "Generic"	//Contamination descriptors
	var/vore_default_contamination_color = "green"		//Contamination color

	var/life_disabled = 0				// For performance reasons

	var/vore_attack_override = FALSE	// Enable on mobs you want to have special behaviour on melee grab attack.

	var/mount_offset_x = 5				// Horizontal riding offset.
	var/mount_offset_y = 8				// Vertical riding offset

	var/obj/item/radio/headset/mob_radio		//Adminbus headset for simplemob shenanigans.
	does_spin = FALSE
	can_be_drop_pred = TRUE				// Mobs are pred by default.
	can_be_drop_prey = TRUE
	var/damage_threshold  = 0 //For some mobs, they have a damage threshold required to deal damage to them.

	var/nom_mob = FALSE //If a mob is meant to be hostile for vore purposes but is otherwise not hostile, if true makes certain AI ignore the mob

	var/voremob_loaded = FALSE // On-demand belly loading.

//For all those ID-having mobs
/mob/living/simple_mob/GetIdCard()
	if(get_active_hand())
		var/obj/item/I = get_active_hand()
		var/id = I.GetID()
		if(id)
			return id
	if(myid)
		return myid

/mob/living/simple_mob/proc/will_eat(mob/living/M)
	if(client) //You do this yourself, dick!
		// ai_log("vr/wont eat [M] because we're player-controlled", 3) // AI TEMPORARY REMOVAL
		return 0
	if(!istype(M)) //Can't eat 'em if they ain't /mob/living
		// ai_log("vr/wont eat [M] because they are not /mob/living", 3) // AI TEMPORARY REMOVAL
		return 0
	if(src == M) //Don't eat YOURSELF dork
		// ai_log("vr/won't eat [M] because it's me!", 3) // AI TEMPORARY REMOVAL
		return 0
	if(M.is_incorporeal()) // No eating the phased ones
		return 0
	if(vore_ignores_undigestable && !M.digestable) //Don't eat people with nogurgle prefs
		// ai_log("vr/wont eat [M] because I am picky", 3) // AI TEMPORARY REMOVAL
		return 0
	if(!M.allowmobvore || !M.devourable) // Don't eat people who don't want to be ate by mobs
		// ai_log("vr/wont eat [M] because they don't allow mob vore", 3) // AI TEMPORARY REMOVAL
		return 0
	if(LAZYFIND(prey_excludes, M)) // They're excluded
		// ai_log("vr/wont eat [M] because they are excluded", 3) // AI TEMPORARY REMOVAL
		return 0
	if(M.size_multiplier < vore_min_size || M.size_multiplier > vore_max_size)
		// ai_log("vr/wont eat [M] because they too small or too big", 3) // AI TEMPORARY REMOVAL
		return 0
	if(vore_capacity != 0 && (vore_fullness >= vore_capacity)) // We're too full to fit them
		// ai_log("vr/wont eat [M] because I am too full", 3) // AI TEMPORARY REMOVAL
		return 0
	return 1

/mob/living/simple_mob/apply_attack(atom/A, damage_to_do, stance = I_HURT)
	if(isliving(A)) // Converts target to living
		var/mob/living/L = A

		//ai_log("vr/do_attack() [L]", 3)
		// If we're not hungry, call the sideways "parent" to do normal punching
		if(!vore_active)
			return ..()

		// If target is standing we might pounce and knock them down instead of attacking
		var/pouncechance = CanPounceTarget(L)
		if(pouncechance)
			return PounceTarget(L, pouncechance)

		// We're not attempting a pounce, if they're down or we can eat standing, do it as long as they're edible. Otherwise, hit normally.
		if(will_eat(L) && (L.lying || vore_standing_too))
			return EatTarget(L)
		else
			return ..()
	else
		return ..()

/mob/living/simple_mob/proc/CanPounceTarget(mob/living/M) //returns either FALSE or a %chance of success
	if(!M.canmove || issilicon(M) || !COOLDOWN_FINISHED(src, vore_pounce_cooldown)) //eliminate situations where pouncing CANNOT happen
		return FALSE
	if(M.is_incorporeal())
		return FALSE
	if(!prob(vore_pounce_chance) || !will_eat(M)) //mob doesn't want to pounce
		return FALSE
	if(vore_standing_too) //100% chance of hitting people we can eat on the spot
		return 100
	var/TargetHealthPercent = M.vitality() * 100 //now we start looking at the target itself
	if (TargetHealthPercent > vore_pounce_maxhealth) //target is too healthy to pounce
		return FALSE
	else
		return max(0,(vore_pounce_successrate - (vore_pounce_falloff * TargetHealthPercent)))

/mob/living/simple_mob/proc/PounceTarget(mob/living/M, successrate = 100)
	COOLDOWN_START(src, vore_pounce_cooldown, 20 SECONDS) // don't attempt another pounce for a while
	if(prob(successrate)) // pounce success!
		M.status_at_least(STAT_WEAKENED, 5)
		M.status_adjust(STAT_STUNNED, 2)
		act_message(src, M, null, MSG_OTHERS(span_danger("%U% pounces on %T%!")))
	else // pounce misses!
		act_message(src, M, null, MSG_OTHERS(span_danger("%U% attempts to pounce %T% but misses!")))
		play_sfx(src, SFX_WEAPONS_PUNCHMISS)

	if(will_eat(M) && (M.lying || vore_standing_too)) //if they're edible then eat them too
		return EatTarget(M)
	else
		return //just leave them

// Attempt to eat target
// TODO - Review this.  Could be some issues here
/mob/living/simple_mob/proc/EatTarget(mob/living/M)
	// ai_log("vr/EatTarget() [M]",2) // AI TEMPORARY REMOVAL
	// stop_automated_movement = 1 // AI TEMPORARY REMOVAL
	var/old_target = M
	ai_busy_begin() // AI TEMPORARY EDIT
	. = animal_nom(M)
	playsound(src, swallowsound, 50, 1)

	if(.)
		// If we succesfully ate them, lose the target
		ai_busy_end() // lose_target(M) //Unsure what to put here. Replaced with set_AI_busy(1) // AI TEMPORARY EDIT
		return old_target
	else if(old_target == M)
		// If we didn't but they are still our target, go back to attack.
		// but don't run the handler immediately, wait until next tick
		// Otherwise we'll be in a possibly infinate loop
		ai_busy_end() // AI TEMPORARY EDIT
	// stop_automated_movement = 0 // AI TEMPORARY EDIT

// Make sure you don't call ..() on this one, otherwise you duplicate work.
/mob/living/simple_mob/init_vore(force)
	if(force)
		vore_active = TRUE
		voremob_loaded = TRUE
	if(!vore_active || no_vore || !voremob_loaded)
		return

	enable_slosh() // Sloshy element

	if(!soulgem)
		rel_set(src, nameof(soulgem), new /obj/soulgem(src))

	// Since they have bellies, add verbs to toggle settings on them.
	grant(src, granted_verb(/mob/living/simple_mob/proc/toggle_digestion), src)
	grant(src, granted_verb(/mob/living/simple_mob/proc/toggle_fancygurgle), src)
	grant(src, granted_verb(/mob/living/proc/vertical_nom), src)
	grant(src, granted_verb(/mob/living/simple_mob/proc/animal_nom), src)
	grant(src, granted_verb(/mob/living/proc/shred_limb), src)
	grant(src, granted_verb(/mob/living/proc/eat_trash), src)
	grant(src, granted_verb(/mob/living/proc/toggle_trash_catching), src)

	if(LAZYLEN(vore_organs))
		return

	can_be_drop_pred = TRUE // Mobs will eat anyone that decides to drop/slip into them by default.
	load_default_bellies()

/mob/living/simple_mob/proc/load_default_bellies()
	//A much more detailed version of the default /living implementation
	var/obj/belly/B = new /obj/belly(src)
	rel_set(src, nameof(vore_selected), B)
	B.immutable = 1
	B.affects_vore_sprites = TRUE
	B.name = vore_stomach_name ? vore_stomach_name : "stomach"
	B.desc = vore_stomach_flavor ? vore_stomach_flavor : "Your surroundings are warm, soft, and slimy. Makes sense, considering you're inside \the [name]."
	B.digest_mode = vore_default_mode
	B.mode_flags = vore_default_flags
	B.item_digest_mode = vore_default_item_mode
	B.contaminates = vore_default_contaminates
	B.contamination_flavor = vore_default_contamination_flavor
	B.contamination_color = vore_default_contamination_color
	B.escapable = vore_escape_chance > 0 ? B_ESCAPABLE_DEFAULT : B_ESCAPABLE_NONE
	B.escapechance = vore_escape_chance
	B.escapechance_absorbed = vore_escape_chance_absorbed
	B.digestchance = vore_digest_chance
	B.absorbchance = vore_absorb_chance
	B.human_prey_swallow_time = swallowTime
	B.nonhuman_prey_swallow_time = swallowTime
	B.vore_verb = "swallow"
	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list( // We need more that aren't repetitive. I suck at endo. -Ace
		"The insides knead at you gently for a moment.",
		"The guts glorp wetly around you as some air shifts.",
		"The predator takes a deep breath and sighs, shifting you somewhat.",
		"The stomach squeezes you tight for a moment, then relaxes harmlessly.",
		"The predator's calm breathing and thumping heartbeat pulses around you.",
		"The warm walls kneads harmlessly against you.",
		"The liquids churn around you, though there doesn't seem to be much effect.",
		"The sound of bodily movements drown out everything for a moment.",
		"The predator's movements gently force you into a different position.")
	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"The burning acids eat away at your form.",
		"The muscular stomach flesh grinds harshly against you.",
		"The caustic air stings your chest when you try to breathe.",
		"The slimy guts squeeze inward to help the digestive juices soften you up.",
		"The onslaught against your body doesn't seem to be letting up; you're food now.",
		"The predator's body ripples and crushes against you as digestive enzymes pull you apart.",
		"The juices pooling beneath you sizzle against your sore skin.",
		"The churning walls slowly pulverize you into meaty nutrients.",
		"The stomach glorps and gurgles as it tries to work you into slop.")
	can_be_drop_pred = TRUE // Mobs will eat anyone that decides to drop/slip into them by default.
	B.belly_fullscreen = "a_tumby"
	B.belly_fullscreen_color = "#823232"
	B.belly_fullscreen_color2 = "#823232"

/mob/living/simple_mob/Bumped(atom/movable/AM, yes)
	if(tryBumpNom(AM))
		return
	..()

/mob/living/simple_mob/proc/tryBumpNom(mob/tmob)
	//returns TRUE if we actually start an attempt to bumpnom, FALSE if checks fail or the random bump nom chance fails
	if(istype(tmob) && will_eat(tmob) && !istype(tmob, type) && prob(vore_bump_chance) && !ckey) //check if they decide to eat. Includes sanity check to prevent cannibalism.
		if(!faction_bump_vore && faction == tmob.faction)
			return FALSE
		if(tmob.canmove && prob(vore_pounce_chance)) //if they'd pounce for other noms, pounce for these too, otherwise still try and eat them if they hold still
			tmob.status_at_least(STAT_WEAKENED, 5)
		act_message(src, tmob, null, MSG_OTHERS(span_danger("%U% [vore_bump_emote] %T%!")))
		ai_busy_begin()
		spawn() // ALLOW(scheduler): animal_nom() sleeps in do_after(); no timer or task form can wait on it until ops land (wait())
			animal_nom(tmob)
			// The nom took seconds: the pred may have been deleted (or died into a belly) meanwhile.
			if(QDELETED(src))
				return
			ai_busy_end()
		return TRUE
	return FALSE

// Checks to see if mob doesn't like this kind of turf
/mob/living/simple_mob/IMove(turf/newloc, safety = TRUE)
	if(istype(newloc,/turf/unsimulated/floor/sky))
		return MOVEMENT_FAILED //Mobs aren't that stupid, probably
	return ..() // Procede as normal.

// Riding
/datum/riding/simple_mob
	keytype = /obj/item/material/twohanded/riding_crop // Crack!
	nonhuman_key_exemption = FALSE	// If true, nonhumans who can't hold keys don't need them, like borgs and simplemobs.
	key_name = "a riding crop"		// What the 'keys' for the thing being rided on would be called.
	only_one_driver = TRUE			// If true, only the person in 'front' (first on list of riding mobs) can drive.

/datum/riding/simple_mob/handle_vehicle_layer()
	ridden().restore_initial_layer()

/datum/riding/simple_mob/ride_check(mob/living/M)
	var/mob/living/L = ridden()
	if(L.stat)
		force_dismount(M)
		return FALSE
	return TRUE

/datum/riding/simple_mob/force_dismount(mob/M)
	. =..()
	ridden().visible_message(span_notice("[M] stops riding [ridden()]!"))

/datum/riding/simple_mob/get_offsets(pass_index) // list(dir = x, y, layer)
	var/mob/living/simple_mob/L = ridden()
	var/scale = L.size_multiplier
	var/scale_difference = (L.size_multiplier - rider_size) * 10

	var/list/values = list(
		"[NORTH]" = list(0, L.mount_offset_y*scale + scale_difference, ABOVE_MOB_LAYER),
		"[SOUTH]" = list(0, L.mount_offset_y*scale + scale_difference, BELOW_MOB_LAYER),
		"[EAST]" = list(-L.mount_offset_x*scale, L.mount_offset_y*scale + scale_difference, ABOVE_MOB_LAYER),
		"[WEST]" = list(L.mount_offset_x*scale, L.mount_offset_y*scale + scale_difference, ABOVE_MOB_LAYER))

	return values

/mob/living/simple_mob/buckle_mob(mob/living/M, forced = FALSE, check_loc = TRUE)
	if(forced)
		return ..() // Skip our checks
	if(!riding_datum)
		return FALSE
	if(lying)
		return FALSE
	if(!ishuman(M))
		return FALSE
	if(M in src?.buckled_mob_list())
		return FALSE
	if(M.size_multiplier > size_multiplier * 1.2)
		to_chat(src,span_warning("This isn't a pony show! You need to be bigger for them to ride."))
		return FALSE

	var/mob/living/carbon/human/H = M

	if(H.loc != src.loc)
		if(H.Adjacent(src))
			H.forceMove(get_turf(src))

	. = ..()
	if(.)
		riding_datum.rider_size = H.size_multiplier
		src?.buckled_mob_list()[H] = "riding"

/mob/living/simple_mob/unarmed_touch(mob/living/user, stance = I_HELP)
	if(riding_datum && LAZYLEN(src?.buckled_mob_list()))
		//We're getting off!
		if(user in src?.buckled_mob_list())
			riding_datum.force_dismount(user)
		//We're kicking everyone off!
		if(user == src)
			for(var/rider in src?.buckled_mob_list())
				riding_datum.force_dismount(rider)
	else
		. = ..()

/mob/living/simple_mob/proc/animal_mount(mob/living/M in living_mobs(1))
	set name = "Animal Mount/Dismount"
	set category = VERB_CAT_ABILITIES_MOB
	set desc = "Let people ride on you."

	if(LAZYLEN(src?.buckled_mob_list()))
		for(var/rider in src?.buckled_mob_list())
			riding_datum.force_dismount(rider)
		return
	if (stat != CONSCIOUS)
		return
	if(!can_buckle || !istype(M) || !M.Adjacent(src) || M?.buckled_to())
		return
	if(buckle_mob(M))
		visible_message(span_notice("[M] starts riding [name]!"))

/mob/living/simple_mob/handle_message_mode(message_mode, message, verb, used_radios, speaking, alt_name)
	if(message_mode)
		if(message_mode == "intercom")
			for(var/obj/item/radio/intercom/I in view(1, null))
				I.talk_into(src,message,message_mode,verb,speaking)
				used_radios += I
		if(message_mode == "headset")
			if(mob_radio && istype(mob_radio,/obj/item/radio/headset))
				mob_radio.talk_into(src,message,message_mode,verb,speaking)
				used_radios += mob_radio
		else
			if(mob_radio && istype(mob_radio,/obj/item/radio/headset))
				if(mob_radio.channels[message_mode])
					mob_radio.talk_into(src,message,message_mode,verb,speaking)
					used_radios += mob_radio
	else
		..()

/mob/living/simple_mob/proc/leap()
	set name = "Pounce Target"
	set category = VERB_CAT_ABILITIES_MOB
	set desc = "Select a target to pounce at."

	if(!COOLDOWN_FINISHED(src, last_special))
		to_chat(src, "Your legs need some more rest.")
		return

	if(incapacitated(INCAPACITATION_DISABLED))
		to_chat(src, "You cannot leap in your current state.")
		return

	var/list/choices = list()
	for(var/mob/living/M in view(3,src))
		choices += M
	choices -= src

	open_request(src, /datum/prompt/choice, PROC_REF(leap_target_chosen), answerer = src, title = "Target Choice", question = "Who do you wish to leap at?", choices = choices, ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/simple_mob/proc/leap_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/T = A.answer.value

	if(get_dist(get_turf(T), get_turf(src)) > 3) return

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	if(incapacitated(INCAPACITATION_DISABLED))
		to_chat(src, "You cannot leap in your current state.")
		return

	COOLDOWN_START(src, last_special, 1 SECOND)
	set_status_flags(status_flags | LEAPING)
	pixel_y = pixel_y + 10

	act_message(src, T, null, MSG_OTHERS(span_danger("%U% leaps at %T%!")))
	throw_at(get_step(get_turf(T),get_turf(src)), 4, 1, src)
	play_sfx(src, SFX_EFFECTS_BODYFALL1)
	pixel_y = default_pixel_y
	after(src, 0.5 SECONDS, PROC_REF(leap_land), with = list(T), keeps_dead = TRUE)

/mob/living/simple_mob/proc/leap_land(mob/living/T)
	if(status_flags & LEAPING) set_status_flags(status_flags & ~LEAPING)

	if(!T || !Adjacent(T))
		to_chat(src, span_warning("You miss!"))
		return

	if(ishuman(T))
		var/mob/living/carbon/human/H = T
		if(H.species.lightweight == 1)
			H.status_at_least(STAT_WEAKENED, 3)
			return
	var/armor_block = T.armor_against(INJURY_PAIN)
	T.injure(INJURY_PAIN, 20, null, src, flags = INJURE_ARMORED)
	if(prob(75))
		T.apply_effect(3, WEAKEN, armor_block)

// === merged from simple_mob_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
/mob/living/simple_mob
	//speech sounds
	var/list/speech_sounds = list() // ALLOW(instance_list): d: per-mob speech_sounds, sized at creation and filled in place; mobs are few
	var/speech_chance = 75 //mobs can be a bit more emotive than carbon/humans
	var/speech_sound_enabled = TRUE

	//spitting projectiles
	var/spitting = 0
	var/spit_projectile = null // what our spit projectile is. Can be anything

	//no stripping of simplemobs
	strip_pref = FALSE

/mob/living/simple_mob/RangedAttack(atom/A)
	if(!isnull(spit_projectile) && spitting)
		Spit(A)
	. = ..()

/mob/living/simple_mob/verb/toggle_speech_sounds()
	set name = "Toggle Species Speech Sounds"
	set desc = "Toggle if your species defined speech sound has a chance of playing on a Say"
	set category = VERB_CAT_IC_MOB

	if(stat)
		to_chat(src, span_warning("You must be awake and standing to perform this action!"))
		return

	speech_sound_enabled = !speech_sound_enabled
	to_chat(src, "You will [speech_sound_enabled ? "now" : "no longer"] have a chance to play your species defined speech sound on a Say.")

	return TRUE

/mob/living/simple_mob/handle_speech_sound()
	if(speech_sound_enabled && speech_sounds && speech_sounds.len && prob(speech_chance))
		var/list/returns[2]
		returns[1] = sound(pick(speech_sounds))
		returns[2] = 50
		return returns
	. = ..()

// a unique named update_transforms override to allow simplemobs going horizontal on lay/stun.
// This will not make the mob horizontal if the mob has a icon_rest != null
// To use this, add an override in your simplemob subtype of update_transforms with NO . = ..()
// Example:
// /mob/living/simple_mob/my_mob/update_transforms()
// 		update_transform_horizontal()

/mob/living/simple_mob/proc/update_transform_horizontal()
	// First, get the correct size.
	var/desired_scale_x = size_multiplier * icon_scale_x
	var/desired_scale_y = size_multiplier * icon_scale_y

	// Here we differ from mob/living/update_transforms()

	// Taking some data from the /carbon/human/update_transform() entry
	var/matrix/M = matrix()
	var/anim_time = 3

	// If we're wanting to lay and there is no icon_rest sprite assigned, then...
	if( ( (stat == UNCONSCIOUS) || resting || incapacitated(INCAPACITATION_DISABLED) ) && !icon_rest )

		var/randn = rand(1, 2)
		if(randn <= 1) // randomly choose a rotation
			M.Turn(-90)
		else
			M.Turn(90)
		M.Scale(desired_scale_x, desired_scale_y)
		M.Translate(1,-6)
		layer = MOB_LAYER -0.01 // Fix for a byond bug where turf entry order no longer matters
	else
		M.Scale(desired_scale_x, desired_scale_y)
		M.Translate(0, (vis_height/2)*(desired_scale_y-1))
		layer = MOB_LAYER

	// Animate instead of set. Original set left commented out
	// src.transform = M //
	animate(src, transform = M, time = anim_time)

	// This from original living.dm update_transforms too
	handle_status_indicators()

/mob/living/simple_mob/proc/use_headset()
	set name = "Use Headset"
	set desc = "Opens your headset's GUI, if you have one."
	set category = VERB_CAT_ABILITIES_MOB

	if(istype(mob_radio, /obj/item/radio/headset))
		mob_radio.tgui_interact(src)
	else
		to_chat(src, span_warning("Your mob does not have a radio in its radio slot."))

/mob/living/simple_mob/proc/use_pda()
	set name = "Use PDA"
	set desc = "Opens your PDA's GUI, if you have one."
	set category = VERB_CAT_ABILITIES_MOB

	if(istype(myid, /obj/item/pda))
		myid.tgui_interact(src)
	else
		to_chat(src, span_warning("Your mob does not have a PDA in its ID slot."))

/mob/living/simple_mob/proc/hunting_vision_ends()
	to_chat(src, "Your concentration wears off.")
	sight -= SEE_MOBS

