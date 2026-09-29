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

APPEARANCE_TEMPLATE(/obj/machinery/gear_painter, "colormate{inserted?_active:}")
DECLARE_APPEARANCE(/obj/machinery/gear_painter, "operable", list("0" = list(APPEARANCE_ICON_STATE = "colormate_off")))
DECLARE_APPEARANCE(/obj/machinery/gear_painter, "panel_open", list("1" = list(APPEARANCE_ICON_STATE = "colormate_open")))

OWN(/obj/machinery/gear_painter, inserted, OWN_SPILL)

/obj/machinery/gear_painter/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/gear_painter_insert,
		/datum/interaction/machine_hand/open_ui,
		/datum/interaction/machine_alt/gear_painter_alt_drop,
	)
	..()

/// Old attackby: insert an item of an allowed type into the Color Mate.
/datum/interaction/machine_item/gear_painter_insert
	id = "gear_painter_insert"
	name = "Insert"
	held_type = list(
		/obj/item/clothing,
		/obj/item/storage/backpack,
		/obj/item/storage/belt,
		/obj/item/toy,
		/obj/item/stack/material,
	)
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/gear_painter/proc/gear_painter_operable, null))
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/gear_painter/proc/gear_painter_empty, "the machine is already loaded"))
	effect = /obj/machinery/gear_painter/proc/interaction_insert

/obj/machinery/gear_painter/proc/gear_painter_operable(mob/actor, atom/target, obj/item/held)
	return operable()

/obj/machinery/gear_painter/proc/gear_painter_empty(mob/actor, atom/target, obj/item/held)
	return !inserted

/obj/machinery/gear_painter/proc/interaction_insert(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I,/obj/item/stack/material/cyborg)) //Needs an exception for borg materials to avoid glitches.
		return TRUE
	act_message(user, null, others = span_notice("%U% inserts %I% into the Color Mate receptable."), item = I)
	user.drop_from_inventory(I)
	I.forceMove(src)
	own_set(src, "inserted", I)
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/gear_painter/proc/insert_mob(mob/victim, mob/user)
	if(inserted)
		return
	if(user)
		act_message(user, victim, others = span_warning("%U% stuffs %T% into [src]!"))
	victim.forceMove(src)
	own_set(src, "inserted", victim)

/obj/machinery/gear_painter/AllowDrop()
	return FALSE

/**
 * Old click_alt: `. = ..(); drop_item(user)` — the default alt-click behaviour always ran,
 * then the item was dropped regardless. Approximated: drop_item() now runs first and
 * declines, so the base alt-click default still runs after it (order reversed from the
 * original, which is not expected to matter here — drop_item() and the base alt-click
 * default don't interact).
 */
/datum/interaction/machine_alt/gear_painter_alt_drop
	id = "gear_painter_alt_drop"
	name = "Remove item"
	consumes_input = FALSE
	effect = /obj/machinery/gear_painter/proc/interaction_alt_drop

/obj/machinery/gear_painter/proc/interaction_alt_drop(mob/user, obj/item/held, datum/interaction/interaction)
	drop_item(user)
	return FALSE

/obj/machinery/gear_painter/proc/drop_item(mob/user)
	if(!oview(1,src))
		return
	if(!inserted)
		return
	to_chat(user, span_notice("You remove [inserted] from [src]"))
	inserted.forceMove(drop_location())
	if(isliving(user))
		user.put_in_hands(inserted)
	own_take(src, "inserted")
	update_icon()
	SStgui.update_uis(src)

DECLARE_UI(/obj/machinery/gear_painter, "ColorMate")

UI_DATA_REPLACE(/obj/machinery/gear_painter, "activemode=active_mode", "buildhue=build_hue:num", "buildsat=build_sat:num", "buildval=build_val:num", "merge:ui_data_obj_machinery_gear_painter{matrixcolors:list,temp:text,item_name:text,item_sprite:text,item_preview:text}")

/// The computed part of /obj/machinery/gear_painter's window data (declared on its UI_DATA row).
/obj/machinery/gear_painter/proc/ui_data_obj_machinery_gear_painter(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/obj/machinery/gear_painter/proc/color_chosen(datum/om/prompt/color/ask)
	if(ask.picked_color)
		activecolor = ask.picked_color
		SStgui.update_uis(src)

UI_ACT(/obj/machinery/gear_painter, "switch_modes", ui_act_switch_modes, UI_ARG_NUM("mode"))
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_switch_modes)
	if(!(inserted))
		return
	active_mode = params["mode"]
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "choose_color", ui_act_choose_color)
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_choose_color)
	if(!(inserted))
		return
	om_ask(ui.user, /datum/om/prompt/color, PROC_REF(color_chosen), default = activecolor, title = "ColorMate colour picking", message = "Choose a color: ", requires = PROMPT_USABLE)
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "paint", ui_act_paint)
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_paint)
	if(!(inserted))
		return
	if(!do_paint(ui.user))
		return TRUE
	temp = "Painted Successfully!"
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "drop", ui_act_drop)
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_drop)
	if(!(inserted))
		return
	temp = ""
	drop_item(ui.user)
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "clear", ui_act_clear)
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_clear)
	if(!(inserted))
		return
	inserted.remove_atom_colour(FIXED_COLOUR_PRIORITY)
	play_sfx(src, SFX_EFFECTS_SPRAY3)
	temp = "Cleared Successfully!"
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "set_matrix_color", ui_act_set_matrix_color, UI_ARG_NUM("color"), UI_ARG_NUM("value"))
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_set_matrix_color)
	if(!(inserted))
		return
	color_matrix_last[params["color"]] = params["value"]
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "set_matrix_string", ui_act_set_matrix_string, UI_ARG_TEXT("value"))
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_set_matrix_string)
	if(!(inserted))
		return
	if(params["value"])
		var/list/colours = splittext(params["value"], ",")
		if(colours.len > 12)
			colours.Cut(13)
		for(var/i = 1, i <= colours.len, i++)
			var/number = text2num(colours[i])
			if(isnum(number))
				color_matrix_last[i] = clamp(number, -10, 10)
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "set_hue", ui_act_set_hue, UI_ARG_NUM("buildhue", 0, 360))
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_set_hue)
	if(!(inserted))
		return
	build_hue = params["buildhue"]
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "set_sat", ui_act_set_sat, UI_ARG_NUM("buildsat", -10, 10))
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_set_sat)
	if(!(inserted))
		return
	build_sat = params["buildsat"]
	return TRUE

UI_ACT(/obj/machinery/gear_painter, "set_val", ui_act_set_val, UI_ARG_NUM("buildval", -10, 10))
UI_ACT_PROC(/obj/machinery/gear_painter, ui_act_set_val)
	if(!(inserted))
		return
	build_val = params["buildval"]
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
