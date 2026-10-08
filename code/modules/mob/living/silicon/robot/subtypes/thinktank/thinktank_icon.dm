/// The platform's look is its module's paint: the body, armour, decals, eyes and pupils, and the open hatch. It has no sprite datum sheet.
/mob/living/silicon/robot/platform/look_parts(datum/look/look)
	var/obj/item/robot_module/robot/platform/tank_module = module
	if(!istype(tank_module))
		return
	look.watch(tank_module)
	// This is necessary due to Polaris' liberal use of KEEP_TOGETHER and propensity for scaling transforms.
	// If we just apply state/colour to the base icon, RESET_COLOR on the additional overlays is ignored.
	look.set_icon(tank_module.user_icon)
	look.state("blank")
	var/flags = (RESET_COLOR|PIXEL_SCALE)
	look.overlay(look_overlay_image(tank_module.user_icon, tank_module.user_icon_state, color = tank_module.body_color, appearance_flags = flags))
	if(tank_module.armor_color)
		look.overlay(look_overlay_image(tank_module.user_icon, "[tank_module.user_icon_state]_armour", color = tank_module.armor_color, appearance_flags = flags))
	for(var/decal in tank_module.decals)
		look.overlay(look_overlay_image(tank_module.user_icon, "[tank_module.user_icon_state]_[decal]", color = tank_module.decals[decal], appearance_flags = flags))
	if(tank_module.eye_color)
		look.overlay(look_overlay_image(tank_module.user_icon, "[tank_module.user_icon_state]_eyes", color = tank_module.eye_color, appearance_flags = flags))
	if(client && key && stat == CONSCIOUS && tank_module.pupil_color)
		look.overlay(look_overlay_image(tank_module.user_icon, "[tank_module.user_icon_state]_pupils", plane = PLANE_LIGHTING_ABOVE, color = tank_module.pupil_color, appearance_flags = flags))
	if(opened)
		look.overlay("[tank_module.user_icon_state]-open")
		if(wiresexposed)
			look.overlay(look_overlay_image(tank_module.user_icon, "[tank_module.user_icon_state]-wires", appearance_flags = flags))
		else if(cell)
			look.overlay(look_overlay_image(tank_module.user_icon, "[tank_module.user_icon_state]-cell", appearance_flags = flags))
		else
			look.overlay(look_overlay_image(tank_module.user_icon, "[tank_module.user_icon_state]-nowires", appearance_flags = flags))

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

	var/datum/prompt/choice/platform_paint/paint_question = open_request(src, /datum/prompt/choice/platform_paint, PROC_REF(paint_part_chosen), answerer = user, radial = TRUE, choices = options, anchor = painting, radius = 42, require_near = TRUE, autopick_single_option = TRUE, timeout = 0)
	if(paint_question)
		rel_set(paint_question, nameof(paint_question.painting), painting)
	return TRUE

/// What to paint on a platform, with the painter used.
/datum/prompt/choice/platform_paint
	var/obj/item/floor_painter/painting

CAPABILITIES(/datum/prompt/choice/platform_paint)
	ref_one(nameof(painting), /obj/item/floor_painter)

/// Re-checks the old custom state after a paint radial answer.
/mob/living/silicon/robot/platform/proc/paint_still_valid(datum/act/request/A)
	if(!A.answer)
		return FALSE
	var/datum/prompt/choice/platform_paint/paint_question = A.request
	var/mob/user = A.request.answerer
	var/obj/item/robot_module/robot/platform/tank_module = module
	if(QDELETED(src) || QDELETED(paint_question.painting) || QDELETED(user) || user.incapacitated())
		return FALSE
	if(!istype(tank_module) || tank_module.loc != src)
		return FALSE
	return TRUE

/// First paint radial answer: a part, or "Decal" which opens the decal menu.
/mob/living/silicon/robot/platform/proc/paint_part_chosen(datum/act/request/A)
	if(!paint_still_valid(A))
		return
	var/datum/prompt/choice/platform_paint/paint_question = A.request
	var/choice = A.answer.value
	if(choice == "Decal")
		var/obj/item/robot_module/robot/platform/tank_module = module
		var/list/available = tank_module.available_decals
		var/list/options = list()
		for(var/decal_name in available)
			LAZYSET(options, decal_name, new /image('icons/effects/thinktank_labels.dmi', decal_name))
		var/datum/prompt/choice/platform_paint/decal_question = open_request(src, /datum/prompt/choice/platform_paint, PROC_REF(paint_decal_chosen), answerer = A.request.answerer, radial = TRUE, choices = options, anchor = paint_question.painting, radius = 42, require_near = TRUE, autopick_single_option = TRUE, timeout = 0)
		if(decal_question)
			rel_set(decal_question, nameof(decal_question.painting), paint_question.painting)
		return
	apply_paint(choice, paint_question.painting)

/// Decal radial answer.
/mob/living/silicon/robot/platform/proc/paint_decal_chosen(datum/act/request/A)
	if(!paint_still_valid(A))
		return
	var/datum/prompt/choice/platform_paint/paint_question = A.request
	apply_paint(A.answer.value, paint_question.painting)

/// Applies a paint choice. Returns TRUE if anything changed.
/mob/living/silicon/robot/platform/proc/apply_paint(choice, obj/item/floor_painter/painting)
	var/obj/item/robot_module/robot/platform/tank_module = module
	. = TRUE
	switch(choice)
		if("Eyes")
			tank_module.set_eye_color(painting.paint_colour)
		if("Armour")
			tank_module.set_armor_color(painting.paint_colour)
		if("Body")
			tank_module.set_body_color(painting.paint_colour)
		if("Clear Colors")
			tank_module.set_eye_color(initial(tank_module.eye_color))
			tank_module.set_armor_color(initial(tank_module.armor_color))
			tank_module.set_body_color(initial(tank_module.body_color))
		if("Clear Decals")
			tank_module.set_decals(null)
		else
			if(choice in tank_module.available_decals)
				var/list/painted = tank_module.decals?.Copy()
				LAZYSET(painted, tank_module.available_decals[choice], painting.paint_colour)
				tank_module.set_decals(painted)
			else
				. = FALSE
