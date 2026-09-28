/obj/item/floor_painter
	name = "paint sprayer"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "labeler1"

	var/decal =        "remove all decals"
	var/paint_dir =    "precise"
	var/paint_colour = "#FFFFFF"

	var/list/decals = list( // ALLOW(instance_list): d: edited in place per instance (3 writers)
		"quarter-turf" =      list("path" = /obj/effect/floor_decal/corner, "precise" = 1, "coloured" = 1),
		"hazard stripes" =    list("path" = /obj/effect/floor_decal/industrial/warning),
		"corner, hazard" =    list("path" = /obj/effect/floor_decal/industrial/warning/corner),
		"hatched marking" =   list("path" = /obj/effect/floor_decal/industrial/hatch, "coloured" = 1),
		"dotted outline" =    list("path" = /obj/effect/floor_decal/industrial/outline, "coloured" = 1),
		"loading sign" =      list("path" = /obj/effect/floor_decal/industrial/loading),
		"1" =                 list("path" = /obj/effect/floor_decal/sign),
		"2" =                 list("path" = /obj/effect/floor_decal/sign/two),
		"A" =                 list("path" = /obj/effect/floor_decal/sign/a),
		"B" =                 list("path" = /obj/effect/floor_decal/sign/b),
		"C" =                 list("path" = /obj/effect/floor_decal/sign/c),
		"D" =                 list("path" = /obj/effect/floor_decal/sign/d),
		"Ex" =                list("path" = /obj/effect/floor_decal/sign/ex),
		"M" =                 list("path" = /obj/effect/floor_decal/sign/m),
		"CMO" =               list("path" = /obj/effect/floor_decal/sign/cmo),
		"V" =                 list("path" = /obj/effect/floor_decal/sign/v),
		"Psy" =               list("path" = /obj/effect/floor_decal/sign/p),
		"remove all decals" = list("path" = /obj/effect/floor_decal/reset)
		)
	var/static/list/paint_dirs = list(
		"north" =       NORTH,
		"northwest" =   NORTHWEST,
		"west" =        WEST,
		"southwest" =   SOUTHWEST,
		"south" =       SOUTH,
		"southeast" =   SOUTHEAST,
		"east" =        EAST,
		"northeast" =   NORTHEAST,
		"precise" = 0
		)
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/floor_painter/afterattack(atom/A, mob/user, proximity, params)
	if(!proximity)
		return

	if(istype(A, /mob/living/silicon/robot/platform))
		var/mob/living/silicon/robot/platform/robit = A
		return robit.try_paint(src, user)

	var/turf/simulated/floor/F = A
	if(!istype(F))
		to_chat(user, span_warning("\The [src] can only be used on station flooring."))
		return

	if(!F.flooring || !F.flooring.can_paint || F.broken || F.burnt)
		to_chat(user, span_warning("\The [src] cannot paint broken or missing tiles."))
		return

	var/list/decal_data = decals[decal]
	var/config_error
	if(!islist(decal_data))
		config_error = 1
	var/painting_decal
	if(!config_error)
		painting_decal = decal_data["path"]
		if(!ispath(painting_decal))
			config_error = 1

	if(config_error)
		to_chat(user, span_warning("\The [src] flashes an error light. You might need to reconfigure it."))
		return

	if(F.decals && F.decals.len > 5 && painting_decal != /obj/effect/floor_decal/reset)
		to_chat(user, span_warning("\The [F] has been painted too much; you need to clear it off."))
		return

	var/painting_dir = 0
	if(paint_dir == "precise")
		if(!decal_data["precise"])
			painting_dir = user.dir
		else
			var/list/mouse_control = params2list(params)
			var/mouse_x = text2num(mouse_control["icon-x"])
			var/mouse_y = text2num(mouse_control["icon-y"])
			if(isnum(mouse_x) && isnum(mouse_y))
				if(mouse_x <= 16)
					if(mouse_y <= 16)
						painting_dir = WEST
					else
						painting_dir = NORTH
				else
					if(mouse_y <= 16)
						painting_dir = SOUTH
					else
						painting_dir = EAST
			else
				painting_dir = user.dir
	else if(paint_dirs[paint_dir])
		painting_dir = paint_dirs[paint_dir]

	var/painting_colour
	if(decal_data["coloured"] && paint_colour)
		painting_colour = paint_colour

	new painting_decal(F, painting_dir, painting_colour)

DECLARE_INTERACTIONS(/obj/item/floor_painter, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/floor_painter/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/choice/floor_painter/modify, PROC_REF(modify_chosen))

/// Floor painter settings: re-checked on the answer, the painter is still carried.
/datum/om/prompt/choice/floor_painter
	ask_flags = ASK_CARRIED | ASK_CAPABLE

/datum/om/prompt/choice/floor_painter/modify
	title = "Modify What?"
	message = "Do you wish to change the decal type, paint direction, or paint colour?"
	choices = list("Decal","Direction","Colour","Cancel")
	buttons = TRUE

/datum/om/prompt/choice/floor_painter/decal
	title = "Decal Choice"
	message = "Select a decal:"

/datum/om/prompt/choice/floor_painter/direction
	title = "Direction Choice"
	message = "Select a direction:"

/// The pick must still be one of the painter's (decals and paint_dirs map names to data).
/datum/om/prompt/choice/floor_painter/decal/valid()
	return isnull(choices[choice]) ? "not a decal" : null

/datum/om/prompt/choice/floor_painter/direction/valid()
	return isnull(choices[choice]) ? "not a direction" : null

/obj/item/floor_painter/proc/modify_chosen(datum/om/prompt/choice/floor_painter/modify/ask)
	var/mob/user = ask.answerer
	switch(ask.choice)
		if("Decal")
			ask_decal(user)
		if("Direction")
			ask_direction(user)
		if("Colour")
			ask_colour(user)

/obj/item/floor_painter/proc/ask_decal(mob/user)
	om_ask(user, /datum/om/prompt/choice/floor_painter/decal, PROC_REF(decal_chosen), choices = decals)

/obj/item/floor_painter/proc/decal_chosen(datum/om/prompt/choice/floor_painter/decal/ask)
	decal = ask.choice
	to_chat(ask.answerer, span_notice("You set \the [src] decal to '[decal]'."))

/obj/item/floor_painter/proc/ask_direction(mob/user)
	om_ask(user, /datum/om/prompt/choice/floor_painter/direction, PROC_REF(direction_chosen), choices = paint_dirs)

/obj/item/floor_painter/proc/direction_chosen(datum/om/prompt/choice/floor_painter/direction/ask)
	paint_dir = ask.choice
	to_chat(ask.answerer, span_notice("You set \the [src] direction to '[paint_dir]'."))

/obj/item/floor_painter/proc/ask_colour(mob/user)
	om_ask(user, /datum/om/prompt/color, PROC_REF(colour_chosen), title = name, default = paint_colour, message = "Choose a colour.", ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/floor_painter/proc/colour_chosen(datum/om/prompt/color/ask)
	if(ask.picked_color && ask.picked_color != paint_colour)
		paint_colour = ask.picked_color
		to_chat(ask.answerer, span_notice("You set \the [src] to paint with <font color='[paint_colour]'>a new colour</font>."))

/obj/item/floor_painter/examine(mob/user)
	. = ..()
	. += "It is configured to produce the '[decal]' decal with a direction of '[paint_dir]' using [paint_colour] paint."

/obj/item/floor_painter/verb/choose_colour()
	set name = "Choose Colour"
	set desc = "Choose a paint colour."
	set category = "Object"
	set src in usr

	if(usr.incapacitated())
		return
	ask_colour(usr)

/obj/item/floor_painter/verb/choose_decal()
	set name = "Choose Decal"
	set desc = "Choose a painting decal."
	set category = "Object"
	set src in usr

	if(usr.incapacitated())
		return

	ask_decal(usr)

/obj/item/floor_painter/verb/choose_direction()
	set name = "Choose Direction"
	set desc = "Choose a painting direction."
	set category = "Object"
	set src in usr

	if(usr.incapacitated())
		return

	ask_direction(usr)
