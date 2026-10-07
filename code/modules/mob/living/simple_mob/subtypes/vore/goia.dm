/mob/living/simple_mob/vore/zorgoia
	drag_buckle = FALSE
	name = "zorgoia"
	desc = "It's a a reptilian mammal hybrid, known for its voracious nature and love for fruits. By more popular terms its referred to as the furry slinky!"
	tt_desc = "Zorgoyuh slinkus"
	icon = 'icons/mob/zorgoia64x32.dmi'
	icon_state = null //Overlay system will make the goias
	icon_living = null
	icon_rest = null
	icon_dead = "zorgoia-death"
	faction = FACTION_ZORGOIA
	endurance = 150 //chonk
	melee_damage_lower = 5
	melee_damage_upper = 15 //Don't break my bones bro
	see_in_dark = 5
	response_help = "pets"
	response_disarm = "bops"
	response_harm = "hits"
	attacktext = list("mauled")
	friendly = list("nuzzles", "noses softly at", "noseboops", "headbumps against", "nibbles affectionately on")
	meat_amount = 5
	has_eye_glow = TRUE //(evil)

	old_x = 0
	old_y = 0
	default_pixel_x = 0
	pixel_x = 0
	pixel_y = 0

	max_buckled_mobs = 1 //Yeehaw
	can_buckle = TRUE
	buckle_movable = TRUE
	buckle_lying = FALSE
	mount_offset_y = 10

	var/mob/living/carbon/human/friend
	var/tamed = 0
	var/tame_chance = 50 //It's a fiddy-fiddy default you may get a buddy pal or you may get mauled and ate. Win-win!

	color = null //color is selected when spawned

	vore_active = 1
	vore_capacity = 3
	vore_icons = 0 //The icon system down there handles the vore belly
	vore_pounce_chance = 35
	vore_bump_chance = 25
	vore_icons = SA_ICON_LIVING | SA_ICON_REST
	vore_stomach_name = "stomach" //Might make a better vore text but have this one for now.
	vore_stomach_flavor = "You find yourself greedily gulped down into the zorgoia's stomach; the walls are surprisingly roomy in comparison to other critters of this size as their stomach makes up a majority of their long noodle shaped body. Your body contorting with the zorgoias long shape as every inch of you is tightly bound by their glowy walls."
	vore_default_contamination_flavor = "Acrid"
	vore_default_item_mode = IM_DIGEST


	can_be_drop_prey = FALSE
	allow_mind_transfer = TRUE
	species_sounds = "None"
	pain_emote_1p = list("yelp", "whine", "bark", "growl")
	pain_emote_3p = list("yelps", "whines", "barks", "growls")

	//This is copypastad from protean code, hope it isnt too painful lol
	// ALLOW(instance_list): d: per-instance colours, rolled at spawn and repainted by the player
	var/list/goia_overlays = list( //all 10 overlays, in order
		"zorgoia_belly" = "#FFFFFF",
		"zorgoia_main" = "#FFFFFF",
		"zorgoia_ears" = "#FFFFFF",
		"zorgoia_spots" = "#FFFFFF",
		"zorgoia_claws" = "#FFFFFF",
		"zorgoia_spines" = "#FFFFFF",
		"zorgoia_fluff" = "#FFFFFF",
		"zorgoia_underbelly" = "#FFFFFF",
		"zorgoia_eyes" = "#FFFFFF",
		"zorgoia_spike" = "#FFFFFF"
	)

	var/static/list/ear_styles = list(
		"null",
		"zorgoia_ears",
		"zorgoia_ears2"
	)
	var/static/list/spots_styles = list(
		"null",
		"zorgoia_spots",
		"zorgoia_stripes",
		"zorgoia_backline",
		"zorgoia_stars"
	)
	var/static/list/claws_styles = list(
		"null",
		"zorgoia_claws",
		"zorgoia_justfangs",
		"zorgoia_feetpaws"
	)
	var/static/list/spines_styles = list(
		"null",
		"zorgoia_spines",
		"zorgoia_tailfade"
	)
	var/static/list/fluff_styles = list(
		"null",
		"zorgoia_fluff",
		"zorgoia_fullhead"
	)
	var/static/list/underbelly_styles = list(
		"zorgoia_underbelly",
		"zorgoia_underbellystripe",
		"null"
	)
	var/static/list/eyes_styles = list(
		"zorgoia_eyes",
		"zorgoia_eyes2"
	)
	var/static/list/spiky_styles = list(
		"zorgoia_spike",
		"zorgoia_spike2"
	)
	var/static/list/belly_styles = list(
		"zorgoia_belly"
	)

/mob/living/simple_mob/vore/zorgoia/proc/recolor() //Base sprite wont need a radical menu selection
	set name = "Change Color"
	set desc = "Change your main color."
	set category = VERB_CAT_ABILITIES_GENERAL
	open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick new colors:", title = "Color", default = goia_overlays["zorgoia_main"], overlay = "zorgoia_main")

/// One of the zorgoia's overlay colours, picked after its style (if it has one). The style lands with the colour.
/datum/prompt/color/goia_overlay
	ask_flags = ASK_CAPABLE
	timeout = 0
	/// The goia_overlays key holding the colour ("zorgoia_ears", ...).
	var/overlay
	/// The goia_overlays key holding the style ("ears", ...); null: colour only.
	var/style_key
	/// The style picked.
	var/style

/mob/living/simple_mob/vore/zorgoia/proc/overlay_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/color/goia_overlay/ask = A.answer
	if(!ask.value)
		return
	if(ask.style_key)
		goia_overlays[ask.style_key] = ask.style
	goia_overlays[ask.overlay] = ask.value
	update_icon()

/mob/living/simple_mob/vore/zorgoia/proc/appearance_switch() //This is just copypastas of the radial menu code, each block of code is the options for each bit of customisation... all 9 of them
	set name = "Adjust Mob Markings"
	set desc = "Change your markings and mob colors."
	set category = VERB_CAT_ABILITIES_GENERAL

	var/list/options = list("Belly","Spike","Ears","Spots","Claws","Spines","Fluff","Underbelly","Eyes")
	for(var/option in options)
		LAZYSET(options, option, image('icons/effects/goia_labels.dmi', option))
	open_request(src, /datum/prompt/choice, PROC_REF(appearance_part_chosen), answerer = src, choices = options, anchor = src, radius = 60, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/// First radial answer: offer the styles of the picked part.
/mob/living/simple_mob/vore/zorgoia/proc/appearance_part_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/part = A.answer.value
	if(!part || QDELETED(src) || src.incapacitated())
		return
	var/list/options
	var/offset = -16
	switch(part)
		if("Ears")
			options = ear_styles
		if("Spots")
			options = spots_styles
		if("Claws")
			options = claws_styles
		if("Spines")
			options = spines_styles
		if("Fluff")
			options = fluff_styles
		if("Underbelly")
			options = underbelly_styles
		if("Eyes")
			options = eyes_styles
		if("Spike")
			options = spiky_styles
			offset = 0
		if("Belly")
			options = belly_styles
			offset = 0
		else
			return
	for(var/option in options)
		var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = offset)
		LAZYSET(options, option, I)
	open_request(src, /datum/prompt/choice/goia_style, PROC_REF(appearance_style_chosen), answerer = src, choices = options, anchor = src, radius = 90, part = part)

/// Second radial answer: pick the colour for the chosen style.
/datum/prompt/choice/goia_style
	radial = TRUE
	autopick_single_option = TRUE
	timeout = 0
	var/part

/mob/living/simple_mob/vore/zorgoia/proc/appearance_style_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/goia_style/ask = A.answer
	var/choice = ask.value
	if(!choice || QDELETED(src) || src.incapacitated())
		return
	switch(ask.part)
		if("Ears")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick ears spike color:", title = "Ears Color", default = goia_overlays["zorgoia_ears"], overlay = "zorgoia_ears", style_key = "ears", style = choice)
		if("Spots")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick spot colors:", title = "Spots Color", default = goia_overlays["zorgoia_spots"], overlay = "zorgoia_spots", style_key = "spots", style = choice)
		if("Claws")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick claw colors:", title = "Claws Color", default = goia_overlays["zorgoia_claws"], overlay = "zorgoia_claws", style_key = "claws", style = choice)
		if("Spines")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick spines colors:", title = "Spines Color", default = goia_overlays["zorgoia_spines"], overlay = "zorgoia_spines", style_key = "spines", style = choice)
		if("Fluff")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick fluff colors:", title = "Fluff Color", default = goia_overlays["zorgoia_fluff"], overlay = "zorgoia_fluff", style_key = "fluff", style = choice)
		if("Underbelly")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick underbelly colors:", title = "Underbelly Color", default = goia_overlays["zorgoia_underbelly"], overlay = "zorgoia_underbelly", style_key = "underbelly", style = choice)
		if("Eyes")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick eye color:", title = "Eye Color", default = goia_overlays["zorgoia_eyes"], overlay = "zorgoia_eyes", style_key = "eyes", style = choice)
		if("Spike")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick tail spike color:", title = "Tail Color", default = goia_overlays["zorgoia_spike"], overlay = "zorgoia_spike", style_key = "spike", style = choice) //This is overlay 10, not 2, swapped with main body, im not rewriting this array
		if("Belly")
			open_request(src, /datum/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), answerer = src, question = "Pick belly color:", title = "Belly Color", default = goia_overlays["zorgoia_belly"], overlay = "zorgoia_belly", style_key = "belly", style = choice)

CAPABILITIES(/mob/living/simple_mob/vore/zorgoia)
	verb_entry(/mob/living/simple_mob/vore/zorgoia/proc/appearance_switch)
	verb_entry(/mob/living/simple_mob/vore/zorgoia/proc/recolor)
	verb_entry(/mob/living/proc/injection) //Poison sting c:
	verb_entry(/mob/living/simple_mob/vore/zorgoia/proc/export_style)
	verb_entry(/mob/living/simple_mob/vore/zorgoia/proc/import_style)
	verb_entry(/mob/living/simple_mob/proc/animal_mount, login = TRUE)
	verb_entry(/mob/living/proc/toggle_rider_reins, login = TRUE)
	op("zorgoia_hand_help", hand(), ungated(), stance(I_HELP), label("Pet"), then(PROC_REF(zorgoia_interaction_hand_help)))
	op("zorgoia_hand_grab", hand(), ungated(), stance(I_GRAB), label("Grab"), then(PROC_REF(zorgoia_interaction_hand_grab)))

/// The help-stance input of zorgoia_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/vore/zorgoia/proc/zorgoia_interaction_hand_help(datum/act/op/A)
	return zorgoia_interaction_hand(A, I_HELP)

/// The grab-stance input of zorgoia_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/vore/zorgoia/proc/zorgoia_interaction_hand_grab(datum/act/op/A)
	return zorgoia_interaction_hand(A, I_GRAB)

/mob/living/simple_mob/vore/zorgoia/Initialize(mapload)
	. = ..()
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_MICROCILLIN)			// get small
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_MACROCILLIN)			// get BIG
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_NORMALCILLIN)			// normal
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_NUMBENZYME)			// no feelings
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_ANDROROVIR)			// -> MALE
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_GYNOROVIR)			// -> FEMALE
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_ANDROGYNOROVIR)		// -> PLURAL
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_STOXIN)				// night night chem
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_RAINBOWTOXIN)			// Funny flashing lights.
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_PARALYSISTOXIN) 		// Paralysis!
	LAZYADD(src.trait_injection_reagents, REAGENT_ID_PAINENZYME)			// Pain INCREASER
	// LAZYADD(src.trait_injection_reagents, REAGENT_ID_APHRODISIAC)			// Horni // Downstream only

	var/list/goia_colors = list("#1a00ff", "#6c5bff", "#ff00fe", "#ff0000", "#00d3ff", "#00ff7c", "#00ff35", "#e1ff00", "#ff9f00", "#393939")
	var/bodycolor = pick(goia_colors)
	var/spines = pick(goia_colors)
	goia_overlays["main"]= "zorgoia_main"
	goia_overlays["zorgoia_main"] = bodycolor
	goia_overlays["ears"] = pick(ear_styles)
	goia_overlays["zorgoia_ears"] = bodycolor
	goia_overlays["spots"] = pick(spots_styles)
	goia_overlays["zorgoia_spots"] = pick(goia_colors)
	goia_overlays["claws"] = pick(claws_styles)
	goia_overlays["zorgoia_claws"] = spines
	goia_overlays["spines"] = pick(spines_styles)
	goia_overlays["zorgoia_spines"] = spines
	goia_overlays["fluff"] = pick(fluff_styles)
	goia_overlays["zorgoia_fluff"] = bodycolor
	goia_overlays["underbelly"] = pick(underbelly_styles)
	goia_overlays["zorgoia_underbelly"] = bodycolor
	goia_overlays["eyes"] = pick(eyes_styles)
	goia_overlays["zorgoia_eyes"] = "#[get_random_colour(1)]"
	goia_overlays["spike"] = pick(spiky_styles)
	goia_overlays["zorgoia_spike"] = "#[get_random_colour(0,0,255)]"
	goia_overlays["belly"] = pick(belly_styles)
	goia_overlays["zorgoia_belly"] = bodycolor
	update_icon()

/// Immutable visual snapshots, bounded so arbitrary player colours cannot grow a world-long cache.
DECLARE_SHARED_CACHE_EX(zorgoia_overlay, GLOBAL_PROC_REF(build_zorgoia_overlay), SC_NEVER, 1024, 0)

/proc/cached_zorgoia_overlay(state, tint, overlay_plane, overlay_layer)
	var/key = json_encode(list(state, tint, overlay_plane, overlay_layer))
	return CACHED_KEY(zorgoia_overlay, key, state, tint, overlay_plane, overlay_layer)

/proc/build_zorgoia_overlay(state, tint, overlay_plane, overlay_layer)
	// Like iconstate2appearance(), retain one private scratch image and cache only its immutable snapshot.
	var/static/image/scratch = image('icons/mob/zorgoia64x32.dmi', pixel_x = -16)
	scratch.icon_state = state
	scratch.color = tint
	scratch.appearance_flags = RESET_COLOR|PIXEL_SCALE
	scratch.plane = overlay_plane
	scratch.layer = overlay_layer
	return scratch.appearance

DECLARE_APPEARANCE_PROC(/mob/living/simple_mob/vore/zorgoia, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/simple_mob/vore/zorgoia/appearance_overlays()
	. = list()
	. += ..()
	if(stat == DEAD)
		plane = MOB_LAYER
		return .
	else
		plane = ABOVE_MOB_PLANE
	icon = 'icons/mob/zorgoia64x32.dmi'
	vore_capacity = 3
	//Heads up, the order of these overlays stacking on top of each other is different from the array order. So goia_overlay[1] is the belly, but rendering on top of everything at the end instead

	. += cached_zorgoia_overlay("[goia_overlays["main"]][resting? "-rest" : null]", goia_overlays["zorgoia_main"], MOB_PLANE, MOB_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["ears"]][resting? "-rest" : null]", goia_overlays["zorgoia_ears"], MOB_PLANE, MOB_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["spots"]][resting? "-rest" : null]", goia_overlays["zorgoia_spots"], MOB_PLANE, MOB_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["claws"]][resting? "-rest" : null]", goia_overlays["zorgoia_claws"], MOB_PLANE, MOB_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["spines"]][resting? "-rest" : null]", goia_overlays["zorgoia_spines"], MOB_PLANE, MOB_LAYER)


	. += cached_zorgoia_overlay("[goia_overlays["fluff"]][resting? "-rest" : null]", goia_overlays["zorgoia_fluff"], MOB_PLANE, MOB_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["eyes"]][resting? "-rest" : null]", goia_overlays["zorgoia_eyes"], PLANE_LIGHTING_ABOVE, FLOAT_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["spike"]][resting? "-rest" : null]", goia_overlays["zorgoia_spike"], MOB_PLANE, MOB_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["belly"]][resting? "-rest" : (vore_fullness? "-[vore_fullness]" : null)]", goia_overlays["zorgoia_belly"], MOB_PLANE, MOB_LAYER)

	. += cached_zorgoia_overlay("[goia_overlays["underbelly"]][resting? "-rest" : (vore_fullness? "-[vore_fullness]" : null)]", goia_overlays["zorgoia_underbelly"], MOB_PLANE, MOB_LAYER)

/// Old attack_hand (ran before the gate): help pets/tames, grab is refused while alive and AI-run. FALSE = default touch.
/mob/living/simple_mob/vore/zorgoia/proc/zorgoia_interaction_hand(datum/act/op/A, stance)
	var/mob/living/carbon/human/M = A.actor
	switch(stance)
		if(I_HELP)
			if(stat != DEAD)
				if(M.zone_sel.selecting == BP_GROIN)
					if(M.vore_bellyrub(src))
						return OP_OK
				act_message(M, src, null, MSG_OTHERS(span_notice("%U% [response_help] %T%.")))
				if(ai_brain)
					var/datum/ai_brain/AI = ai_brain
					AI.lose_target()  // sleep-style state — drop current target
					if(prob(tame_chance))
						AI.set_hostile(FALSE)
						rel_set(src, nameof(friend), M)
						AI.set_follow(friend)
						if(tamed != 1)
							tamed = 1
							faction = M.faction
			return OP_OK

		if(I_GRAB)
			if(stat != DEAD)
				if((ai_brain != null))
					var/datum/ai_brain/AI = ai_brain
					audible_emote("growls disapprovingly at [M].")
					if(M == friend)
						AI.lose_follow()
						rel_clear(src, nameof(friend))
					return OP_OK
			return OP_DECLINE

	return OP_DECLINE

/mob/living/simple_mob/vore/zorgoia/Login()
	. = ..()
	if(!riding_datum)
		rel_set(src, nameof(riding_datum), new /datum/riding/simple_mob(src))
	movement_cooldown = 0

/mob/living/simple_mob/vore/zorgoia/on_death(gibbed) //are they going to be ok?
	. = ..()
	cut_overlays()

/mob/living/simple_mob/vore/zorgoia/tamed
	tamed = TRUE

/mob/living/simple_mob/vore/zorgoia/proc/export_style()
	set name = "Export style string"
	set desc = "Export a string of text that can be used to instantly get the current style back using the import style verb"
	set category = VERB_CAT_ABILITIES_SETTINGS
	var/output_style = jointext(list(
		goia_overlays["zorgoia_main"],
		goia_overlays["main"], // No alt styles for it currently
		goia_overlays["zorgoia_ears"],
		goia_overlays["ears"],
		goia_overlays["zorgoia_spots"],
		goia_overlays["spots"],
		goia_overlays["zorgoia_claws"],
		goia_overlays["claws"],
		goia_overlays["zorgoia_spines"],
		goia_overlays["spines"],
		goia_overlays["zorgoia_fluff"],
		goia_overlays["fluff"],
		goia_overlays["zorgoia_underbelly"],
		goia_overlays["underbelly"],
		goia_overlays["zorgoia_eyes"],
		goia_overlays["eyes"],
		goia_overlays["zorgoia_spike"],
		goia_overlays["spike"],
		goia_overlays["zorgoia_belly"],
		goia_overlays["belly"]), ";")
	to_chat(src, span_notice("Exported style string is \" [output_style] \". Use this to get the same style in the future with import style"))

/mob/living/simple_mob/vore/zorgoia/proc/import_style()
	set name = "Import style string"
	set desc = "Import a string of text that was made using the import style verb to get back that style"
	set category = VERB_CAT_ABILITIES_SETTINGS
	open_request(src, /datum/prompt/text, PROC_REF(import_style_entered), answerer = src, title = "Style loading", question = "Paste the style string you exported with Export Style.", max_len = 250, timeout = 0)

/mob/living/simple_mob/vore/zorgoia/proc/import_style_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/input_style = A.answer.value
	input_style = sanitizeSafe(input_style)
	if(input_style)
		var/list/input_style_list = splittext(input_style, ";")
		if((LAZYLEN(input_style_list) == 20) /* && (input_style_list[2] in main_styles) */ \
					&& (input_style_list[4] in ear_styles) && (input_style_list[6] in spots_styles) && (input_style_list[8] in claws_styles) \
					&& (input_style_list[10] in spines_styles) && (input_style_list[12] in fluff_styles) && (input_style_list[14] in underbelly_styles) \
					&& (input_style_list[16] in eyes_styles) && (input_style_list[18] in spiky_styles) &&  (input_style_list[20] in belly_styles))
			try
				if(rgb2num(input_style_list[1]))
					goia_overlays["zorgoia_main"] = input_style_list[1]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			// goia_overlays["main"] = input_style_list[2] // We only have one yet
			try
				if(rgb2num(input_style_list[3]))
					goia_overlays["zorgoia_ears"] = input_style_list[3]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["ears"] = input_style_list[4]
			try
				if(rgb2num(input_style_list[5]))
					goia_overlays["zorgoia_spots"] = input_style_list[5]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["spots"] = input_style_list[6]
			try
				if(rgb2num(input_style_list[7]))
					goia_overlays["zorgoia_claws"] = input_style_list[7]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["claws"] = input_style_list[8]
			try
				if(rgb2num(input_style_list[9]))
					goia_overlays["zorgoia_spines"] = input_style_list[9]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["spines"] = input_style_list[10]
			try
				if(rgb2num(input_style_list[11]))
					goia_overlays["zorgoia_fluff"] = input_style_list[11]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["fluff"] = input_style_list[12]
			try
				if(rgb2num(input_style_list[13]))
					goia_overlays["zorgoia_underbelly"] = input_style_list[13]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["underbelly"] = input_style_list[14]
			try
				if(rgb2num(input_style_list[15]))
					goia_overlays["zorgoia_eyes"] = input_style_list[15]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["eyes"] = input_style_list[16]
			try
				if(rgb2num(input_style_list[17]))
					goia_overlays["zorgoia_spike"] = input_style_list[17]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			input_style_list["spike"] = input_style_list[18]
			try
				if(rgb2num(input_style_list[19]))
					goia_overlays["zorgoia_belly"] = input_style_list[19]
			catch // ALLOW(silent_catch): invalid player-entered colour is ignored
			goia_overlays["belly"] = input_style_list[20]
			update_icon()

