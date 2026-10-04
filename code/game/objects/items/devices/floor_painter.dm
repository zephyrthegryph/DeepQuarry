/obj/item/floor_painter
	name = "paint sprayer"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "labeler1"

	var/decal =        "remove all decals"
	var/paint_dir =    "precise"
	var/paint_colour = "#FFFFFF"

	var/static/list/decals = list(
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
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

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

	floor_decal_paint(F, painting_decal, painting_dir, painting_colour)

TRACKED(/obj/item/floor_painter, decal)
TRACKED(/obj/item/floor_painter, paint_dir)
TRACKED(/obj/item/floor_painter, paint_colour)

CAPABILITIES(/obj/item/floor_painter)
	held_verb(/obj/item/floor_painter/proc/choose_colour, SLOT_ANY_CARRIED)
	held_verb(/obj/item/floor_painter/proc/choose_decal, SLOT_ANY_CARRIED)
	held_verb(/obj/item/floor_painter/proc/choose_direction, SLOT_ANY_CARRIED)
	op("configure", in_hand(), label("Configure paint sprayer"), needs(carried(), req_capable()),
		asks(/datum/prompt/choice, keeps = 0, step = "setting", fields = list("title" = "Modify What?", "question" = "Do you wish to change the decal type, paint direction, or paint colour?", "choices" = list("Decal", "Direction", "Colour", "Cancel"), "buttons" = TRUE, "timeout" = 0)),
		asks(/datum/prompt/choice/floor_painter_decal, fields = list("timeout" = 0), keeps = 0, step = "decal", when = PROC_REF(changing_decal)),
		asks(/datum/prompt/choice/floor_painter_direction, fields = list("timeout" = 0), keeps = 0, step = "direction", when = PROC_REF(changing_direction)),
		asks(/datum/prompt/color/floor_painter, fields = list("timeout" = 0), keeps = 0, step = "colour", when = PROC_REF(changing_colour)), then(PROC_REF(setting_chosen)))
	op("decal", menu(), label("Choose Decal"), needs(carried(), req_capable()), asks(/datum/prompt/choice/floor_painter_decal, fields = list("timeout" = 0), keeps = 0, step = "decal"), then(PROC_REF(decal_chosen)))
	op("direction", menu(), label("Choose Direction"), needs(carried(), req_capable()), asks(/datum/prompt/choice/floor_painter_direction, fields = list("timeout" = 0), keeps = 0, step = "direction"), then(PROC_REF(direction_chosen)))
	op("colour", menu(), label("Choose Colour"), needs(carried(), req_capable()), asks(/datum/prompt/color/floor_painter, fields = list("timeout" = 0), keeps = 0, step = "colour"), then(PROC_REF(colour_chosen)))

/obj/item/floor_painter/proc/changing_decal(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("setting")
	return R?.value == "Decal"

/obj/item/floor_painter/proc/changing_direction(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("setting")
	return R?.value == "Direction"

/obj/item/floor_painter/proc/changing_colour(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("setting")
	return R?.value == "Colour"

/obj/item/floor_painter/proc/setting_chosen(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("setting")
	switch(R.value)
		if("Decal")
			return decal_chosen(A)
		if("Direction")
			return direction_chosen(A)
		if("Colour")
			return colour_chosen(A)
	return OP_OK

/obj/item/floor_painter/proc/decal_chosen(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("decal")
	set_decal(R.value)
	to_chat(A.actor, span_notice("You set \the [src] decal to '[decal]'."))
	return OP_OK

/obj/item/floor_painter/proc/direction_chosen(datum/act/op/A)
	var/datum/prompt/choice/R = A.step_answer("direction")
	set_paint_dir(R.value)
	to_chat(A.actor, span_notice("You set \the [src] direction to '[paint_dir]'."))
	return OP_OK

/obj/item/floor_painter/proc/colour_chosen(datum/act/op/A)
	var/datum/prompt/color/R = A.step_answer("colour")
	if(R.value && R.value != paint_colour)
		set_paint_colour(R.value)
		to_chat(A.actor, span_notice("You set \the [src] to paint with <font color='[paint_colour]'>a new colour</font>."))
	return OP_OK

/datum/prompt/choice/floor_painter_decal
	title = "Decal Choice"
	question = "Select a decal:"
	timeout = 0

/datum/prompt/choice/floor_painter_decal/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		var/obj/item/floor_painter/painter = asking.target
		if(istype(painter))
			choices = painter.decals

/datum/prompt/choice/floor_painter_direction
	title = "Direction Choice"
	question = "Select a direction:"
	timeout = 0

/datum/prompt/choice/floor_painter_direction/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		var/obj/item/floor_painter/painter = asking.target
		if(istype(painter))
			choices = painter.paint_dirs

/datum/prompt/color/floor_painter
	question = "Choose a colour."
	timeout = 0

/datum/prompt/color/floor_painter/prepare(datum/act/A)
	. = ..()
	if(istype(A, /datum/act/op))
		var/datum/act/op/asking = A
		var/obj/item/floor_painter/painter = asking.target
		if(istype(painter))
			title = painter.name
			default = painter.paint_colour

/obj/item/floor_painter/examine(mob/user)
	. = ..()
	. += "It is configured to produce the '[decal]' decal with a direction of '[paint_dir]' using [paint_colour] paint."

/obj/item/floor_painter/proc/choose_colour()
	set name = "Choose Colour"
	set category = VERB_CAT_OBJECT
	set src in usr

	perform_op(usr, src, "colour", null, ORIGIN_VERB)

/obj/item/floor_painter/proc/choose_decal()
	set name = "Choose Decal"
	set category = VERB_CAT_OBJECT
	set src in usr

	perform_op(usr, src, "decal", null, ORIGIN_VERB)

/obj/item/floor_painter/proc/choose_direction()
	set name = "Choose Direction"
	set category = VERB_CAT_OBJECT
	set src in usr

	perform_op(usr, src, "direction", null, ORIGIN_VERB)
