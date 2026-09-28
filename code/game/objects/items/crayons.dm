/obj/item/pen/crayon/mime
	icon_state = "crayonmime"
	desc = "A very sad-looking crayon."
	colour = "#FFFFFF"
	shadeColour = "#000000"
	colourName = "mime"
	uses = 0

/obj/item/pen/crayon/mime/attack_self(mob/living/user) //inversion
	. = ..(user)
	if(.)
		return TRUE
	if(colour != "#FFFFFF" && shadeColour != "#000000")
		colour = "#FFFFFF"
		shadeColour = "#000000"
		to_chat(user, "You will now draw in white and black with this crayon.")
	else
		colour = "#000000"
		shadeColour = "#FFFFFF"
		to_chat(user, "You will now draw in black and white with this crayon.")
	return

/obj/item/pen/crayon/rainbow
	icon_state = "crayonrainbow"
	colour = "#FFF000"
	shadeColour = "#000FFF"
	colourName = "rainbow"
	uses = 0

/obj/item/pen/crayon/rainbow/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/new_colour = tgui_color_picker(user, "Please select the main colour.", "Crayon colour", colour)
	if(new_colour)
		colour = new_colour
	new_colour = tgui_color_picker(user, "Please select the shade colour.", "Crayon shade colour", shadeColour)
	if(new_colour)
		shadeColour = new_colour
	return

/obj/item/pen/crayon/afterattack(atom/target, mob/user, proximity, click_parameters)
	if(!proximity) return
	if(istype(target,/turf/simulated/floor))
		om_prompt_sequence(src, user, list(
			list("key" = "kind", "kind" = "list", "message" = "Choose what you'd like to draw.", "title" = "Crayon scribbles", "choices" = list("graffiti","rune","letter","arrow")),
			PROC_REF(ask_drawing),
		), PROC_REF(drawing_chosen), list("target" = target, "requires" = list(/datum/om/check/in_range, /datum/om/check/not_incapacitated), "data" = list("canvas" = target, "params" = click_parameters)))
	return

/obj/item/pen/crayon/proc/ask_drawing(mob/user, datum/om/prompt/ask)
	switch(ask.get("kind"))
		if("letter")
			return list("key" = "drawtype", "kind" = "list", "message" = "Choose the letter.", "title" = "Crayon scribbles", "choices" = list("a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"))
		if("graffiti")
			return list("key" = "drawtype", "kind" = "list", "message" = "Choose the graffiti.", "title" = "Crayon scribbles", "choices" = list("amyjon","face","matt","revolution","engie","guy","end","dwarf","uboa"))
		if("rune")
			return list("key" = "drawtype", "kind" = "list", "message" = "Choose the rune.", "title" = "Crayon scribbles", "choices" = list("rune1", "rune2", "rune3", "rune4", "rune5", "rune6"))
		if("arrow")
			return list("key" = "drawtype", "kind" = "list", "message" = "Choose the arrow.", "title" = "Crayon scribbles", "choices" = list("left", "right", "up", "down"))

/obj/item/pen/crayon/proc/drawing_chosen(mob/user, datum/om/prompt/ask)
	var/atom/target = ask.get("canvas")
	var/drawtype = ask.get("drawtype")
	if(!drawtype)
		return
	switch(ask.get("kind"))
		if("letter")
			to_chat(user, "You start drawing a letter on the [target.name].")
		if("graffiti")
			to_chat(user, "You start drawing graffiti on the [target.name].")
		if("rune")
			to_chat(user, "You start drawing a rune on the [target.name].")
		if("arrow")
			to_chat(user, "You start drawing an arrow on the [target.name].")
	om_task_start(/datum/om/task/timed/crayon_draw, user, src, list("duration" = instant ? 0 : 5 SECONDS, "receiver" = src, "surface" = target, "drawtype" = drawtype, "click_parameters" = ask.get("params")))

/datum/om/task/timed/crayon_draw
	complete_proc = /obj/item/pen/crayon/proc/draw_done
	var/atom/surface
	var/drawtype
	var/click_parameters

/obj/item/pen/crayon/proc/draw_done(datum/om/task/timed/crayon_draw/task)
	var/atom/target = task.surface
	var/mob/user = task.actor
	var/drawtype = task.drawtype
	var/click_parameters = task.click_parameters
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

/obj/item/pen/crayon/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(M == user)
		to_chat(user, "You take a bite of the crayon and swallow it.")
		user.nutrition += 1
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

/obj/item/pen/crayon/marker/mime/attack_self(mob/living/user) //inversion
	. = ..(user)
	if(.)
		return TRUE
	if(colour != "#FFFFFF" && shadeColour != "#000000")
		colour = "#FFFFFF"
		shadeColour = "#000000"
		to_chat(user, "You will now draw in white and black with this marker.")
	else
		colour = "#000000"
		shadeColour = "#FFFFFF"
		to_chat(user, "You will now draw in black and white with this marker.")
	return

/obj/item/pen/crayon/marker/rainbow
	icon_state = "markerrainbow"
	colour = "#FFF000"
	shadeColour = "#000FFF"
	colourName = "rainbow"
	uses = 0

/obj/item/pen/crayon/marker/rainbow/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/new_colour = tgui_color_picker(user, "Please select the main colour.", "Marker colour", colour)
	if(new_colour)
		colour = new_colour
	new_colour = tgui_color_picker(user, "Please select the shade colour.", "Marker colour", shadeColour)
	if(new_colour)
		shadeColour = new_colour
	return

/obj/item/pen/crayon/marker/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(M == user)
		to_chat(user, "You take a bite of the marker and swallow it.")
		user.nutrition += 1
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
