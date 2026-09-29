DECLARE_APPEARANCE_PROC(/mob/living/silicon/robot/platform, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/silicon/robot/platform/appearance_overlays()
	. = list()

	underlays.Cut()
	var/obj/item/robot_module/robot/platform/tank_module = module
	if(!istype(tank_module))
		icon = initial(icon)
		icon_state = initial(icon_state)
		color = initial(color)
		return .

	// This is necessary due to Polaris' liberal use of KEEP_TOGETHER and propensity for scaling transforms.
	// If we just apply state/colour to the base icon, RESET_COLOR on the additional overlays is ignored.
	icon = tank_module.user_icon
	icon_state = "blank"
	color = null
	var/image/I = image(tank_module.user_icon, tank_module.user_icon_state)
	I.color = tank_module.base_color
	I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
	underlays += I

	if(tank_module.armor_color)
		I = image(icon, "[tank_module.user_icon_state]_armour")
		I.color = tank_module.armor_color
		I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
		. += I

	for(var/decal in tank_module.decals)
		I = image(icon, "[tank_module.user_icon_state]_[decal]")
		I.color = tank_module.decals[decal]
		I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
		. += I

	if(tank_module.eye_color)
		I = image(icon, "[tank_module.user_icon_state]_eyes")
		I.color = tank_module.eye_color
		I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
		. += I

	if(client && key && stat == CONSCIOUS && tank_module.pupil_color)
		I = image(icon, "[tank_module.user_icon_state]_pupils")
		I.color = tank_module.pupil_color
		I.plane = PLANE_LIGHTING_ABOVE
		I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
		. += I

	if(opened)
		. += "[tank_module.user_icon_state]-open"
		if(wiresexposed)
			I = image(icon, "[tank_module.user_icon_state]-wires")
		else if(cell)
			I = image(icon, "[tank_module.user_icon_state]-cell")
		else
			I = image(icon, "[tank_module.user_icon_state]-nowires")
		I.appearance_flags |= (RESET_COLOR|PIXEL_SCALE)
		. += I

/mob/living/silicon/robot/platform/proc/try_paint(obj/item/floor_painter/painting, mob/user)

	var/obj/item/robot_module/robot/platform/tank_module = module
	if(!istype(tank_module))
		to_chat(user, span_warning("\The [src] is not paintable."))
		return FALSE

	var/list/options = list("Eyes", "Armour", "Body", "Clear Colors")
	if(length(tank_module.available_decals))
		options += "Decal"
	if(length(tank_module.decals))
		options += "Clear Decals"
	for(var/option in options)
		LAZYSET(options, option, new /image('icons/effects/thinktank_labels.dmi', option))

	om_ask(user, /datum/om/prompt/choice/radial/platform_paint, PROC_REF(paint_part_chosen), choices = options, anchor = painting, radius = 42, require_near = TRUE, painting = painting)
	return TRUE

/// What to paint on a platform, with the painter used. The painter is held as a handle.
/datum/om/prompt/choice/radial/platform_paint
	var/obj/item/floor_painter/painting

/// Re-checks the old custom state after a paint radial answer.
/mob/living/silicon/robot/platform/proc/paint_still_valid(datum/om/prompt/choice/radial/platform_paint/ask)
	var/mob/user = ask.answerer
	var/obj/item/robot_module/robot/platform/tank_module = module
	if(!ask.choice || QDELETED(src) || QDELETED(ask.painting) || QDELETED(user) || user.incapacitated())
		return FALSE
	if(!istype(tank_module) || tank_module.loc != src)
		return FALSE
	return TRUE

/// First paint radial answer: a part, or "Decal" which opens the decal menu.
/mob/living/silicon/robot/platform/proc/paint_part_chosen(datum/om/prompt/choice/radial/platform_paint/ask)
	if(!paint_still_valid(ask))
		return
	if(ask.choice == "Decal")
		var/obj/item/robot_module/robot/platform/tank_module = module
		var/list/available = tank_module.available_decals
		var/list/options = list()
		for(var/decal_name in available)
			LAZYSET(options, decal_name, new /image('icons/effects/thinktank_labels.dmi', decal_name))
		om_ask(ask.answerer, /datum/om/prompt/choice/radial/platform_paint, PROC_REF(paint_decal_chosen), choices = options, anchor = ask.painting, radius = 42, require_near = TRUE, painting = ask.painting)
		return
	apply_paint(ask.choice, ask.painting)

/// Decal radial answer.
/mob/living/silicon/robot/platform/proc/paint_decal_chosen(datum/om/prompt/choice/radial/platform_paint/ask)
	if(!paint_still_valid(ask))
		return
	apply_paint(ask.choice, ask.painting)

/// Applies a paint choice. Returns TRUE if anything changed.
/mob/living/silicon/robot/platform/proc/apply_paint(choice, obj/item/floor_painter/painting)
	var/obj/item/robot_module/robot/platform/tank_module = module
	. = TRUE
	switch(choice)
		if("Eyes")
			tank_module.eye_color =   painting.paint_colour
		if("Armour")
			tank_module.armor_color = painting.paint_colour
		if("Body")
			tank_module.base_color =  painting.paint_colour
		if("Clear Colors")
			tank_module.eye_color =   initial(tank_module.eye_color)
			tank_module.armor_color = initial(tank_module.armor_color)
			tank_module.base_color =  initial(tank_module.base_color)
		if("Clear Decals")
			tank_module.decals = null
		else
			if(choice in tank_module.available_decals)
				LAZYSET(tank_module.decals, tank_module.available_decals[choice], painting.paint_colour)
			else
				. = FALSE
	if(.)
		update_icon()
