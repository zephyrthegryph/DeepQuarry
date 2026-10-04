/obj/item/pen/crayon/mime
	icon_state = "crayonmime"
	desc = "A very sad-looking crayon."
	colour = "#FFFFFF"
	shadeColour = "#000000"
	colourName = "mime"
	uses = 0

CAPABILITIES(/obj/item/pen/crayon/mime)
	op("invert", in_hand(), label("Invert colours"), then(PROC_REF(interaction_invert)))

/// Old attack_self.
/obj/item/pen/crayon/mime/proc/interaction_invert(datum/act/op/A)
	var/mob/living/user = A.actor
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

CAPABILITIES(/obj/item/pen/crayon/rainbow)
	op("interaction_pick_colour", in_hand(), label("Pick colour"), then(PROC_REF(interaction_pick_colour)))

/// Old attack_self.
/obj/item/pen/crayon/rainbow/proc/interaction_pick_colour(datum/act/op/A)
	var/mob/living/user = A.actor
	ask_rainbow_colour(user, "Crayon colour", "Crayon shade colour")
	return

/// A rainbow crayon or marker picks its main colour, then its shade (a cancel keeps that one).
/obj/item/pen/crayon/proc/ask_rainbow_colour(mob/user, main_title, shade_title)
	open_request(src, /datum/prompt/color/crayon_colour, PROC_REF(rainbow_colour_picked), answerer = user, title = main_title, question = "Please select the main colour.", default = colour, shade_title = shade_title, ask_flags = ASK_CARRIED, timeout = 0)

/obj/item/pen/crayon/proc/ask_rainbow_shade(mob/user, shade_title)
	open_request(src, /datum/prompt/color/crayon_colour, PROC_REF(rainbow_colour_picked), answerer = user, title = shade_title, question = "Please select the shade colour.", default = shadeColour, shade = TRUE, ask_flags = ASK_CARRIED, timeout = 0)

/// The colour question of a rainbow crayon. The shade pick is the second one; the first remembers the title the shade window will carry.
/datum/prompt/color/crayon_colour
	/// TRUE: this is the shade pick.
	var/shade = FALSE
	var/shade_title

/// The main colour was picked, or the question ended without one (a cancel keeps the colour): either way the shade is asked next. The shade answer ends it.
/obj/item/pen/crayon/proc/rainbow_colour_picked(datum/act/request/A)
	var/datum/prompt/color/crayon_colour/R = A.request
	if(R.shade)
		if(A.answer?.answer_value)
			shadeColour = A.answer.answer_value
		return
	if(A.answer?.answer_value)
		colour = A.answer.answer_value
	ask_rainbow_shade(R.answerer, R.shade_title)

/obj/item/pen/crayon/afterattack(atom/target, mob/user, proximity, click_parameters)
	if(!proximity) return
	if(istype(target,/turf/simulated/floor))
		open_request(src, /datum/prompt/choice/crayon_kind, PROC_REF(ask_drawing), answerer = user, subject = target, title = "Crayon scribbles", question = "Choose what you'd like to draw.", choices = list("graffiti","rune","letter","arrow"), click_parameters = click_parameters, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return

/// What to draw, then which one. The subject is the floor: still in reach, and the drawer able.
/datum/prompt/choice/crayon_kind
	var/click_parameters

/// The second question: which letter, graffiti, rune or arrow. It keeps the click the drawing will land at.
/datum/prompt/choice/crayon_drawing
	var/drawing_kind
	var/click_parameters

/// What each kind of drawing offers: the question the second prompt asks and the things it lists.
/obj/item/pen/crayon/var/static/list/drawing_menus = list(
	"letter" = list("Choose the letter.", list("a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z")),
	"graffiti" = list("Choose the graffiti.", list("amyjon","face","matt","revolution","engie","guy","end","dwarf","uboa")),
	"rune" = list("Choose the rune.", list("rune1", "rune2", "rune3", "rune4", "rune5", "rune6")),
	"arrow" = list("Choose the arrow.", list("left", "right", "up", "down")),
)

/obj/item/pen/crayon/proc/ask_drawing(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/crayon_kind/R = A.request
	var/kind = A.answer.answer_value
	var/list/menu = drawing_menus[kind]
	if(!menu)
		return
	open_request(src, /datum/prompt/choice/crayon_drawing, PROC_REF(drawing_chosen), answerer = R.answerer, subject = R.subject, title = "Crayon scribbles", question = menu[1], choices = menu[2], drawing_kind = kind, click_parameters = R.click_parameters, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)

/obj/item/pen/crayon/proc/drawing_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/crayon_drawing/R = A.request
	var/mob/user = R.answerer
	var/atom/target = R.subject
	var/drawtype = A.answer.answer_value
	if(!drawtype)
		return
	switch(R.drawing_kind)
		if("letter")
			to_chat(user, "You start drawing a letter on the [target.name].")
		if("graffiti")
			to_chat(user, "You start drawing graffiti on the [target.name].")
		if("rune")
			to_chat(user, "You start drawing a rune on the [target.name].")
		if("arrow")
			to_chat(user, "You start drawing an arrow on the [target.name].")
	om_task_start(/datum/om/task/timed/crayon_draw, user, src, duration = instant ? 0 : 5 SECONDS, receiver = src, surface = target, drawtype = drawtype, click_parameters = R.click_parameters)

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
	op("invert", in_hand(), label("Invert colours"), then(PROC_REF(interaction_invert)))

/// Old attack_self.
/obj/item/pen/crayon/marker/mime/proc/interaction_invert(datum/act/op/A)
	var/mob/living/user = A.actor
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
