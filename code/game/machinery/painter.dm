/obj/machinery/gear_painter
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 40
	name = "Color Mate"
	desc = "A machine to give your apparel a fresh new color!"
	icon = 'icons/obj/vending_vr.dmi'
	icon_state = "colormate"
	density = TRUE
	anchored = TRUE
	var/atom/movable/inserted
	var/activecolor = "#FFFFFF"
	var/list/color_matrix_last
	var/active_mode = COLORMATE_HSV

	var/build_hue = 0
	var/build_sat = 1
	var/build_val = 1

	/// Allow holder'd mobs
	var/allow_mobs = TRUE
	/// Minimum lightness for normal mode
	var/minimum_normal_lightness = 50
	/// Minimum lightness for matrix mode, tested using 4 test colors of full red, green, blue, white.
	var/minimum_matrix_lightness = 75
	/// Minimum matrix tests that must pass for something to be considered a valid color (see above)
	var/minimum_matrix_tests = 2
	/// Temporary messages
	var/temp

	var/static/list/allowed_types = list(
		/obj/item/clothing,
		/obj/item/storage/backpack,
		/obj/item/storage/belt,
		/obj/item/toy,
		/obj/item/stack/material
	)

/obj/machinery/gear_painter/Initialize(mapload)
	. = ..()
	color_matrix_last = list(
		1, 0, 0,
		0, 1, 0,
		0, 0, 1,
		0, 0, 0,
	)

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/gear_painter/draw(datum/look/look)
	..()
	look.state("colormate[inserted ? "_active" : ""]")
	if(operable() == 0)
		look.state("colormate_off")
	if(panel_open == 1)
		look.state("colormate_open")

CAPABILITIES(/obj/machinery/gear_painter)
	owns_one(nameof(inserted), on_destroy = ON_DESTROY_SPILL)
	interface("ColorMate")
	op("switch_modes", ui_act("switch_modes", arg("mode", num())), then(PROC_REF(ui_act_switch_modes)))
	op("choose_color", ui_act("choose_color"), needs(req_adjacent(), req_capable()), asks(/datum/prompt/color, fields = list("default" = computed(PROC_REF(colour_default)), "title" = "ColorMate colour picking", "question" = "Choose a color: ", "timeout" = 0), when = PROC_REF(colour_item_present)), then(PROC_REF(ui_act_choose_color)))
	op("paint", ui_act("paint"), then(PROC_REF(ui_act_paint)))
	op("drop", ui_act("drop"), then(PROC_REF(ui_act_drop)))
	op("clear", ui_act("clear"), then(PROC_REF(ui_act_clear)))
	op("set_matrix_color", ui_act("set_matrix_color", arg("color", num()), arg("value", num())), then(PROC_REF(ui_act_set_matrix_color)))
	op("set_matrix_string", ui_act("set_matrix_string", arg("value", schema_text(4096))), then(PROC_REF(ui_act_set_matrix_string)))
	op("set_hue", ui_act("set_hue", arg("buildhue", num(0, 360))), then(PROC_REF(ui_act_set_hue)))
	op("set_sat", ui_act("set_sat", arg("buildsat", num(-10, 10))), then(PROC_REF(ui_act_set_sat)))
	op("set_val", ui_act("set_val", arg("buildval", num(-10, 10))), then(PROC_REF(ui_act_set_val)))
	op("gear_painter_insert", inputs(item(/obj/item/clothing), item(/obj/item/storage/backpack), item(/obj/item/storage/belt), item(/obj/item/toy), item(/obj/item/stack/material)), priority(OP_PRIORITY_DEFAULT - 1), label("Insert"), when(req_operable()), needs(req_empty(nameof(inserted), because = MSG(gear_painter/loaded))), then(PROC_REF(interaction_insert)))
	op("gear_painter_alt_drop", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Remove item"), passes(), then(PROC_REF(interaction_alt_drop)))

/obj/machinery/gear_painter/proc/interaction_insert(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I,/obj/item/stack/material/cyborg)) //Needs an exception for borg materials to avoid glitches.
		return OP_OK
	act_message(user, null, others = span_notice("%U% inserts %I% into the Color Mate receptable."), item = I)
	if(!move_into(src, nameof(src.inserted), I, user))
		return OP_OK
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/gear_painter/proc/insert_mob(mob/victim, mob/user)
	if(inserted)
		return
	if(user)
		act_message(user, victim, others = span_warning("%U% stuffs %T% into [src]!"))
	move_into(src, nameof(src.inserted), victim, user)

/obj/machinery/gear_painter/AllowDrop()
	return FALSE

/**
 * Old click_alt: `. = ..(); drop_item(user)` — the default alt-click behaviour always ran,
 * then the item was dropped regardless. Approximated: drop_item() now runs first and
 * declines, so the base alt-click default still runs after it (order reversed from the
 * original, which is not expected to matter here — drop_item() and the base alt-click
 * default don't interact).
 */

/obj/machinery/gear_painter/proc/interaction_alt_drop(datum/act/op/A)
	var/mob/user = A.actor
	drop_item(user)
	return OP_DECLINE

/obj/machinery/gear_painter/proc/drop_item(mob/user)
	if(!oview(1,src))
		return
	if(!inserted)
		return
	to_chat(user, span_notice("You remove [inserted] from [src]"))
	inserted.forceMove(drop_location())
	if(isliving(user))
		user.put_in_hands(inserted)
	rel_take(src, nameof(inserted))
	SStgui.update_uis(src)

/obj/machinery/gear_painter/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	. = list()
	.["matrixcolors"] = list(
		"rr" = color_matrix_last[1],
		"rg" = color_matrix_last[2],
		"rb" = color_matrix_last[3],
		"gr" = color_matrix_last[4],
		"gg" = color_matrix_last[5],
		"gb" = color_matrix_last[6],
		"br" = color_matrix_last[7],
		"bg" = color_matrix_last[8],
		"bb" = color_matrix_last[9],
		"cr" = color_matrix_last[10],
		"cg" = color_matrix_last[11],
		"cb" = color_matrix_last[12],
	)
	if(temp)
		.["temp"] = temp
	if(inserted)
		.["item_name"] = inserted.name
		.["item_sprite"] = icon2base64(get_flat_icon(inserted,dir=SOUTH,no_anim=TRUE))
		.["item_preview"] = icon2base64(build_preview(user))
	else
		.["item_name"] = null
		.["item_sprite"] = null
		.["item_preview"] = null
	.["activemode"] = active_mode
	.["buildhue"] = build_hue
	.["buildsat"] = build_sat
	.["buildval"] = build_val

/obj/machinery/gear_painter/proc/colour_item_present(datum/act/op/A)
	return !!read_once(inserted)

/obj/machinery/gear_painter/proc/colour_default(datum/act/op/A)
	return read_once(activecolor)

/obj/machinery/gear_painter/proc/ui_act_switch_modes(datum/act/op/A, mode)
	if(!(inserted))
		return
	active_mode = mode
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_choose_color(datum/act/op/A)
	if(A.answer?.value)
		activecolor = A.answer.value
		SStgui.update_uis(src)
	return OP_OK

/obj/machinery/gear_painter/proc/ui_act_paint(datum/act/op/A)
	var/mob/user = A.actor
	if(!(inserted))
		return
	if(!do_paint(user))
		return TRUE
	temp = "Painted Successfully!"
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_drop(datum/act/op/A)
	var/mob/user = A.actor
	if(!(inserted))
		return
	temp = ""
	drop_item(user)
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_clear(datum/act/op/A)
	if(!(inserted))
		return
	inserted.remove_atom_colour(FIXED_COLOUR_PRIORITY)
	play_sfx(src, SFX_EFFECTS_SPRAY3)
	temp = "Cleared Successfully!"
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_set_matrix_color(datum/act/op/A, raw_color, value)
	if(!(inserted))
		return
	color_matrix_last[raw_color] = value
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_set_matrix_string(datum/act/op/A, value)
	if(!(inserted))
		return
	if(value)
		var/list/colours = splittext(value, ",")
		if(colours.len > 12)
			colours.Cut(13)
		for(var/i = 1, i <= colours.len, i++)
			var/number = text2num(colours[i])
			if(isnum(number))
				color_matrix_last[i] = clamp(number, -10, 10)
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_set_hue(datum/act/op/A, buildhue)
	if(!(inserted))
		return
	build_hue = buildhue
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_set_sat(datum/act/op/A, buildsat)
	if(!(inserted))
		return
	build_sat = buildsat
	return TRUE

/obj/machinery/gear_painter/proc/ui_act_set_val(datum/act/op/A, buildval)
	if(!(inserted))
		return
	build_val = buildval
	return TRUE

/obj/machinery/gear_painter/proc/do_paint(mob/user)
	var/color_to_use
	switch(active_mode)
		if(COLORMATE_TINT)
			color_to_use = activecolor
		if(COLORMATE_MATRIX, COLORMATE_MATRIX_AUTO)
			color_to_use = rgb_construct_color_matrix(
				text2num(color_matrix_last[1]),
				text2num(color_matrix_last[2]),
				text2num(color_matrix_last[3]),
				text2num(color_matrix_last[4]),
				text2num(color_matrix_last[5]),
				text2num(color_matrix_last[6]),
				text2num(color_matrix_last[7]),
				text2num(color_matrix_last[8]),
				text2num(color_matrix_last[9]),
				text2num(color_matrix_last[10]),
				text2num(color_matrix_last[11]),
				text2num(color_matrix_last[12]),
			)
		if(COLORMATE_HSV)
			color_to_use = color_matrix_hsv(build_hue, build_sat, build_val)
			color_matrix_last = color_to_use
	if(!color_to_use || !check_valid_color(color_to_use, user))
		temp = "Invalid color!"
		return FALSE
	inserted.add_atom_colour(color_to_use, FIXED_COLOUR_PRIORITY)
	play_sfx(src, SFX_EFFECTS_SPRAY3)
	return TRUE

/// Produces the preview image of the item, used in the UI, the way the color is not stacking is a sin.
/obj/machinery/gear_painter/proc/build_preview(mob/user)
	if(inserted) //sanity
		var/list/cm
		switch(active_mode)
			if(COLORMATE_MATRIX, COLORMATE_MATRIX_AUTO)
				cm = rgb_construct_color_matrix(
					text2num(color_matrix_last[1]),
					text2num(color_matrix_last[2]),
					text2num(color_matrix_last[3]),
					text2num(color_matrix_last[4]),
					text2num(color_matrix_last[5]),
					text2num(color_matrix_last[6]),
					text2num(color_matrix_last[7]),
					text2num(color_matrix_last[8]),
					text2num(color_matrix_last[9]),
					text2num(color_matrix_last[10]),
					text2num(color_matrix_last[11]),
					text2num(color_matrix_last[12]),
				)
				if(!check_valid_color(cm, user))
					return get_flat_icon(inserted, dir=SOUTH, no_anim=TRUE)

			if(COLORMATE_TINT)
				if(!check_valid_color(activecolor, user))
					return get_flat_icon(inserted, dir=SOUTH, no_anim=TRUE)

			if(COLORMATE_HSV)
				cm = color_matrix_hsv(build_hue, build_sat, build_val)
				color_matrix_last = cm
				if(!check_valid_color(cm, user))
					return get_flat_icon(inserted, dir=SOUTH, no_anim=TRUE)

		var/cur_color = inserted.color
		inserted.color = null
		inserted.color = (active_mode == COLORMATE_TINT ? activecolor : cm)
		var/icon/preview = get_flat_icon(inserted, dir=SOUTH, no_anim=TRUE)
		inserted.color = cur_color
		temp = ""

		. = preview

/obj/machinery/gear_painter/proc/check_valid_color(list/cm, mob/user)
	if(!islist(cm))		// normal
		var/list/HSV = ReadHSV(RGBtoHSV(cm))
		if(HSV[3] < minimum_normal_lightness)
			temp = "[cm] is too dark (Minimum lightness: [minimum_normal_lightness])"
			return FALSE
		return TRUE
	else	// matrix
		// We test using full red, green, blue, and white
		// A predefined number of them must pass to be considered valid
		var/passed = 0
#define COLORTEST(thestring, thematrix) passed += (ReadHSV(RGBtoHSV(RGBMatrixTransform(thestring, thematrix)))[3] >= minimum_matrix_lightness)
		COLORTEST("FF0000", cm)
		COLORTEST("00FF00", cm)
		COLORTEST("0000FF", cm)
		COLORTEST("FFFFFF", cm)
#undef COLORTEST
		if(passed < minimum_matrix_tests)
			temp = "Matrix is too dark. (passed [passed] out of [minimum_matrix_tests] required tests. Minimum lightness: [minimum_matrix_lightness])."
			return FALSE
		return TRUE

MSG_DEF_SELF(gear_painter/loaded, "the machine is already loaded")
