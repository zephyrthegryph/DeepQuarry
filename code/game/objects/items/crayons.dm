/obj/item/pen/crayon/mime
	icon_state = "crayonmime"
	desc = "A very sad-looking crayon."
	colour = "#FFFFFF"
	shadeColour = "#000000"
	colourName = "mime"
	uses = 0

CAPABILITIES(/obj/item/pen/crayon/mime)
	op("invert", in_hand(), label("Invert colours"), then(PROC_REF(mime_crayon_inverted)))

/obj/item/pen/crayon/mime/proc/mime_crayon_inverted(datum/act/op/A)
	var/mob/living/user = A.actor
	if(colour != "#FFFFFF" && shadeColour != "#000000")
		colour = "#FFFFFF"
		shadeColour = "#000000"
		to_chat(user, "You will now draw in white and black with this crayon.")
	else
		colour = "#000000"
		shadeColour = "#FFFFFF"
		to_chat(user, "You will now draw in black and white with this crayon.")
	return OP_OK

/obj/item/pen/crayon/rainbow
	icon_state = "crayonrainbow"
	colour = "#FFF000"
	shadeColour = "#000FFF"
	colourName = "rainbow"
	uses = 0

CAPABILITIES(/obj/item/pen/crayon/rainbow)
	op("interaction_pick_colour", in_hand(), label("Pick colour"), then(PROC_REF(interaction_pick_colour)))

/// Old attack_self.
/obj/item/pen/crayon/rainbow/proc/interaction_pick_colour(datum/act/op/A)
	var/mob/living/user = A.actor
	ask_rainbow_colour(user, "Crayon colour", "Crayon shade colour")
	return

/// A rainbow crayon or marker picks its main colour, then its shade (a cancel keeps that one).
/obj/item/pen/crayon/proc/ask_rainbow_colour(mob/user, main_title, shade_title)
	open_request(src, /datum/prompt/color/crayon_colour, PROC_REF(rainbow_colour_picked), answerer = user, title = main_title, question = "Please select the main colour.", default = colour, shade_title = shade_title)

/obj/item/pen/crayon/proc/ask_rainbow_shade(mob/user, shade_title)
	open_request(src, /datum/prompt/color/crayon_colour, PROC_REF(rainbow_colour_picked), answerer = user, title = shade_title, question = "Please select the shade colour.", default = shadeColour, shade = TRUE)

/// Re-checked on the answer: the crayon is still carried.
/datum/prompt/color/crayon_colour
	ask_flags = ASK_CARRIED
	timeout = 0
	/// TRUE: this is the shade pick.
	var/shade = FALSE
	var/shade_title

/obj/item/pen/crayon/proc/rainbow_colour_picked(datum/act/request/A)
	// Explicit closing skipped old prompt rechecks; a rejected answer did not continue.
	if(!A.answer && (A.request.outcome != REQ_CANCELLED || !isnull(A.request.value)))
		return
	var/mob/user = A.request.answerer
	if(!user || QDELETED(user))
		return
	var/datum/prompt/color/crayon_colour/prompt = A.request
	if(prompt.shade)
		if(A.answer && A.answer.value)
			shadeColour = A.answer.value
		return
	if(A.answer && A.answer.value)
		colour = A.answer.value
	ask_rainbow_shade(user, prompt.shade_title)

/obj/item/pen/crayon/afterattack(atom/target, mob/user, proximity, click_parameters)
	if(!proximity) return
	if(istype(target,/turf/simulated/floor))
		open_request(src, /datum/prompt/choice/crayon_kind, PROC_REF(ask_drawing), answerer = user, subject = target, click_parameters = click_parameters)
	return

/// What to draw, then which one. The subject is the floor: still in reach, and the drawer able.
/datum/prompt/choice/crayon_kind
	title = "Crayon scribbles"
	recheck_on_open = TRUE
	question = "Choose what you'd like to draw."
	choices = list("graffiti","rune","letter","arrow")
	timeout = 0
	var/click_parameters

/datum/prompt/choice/crayon_drawing
	parent_type = /datum/prompt/choice/crayon_kind
	var/drawing_kind

/datum/prompt/choice/crayon_drawing/prepare(datum/act/context)
	. = ..()
	switch(drawing_kind)
		if("letter")
			question = "Choose the letter."
			choices = list("a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z")
		if("graffiti")
			question = "Choose the graffiti."
			choices = list("amyjon","face","matt","revolution","engie","guy","end","dwarf","uboa")
		if("rune")
			question = "Choose the rune."
			choices = list("rune1", "rune2", "rune3", "rune4", "rune5", "rune6")
		if("arrow")
			question = "Choose the arrow."
			choices = list("left", "right", "up", "down")
		else
			return FALSE
	return TRUE

/obj/item/pen/crayon/proc/ask_drawing(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/crayon_kind/ask = context.answer
	open_request(src, /datum/prompt/choice/crayon_drawing, PROC_REF(drawing_chosen), answerer = ask.answerer, subject = ask.subject, drawing_kind = ask.value, click_parameters = ask.click_parameters)

/obj/item/pen/crayon/proc/drawing_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/crayon_drawing/ask = context.answer
	var/mob/user = ask.answerer
	var/atom/target = ask.subject
	var/drawtype = ask.value
	if(!drawtype)
		return
	switch(ask.drawing_kind)
		if("letter")
			to_chat(user, "You start drawing a letter on the [target.name].")
		if("graffiti")
			to_chat(user, "You start drawing graffiti on the [target.name].")
		if("rune")
			to_chat(user, "You start drawing a rune on the [target.name].")
		if("arrow")
			to_chat(user, "You start drawing an arrow on the [target.name].")
	perform_op(user, src, "draw", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("surface" = target, "drawtype" = drawtype, "click_parameters" = ask.click_parameters))

/// The drawing is a wait of the crayon's own (the surface, the picked drawing and the click come from the prompt chain that started it).
CAPABILITIES(/obj/item/pen/crayon)
	op("draw", ai(), takes("surface", "drawtype", "click_parameters"), wait(PROC_REF(draw_wait)), then(PROC_REF(draw_done)))

/// How long the drawing takes: nothing for an instant crayon.
/obj/item/pen/crayon/proc/draw_wait(datum/act/op/A)
	return instant ? 0 : 5 SECONDS

/obj/item/pen/crayon/proc/draw_done(datum/act/op/A)
	var/atom/target = A.arg("surface")
	var/mob/user = A.actor
	var/drawtype = A.arg("drawtype")
	var/click_parameters = A.arg("click_parameters")
	if(QDELETED(target))
		return OP_FAILED
	var/list/mouse_control = params2list(click_parameters)
	var/p_x = 0
	var/p_y = 0
	if(mouse_control["icon-x"])
		p_x = text2num(mouse_control["icon-x"]) - 16
	if(mouse_control["icon-y"])
		p_y = text2num(mouse_control["icon-y"]) - 16
	var/atom/new_graffiti = new /obj/effect/decal/cleanable/crayon(target,colour,shadeColour,drawtype)
	new_graffiti.pixel_x = p_x
	new_graffiti.pixel_y = p_y
	to_chat(user, "You finish drawing.")

	var/msg = "[user.client?.key] ([user]) has drawn [drawtype] (with [src]) at [target.x],[target.y],[target.z]."
	if(CONFIG_GET(flag/log_graffiti))
		message_admins(msg)
	log_game(msg) //We will log it anyways.

	target.add_fingerprint(user)		// Adds their fingerprints to the floor the crayon is drawn on.
	if(uses)
		uses--
		if(!uses)
			to_chat(user, span_warning("You used up your crayon!"))
			consume(src, user)
	return OP_OK

/obj/item/pen/crayon/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(M == user)
		to_chat(user, "You take a bite of the crayon and swallow it.")
		user.adjust_nutrition(1)
		if(ishuman(user))
			var/mob/living/carbon/human/human = user
			human.ingested.add_reagent(REAGENT_ID_CRAYONDUST,min(5,uses)/3)
		else
			user.reagents.add_reagent(REAGENT_ID_CRAYONDUST,min(5,uses)/3)
		if(uses)
			uses -= 5
			if(uses <= 0)
				to_chat(user, span_warning("You ate your crayon!"))
				consume(src, user)
		return ITEM_INTERACT_SUCCESS
	else
		..()

/obj/item/pen/crayon/marker/mime
	icon_state = "markermime"
	desc = "A very sad-looking marker."
	colour = "#FFFFFF"
	shadeColour = "#000000"
	colourName = "mime"
	uses = 0

CAPABILITIES(/obj/item/pen/crayon/marker/mime)
	op("invert", in_hand(), label("Invert colours"), then(PROC_REF(mime_marker_inverted)))

/obj/item/pen/crayon/marker/mime/proc/mime_marker_inverted(datum/act/op/A)
	var/mob/living/user = A.actor
	if(colour != "#FFFFFF" && shadeColour != "#000000")
		colour = "#FFFFFF"
		shadeColour = "#000000"
		to_chat(user, "You will now draw in white and black with this marker.")
	else
		colour = "#000000"
		shadeColour = "#FFFFFF"
		to_chat(user, "You will now draw in black and white with this marker.")
	return OP_OK

/obj/item/pen/crayon/marker/rainbow
	icon_state = "markerrainbow"
	colour = "#FFF000"
	shadeColour = "#000FFF"
	colourName = "rainbow"
	uses = 0

CAPABILITIES(/obj/item/pen/crayon/marker/rainbow)
	op("interaction_pick_colour", in_hand(), label("Pick colour"), then(PROC_REF(interaction_pick_colour)))

/// Old attack_self.
/obj/item/pen/crayon/marker/rainbow/proc/interaction_pick_colour(datum/act/op/A)
	var/mob/living/user = A.actor
	ask_rainbow_colour(user, "Marker colour", "Marker colour")
	return

/obj/item/pen/crayon/marker/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(M == user)
		to_chat(user, "You take a bite of the marker and swallow it.")
		user.adjust_nutrition(1)
		if(ishuman(user))
			var/mob/living/carbon/human/human = user
			human.ingested.add_reagent(REAGENT_ID_MARKERINK,6)
		else
			user.reagents.add_reagent(REAGENT_ID_MARKERINK,6)
		if(uses)
			uses -= 5
			if(uses <= 0)
				to_chat(user, span_warning("You ate the marker!"))
				consume(src, user)
		return ITEM_INTERACT_SUCCESS
	else
		..()

/datum/prompt/choice/crayon_kind/recheck_extra()
	var/mob/drawer = answerer
	var/atom/surface = subject
	if(!istype(drawer) || QDELETED(drawer) || !istype(surface) || QDELETED(surface))
		return "too far away"
	var/turf/drawer_turf = get_turf(drawer)
	var/turf/surface_turf = get_turf(surface)
	if(!drawer_turf || !surface_turf || drawer_turf.z != surface_turf.z || get_dist(drawer_turf, surface_turf) > 1)
		return "too far away"
	if(drawer.incapacitated(INCAPACITATION_DEFAULT))
		return "not able to"
