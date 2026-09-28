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
	// ALLOW(instance_list): mob: 15 mobs at boot; per-instance state, see audit
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
	set category = "Abilities.General"
	om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick new colors:", title = "Color", default = goia_overlays["zorgoia_main"], overlay = "zorgoia_main")

/// One of the zorgoia's overlay colours, picked after its style (if it has one). The style lands with the colour.
/datum/om/prompt/color/goia_overlay
	ask_flags = ASK_CAPABLE
	/// The goia_overlays key holding the colour ("zorgoia_ears", ...).
	var/overlay
	/// The goia_overlays key holding the style ("ears", ...); null: colour only.
	var/style_key
	/// The style picked.
	var/style

/mob/living/simple_mob/vore/zorgoia/proc/overlay_color_picked(datum/om/prompt/color/goia_overlay/ask)
	if(!ask.picked_color)
		return
	if(ask.style_key)
		goia_overlays[ask.style_key] = ask.style
	goia_overlays[ask.overlay] = ask.picked_color
	update_icon()

/mob/living/simple_mob/vore/zorgoia/proc/appearance_switch() //This is just copypastas of the radial menu code, each block of code is the options for each bit of customisation... all 9 of them
	set name = "Adjust Mob Markings"
	set desc = "Change your markings and mob colors."
	set category = "Abilities.General"

	var/list/options = list("Belly","Spike","Ears","Spots","Claws","Spines","Fluff","Underbelly","Eyes")
	for(var/option in options)
		LAZYSET(options, option, image('icons/effects/goia_labels.dmi', option))
	var/choice = show_radial_menu(src, src, options, radius = 60)
	if(!choice || QDELETED(src) || src.incapacitated())
		return FALSE
	. = TRUE
	switch(choice)

		if("Ears")
			options = ear_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = -16)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick ears spike color:", title = "Ears Color", default = goia_overlays["zorgoia_ears"], overlay = "zorgoia_ears", style_key = "ears", style = choice)

		if("Spots")
			options = spots_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = -16)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick spot colors:", title = "Spots Color", default = goia_overlays["zorgoia_spots"], overlay = "zorgoia_spots", style_key = "spots", style = choice)

		if("Claws")
			options = claws_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = -16)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick claw colors:", title = "Claws Color", default = goia_overlays["zorgoia_claws"], overlay = "zorgoia_claws", style_key = "claws", style = choice)

		if("Spines")
			options = spines_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = -16)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick spines colors:", title = "Spines Color", default = goia_overlays["zorgoia_spines"], overlay = "zorgoia_spines", style_key = "spines", style = choice)

		if("Fluff")
			options = fluff_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = -16)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick fluff colors:", title = "Fluff Color", default = goia_overlays["zorgoia_fluff"], overlay = "zorgoia_fluff", style_key = "fluff", style = choice)

		if("Underbelly")
			options = underbelly_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = -16)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick underbelly colors:", title = "Underbelly Color", default = goia_overlays["zorgoia_underbelly"], overlay = "zorgoia_underbelly", style_key = "underbelly", style = choice)

		if("Eyes")
			options = eyes_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4, pixel_x = -16)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick eye color:", title = "Eye Color", default = goia_overlays["zorgoia_eyes"], overlay = "zorgoia_eyes", style_key = "eyes", style = choice)

		if("Spike")
			options = spiky_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick tail spike color:", title = "Tail Color", default = goia_overlays["zorgoia_spike"], overlay = "zorgoia_spike", style_key = "spike", style = choice) //This is overlay 10, not 2, swapped with main body, im not rewriting this array

		if("Belly")
			options = belly_styles
			for(var/option in options)
				var/image/I = image('icons/mob/zorgoia64x32.dmi', option, dir = 4)
				LAZYSET(options, option, I)
			choice = show_radial_menu(src, src, options, radius = 90)
			if(!choice || QDELETED(src) || src.incapacitated())
				return 0
			om_ask(src, /datum/om/prompt/color/goia_overlay, PROC_REF(overlay_color_picked), message = "Pick belly color:", title = "Belly Color", default = goia_overlays["zorgoia_belly"], overlay = "zorgoia_belly", style_key = "belly", style = choice)

/mob/living/simple_mob/vore/zorgoia/Initialize(mapload)
	. = ..()
	add_verb(src,/mob/living/simple_mob/vore/zorgoia/proc/appearance_switch)
	add_verb(src,/mob/living/simple_mob/vore/zorgoia/proc/recolor)
	add_verb(src,/mob/living/proc/injection) //Poison sting c:
	add_verb(src,/mob/living/simple_mob/vore/zorgoia/proc/export_style)
	add_verb(src,/mob/living/simple_mob/vore/zorgoia/proc/import_style)
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

/mob/living/simple_mob/vore/zorgoia/update_icon()
	..()
	if(stat == DEAD)
		plane = MOB_LAYER
		return
	else
		plane = ABOVE_MOB_PLANE
	cut_overlays()
	icon = 'icons/mob/zorgoia64x32.dmi'
	vore_capacity = 3
	//Heads up, the order of these overlays stacking on top of each other is different from the array order. So goia_overlay[1] is the belly, but rendering on top of everything at the end instead

	var/image/I = image(icon, "[goia_overlays["main"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_main"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["ears"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_ears"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["spots"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_spots"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["claws"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_claws"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["spines"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_spines"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)


	I = image(icon, "[goia_overlays["fluff"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_fluff"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["eyes"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_eyes"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = PLANE_LIGHTING_ABOVE
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["spike"]][resting? "-rest" : null]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_spike"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["belly"]][resting? "-rest" : (vore_fullness? "-[vore_fullness]" : null)]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_belly"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

	I = image(icon, "[goia_overlays["underbelly"]][resting? "-rest" : (vore_fullness? "-[vore_fullness]" : null)]", pixel_x = -16)
	I.color = goia_overlays["zorgoia_underbelly"]
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	I.plane = MOB_PLANE
	I.layer = MOB_LAYER
	add_overlay(I)
	qdel(I)

EXTEND_INTERACTIONS(/mob/living/simple_mob/vore/zorgoia, \
	INTERACT_HAND_UNGATED_AS(I_HELP, "Pet", PROC_REF(zorgoia_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_GRAB, "Grab", PROC_REF(zorgoia_interaction_hand)), \
)

/// Old attack_hand (ran before the gate): help pets/tames, grab is refused while alive and AI-run. FALSE = default touch.
/mob/living/simple_mob/vore/zorgoia/proc/zorgoia_interaction_hand(mob/living/carbon/human/M, obj/item/held, datum/interaction/interaction)
	switch(interaction.stance)
		if(I_HELP)
			if(stat != DEAD)
				if(M.zone_sel.selecting == BP_GROIN)
					if(M.vore_bellyrub(src))
						return TRUE
				M.visible_message(span_notice("[M] [response_help] \the [src]."))
				if(ai_brain)
					var/datum/ai_brain/AI = ai_brain
					AI.lose_target()  // sleep-style state — drop current target
					if(prob(tame_chance))
						AI.set_hostile(FALSE)
						friend = M
						AI.set_follow(friend)
						if(tamed != 1)
							tamed = 1
							faction = M.faction
			return TRUE

		if(I_GRAB)
			if(stat != DEAD)
				if((ai_brain != null))
					var/datum/ai_brain/AI = ai_brain
					audible_emote("growls disapprovingly at [M].")
					if(M == friend)
						AI.lose_follow()
						friend = null
					return TRUE
			return FALSE

	return FALSE

/mob/living/simple_mob/vore/zorgoia/Login()
	. = ..()
	if(!riding_datum)
		riding_datum = new /datum/riding/simple_mob(src)
	add_verb(src,/mob/living/simple_mob/proc/animal_mount)
	add_verb(src,/mob/living/proc/toggle_rider_reins)
	movement_cooldown = 0

/mob/living/simple_mob/vore/zorgoia/on_death(gibbed) //are they going to be ok?
	. = ..()
	cut_overlays()

/mob/living/simple_mob/vore/zorgoia/tamed
	tamed = TRUE

/mob/living/simple_mob/vore/zorgoia/proc/export_style()
	set name = "Export style string"
	set desc = "Export a string of text that can be used to instantly get the current style back using the import style verb"
	set category = "Abilities.Settings"
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
	set category = "Abilities.Settings"
	om_ask(src, /datum/om/prompt/text, PROC_REF(import_style_entered), title = "Style loading", message = "Paste the style string you exported with Export Style.", max_length = 250)

/mob/living/simple_mob/vore/zorgoia/proc/import_style_entered(datum/om/prompt/text/ask)
	var/input_style = ask.text
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

REF_HELD(/mob/living/simple_mob/vore/zorgoia, "friend")
