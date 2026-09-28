/obj/item/floor_painter
	name = "paint sprayer"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "labeler1"

	var/decal =        "remove all decals"
	var/paint_dir =    "precise"
	var/paint_colour = "#FFFFFF"

	var/list/decals = list(
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
	om_prompt(src, user, list("message" = "Do you wish to change the decal type, paint direction, or paint colour?", "title" = "Modify What?", "choices" = list("Decal","Direction","Colour","Cancel"), "requires" = PROMPT_HELD), PROC_REF(modify_chosen))

/obj/item/floor_painter/proc/modify_chosen(mob/user, choice, datum/om/prompt/ask)
	switch(choice)
		if("Decal")
			ask_decal(user)
		if("Direction")
			ask_direction(user)
		if("Colour")
			ask_colour(user)

/obj/item/floor_painter/proc/ask_decal(mob/user)
	om_prompt(src, user, list("kind" = "list", "message" = "Select a decal:", "title" = "Decal Choice", "choices" = decals, "requires" = PROMPT_HELD), PROC_REF(decal_chosen))

/obj/item/floor_painter/proc/decal_chosen(mob/user, new_decal, datum/om/prompt/ask)
	if(!isnull(decals[new_decal]))
		decal = new_decal
		to_chat(user, span_notice("You set \the [src] decal to '[decal]'."))

/obj/item/floor_painter/proc/ask_direction(mob/user)
	om_prompt(src, user, list("kind" = "list", "message" = "Select a direction:", "title" = "Direction Choice", "choices" = paint_dirs, "requires" = PROMPT_HELD), PROC_REF(direction_chosen))

/obj/item/floor_painter/proc/direction_chosen(mob/user, new_dir, datum/om/prompt/ask)
	if(!isnull(paint_dirs[new_dir]))
		paint_dir = new_dir
		to_chat(user, span_notice("You set \the [src] direction to '[paint_dir]'."))

/obj/item/floor_painter/proc/ask_colour(mob/user)
	om_prompt(src, user, list("kind" = "color", "message" = "Choose a colour.", "title" = name, "default" = paint_colour, "requires" = PROMPT_HELD), PROC_REF(colour_chosen))

/obj/item/floor_painter/proc/colour_chosen(mob/user, new_colour, datum/om/prompt/ask)
	if(new_colour && new_colour != paint_colour)
		paint_colour = new_colour
		to_chat(user, span_notice("You set \the [src] to paint with <font color='[paint_colour]'>a new colour</font>."))

/obj/item/floor_painter/examine(mob/user)
	. = ..()
	. += "It is configured to produce the '[decal]' decal with a direction of '[paint_dir]' using [paint_colour] paint."

/obj/item/floor_painter/proc/choose_colour_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated())
		return
	ask_colour(user)

/obj/item/floor_painter/proc/choose_decal_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated())
		return

	ask_decal(user)

/obj/item/floor_painter/proc/choose_direction_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(user.incapacitated())
		return

	ask_direction(user)

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/floor_painter, \
	INTERACT_VERB("Choose Colour", PROC_REF(choose_colour_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Choose Decal", PROC_REF(choose_decal_effect), REQ_IN_INVENTORY), \
	INTERACT_VERB("Choose Direction", PROC_REF(choose_direction_effect), REQ_IN_INVENTORY), \
)
