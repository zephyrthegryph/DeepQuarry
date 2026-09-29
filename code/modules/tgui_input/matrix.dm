/**
 * Creates a TGUI window with a matrix input. Returns the user's response as list | null.
 *
 * This proc should be used to create windows for matrix entry that the caller will wait for a response from.
 * If tgui fancy chat is turned off: Will return a normal input. If a max or min value is specified, will
 * validate the input inside the UI and ui_act.
 *
 * Arguments:
 * * user - The user to show the matrix input to.
 * * message - The content of the matrix input, shown in the body of the TGUI window.
 * * title - The title of the matrix input modal, shown on the top of the TGUI window.
 * * target - The target where the matrix will be applied to.
 * * matrix_only - uses a static mode and allows fallback to non tgui. Only use this if you only care about the return value.
 * * default - The default (or current) value, shown as a placeholder. Users can press refresh with this.
 * * timeout - The timeout of the matrix input, after which the modal will close and qdel itself. Set to zero for no timeout.
 */
/proc/tgui_input_colormatrix(mob/user, message, title = "Matrix Recolor", atom/movable/target, list/default = DEFAULT_COLORMATRIX, matrix_only = FALSE, timeout = 30 MINUTES, ui_state = GLOB.tgui_always_state)
	if (!user)
		user = usr
	if (!istype(user))
		if (istype(user, /client))
			var/client/client = user
			user = client.mob
		else
			return null

	if (isnull(user.client))
		return null

	if(!islist(default) || !length(default))
		default = DEFAULT_COLORMATRIX

	if(length(default) < 12)
		default.len = 12

	// legacy browser-modal color_matrix_picker fallback removed.
	// Without a valid target (atom or path) there's nothing to preview, so
	// abort. The tgui_input_mode preference is ignored here — TGUI is the
	// only matrix-input UI.
	if(!ispath(target) && !isatom(target))
		return null
	var/was_path = ispath(target)
	var/atom/movable/real_target = was_path ? new target : target
	var/datum/tgui_input_colormatrix/matrix_input = new(user, message, title, real_target, default, matrix_only, timeout, ui_state, was_path)
	matrix_input.tgui_interact(user)
	matrix_input.wait()
	// We only created it for the preview
	if(was_path)
		qdel(real_target)
	if (matrix_input)
		. = matrix_input.entry
		qdel(matrix_input)

/**
 * # tgui_input_colormatrix
 *
 * Datum used for instantiating and using a TGUI-controlled color matrix input that prompts the user with
 * a message and has an input for color matrix entry.
 */
/datum/tgui_input_colormatrix
	/// Boolean field describing if the tgui_input_colormatrix was closed by the user.
	var/closed
	/// The entry that the user has return_typed in.
	var/entry
	/// The prompt's body, if any, of the TGUI window.
	var/message
	/// The target for our display
	var/tmp/target_handle
	/// The base color matrix
	var/list/default
	/// static mode users can't change
	var/matrix_only
	/// our default list should not be edited as it might be a reference
	var/list/color_matrix_last
	/// The time at which the number input was created, for displaying timeout progress.
	EXPIRY_DECLARE(start_time)
	/// The lifespan of the color matrix input, after which the window will close and delete itself.
	var/timeout
	/// The title of the TGUI window
	var/title
	/// The TGUI UI state that will be returned in ui_state(). Default: always_state
	var/tmp/datum/tgui_state/state_static
	/// Internal var to remember if we only passed a path before
	var/was_path

	var/activecolor = "#FFFFFF"
	var/active_mode = COLORMATE_HSV

	var/build_hue = 0
	var/build_sat = 1
	var/build_val = 1

	/// Minimum lightness for normal mode
	var/minimum_normal_lightness = 50
	/// Minimum lightness for matrix mode, tested using 4 test colors of full red, green, blue, white.
	var/minimum_matrix_lightness = 75
	/// Minimum matrix tests that must pass for something to be considered a valid color (see above)
	var/minimum_matrix_tests = 2
	/// Temporary messages
	var/temp

/datum/tgui_input_colormatrix/New(mob/user, message, title, atom/movable/target, list/default, matrix_only, timeout, ui_state, was_path)
	src.default = default
	src.message = message
	src.target_handle = om_handle(target)
	src.title = title
	src.state_static = ui_state
	src.was_path = was_path
	src.matrix_only = matrix_only
	if(matrix_only)
		active_mode = COLORMATE_MATRIX
	if (timeout)
		src.timeout = timeout
		EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
		om_qdel_after(src, timeout)
	color_matrix_last = default.Copy()

/**
 * Waits for a user's response to the tgui_input_colormatrix's prompt before returning. Returns early if
 * the window was closed by the user.
 */
/datum/tgui_input_colormatrix/proc/wait()
	while (!entry && !closed && !QDELETED(src))
		stoplag(1) // ALLOW(scheduler): tgui_input waits on the player (prompts, S10)

DECLARE_UI(/datum/tgui_input_colormatrix, "ColorMate")

/datum/tgui_input_colormatrix/tgui_close(mob/user)
	. = ..()
	closed = TRUE

/datum/tgui_input_colormatrix/tgui_state(mob/user)
	return state()

/datum/tgui_input_colormatrix/tgui_static_data(mob/user)
	var/list/data = list()
	data["message"] = message
	data["title"] = title
	data["item_name"] = target().name
	data["item_sprite"] = icon2base64(get_flat_icon(target(),dir=SOUTH,no_anim=TRUE))
	data["matrix_only"] = matrix_only
	return data

UI_DATA_REPLACE(/datum/tgui_input_colormatrix, "activemode=active_mode", "buildhue=build_hue:num", "buildsat=build_sat:num", "buildval=build_val:num", "merge:ui_data_datum_tgui_input_colormatrix{matrixcolors:list,item_preview:text,temp:text,timeout:num}")

/// The computed part of /datum/tgui_input_colormatrix's window data (declared on its UI_DATA row).
/datum/tgui_input_colormatrix/proc/ui_data_datum_tgui_input_colormatrix(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["matrixcolors"] = list(
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
	data["item_preview"] = icon2base64(build_preview(user))
	if(temp)
		data["temp"] = temp
	if(timeout)
		data["timeout"] = CLAMP01((timeout - (world.time - start_time) - 1 SECONDS) / (timeout - 1 SECONDS))
	return data

UI_ACT(/datum/tgui_input_colormatrix, "switch_modes", ui_act_switch_modes, UI_ARG_NUM("mode"))
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_switch_modes)
	if(matrix_only && active_mode < 3)
		return FALSE
	active_mode = params["mode"]
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "choose_color", ui_act_choose_color)
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_choose_color)
	om_ask(ui.user, /datum/om/prompt/color, PROC_REF(color_chosen), title = "[title] colour picking", message = "Choose a color: ", default = activecolor, ui_refresh = src)
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "paint", ui_act_paint)
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_paint)
	if(!do_paint(ui.user, !was_path))
		return TRUE
	set_entry(color_matrix_last)
	temp = "Painted Successfully!"
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "drop", ui_act_drop)
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_drop)
	temp = ""
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "clear", ui_act_clear)
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_clear)
	target().remove_atom_colour(FIXED_COLOUR_PRIORITY)
	play_sfx(src, SFX_EFFECTS_SPRAY3)
	temp = "Cleared Successfully!"
	color_matrix_last = DEFAULT_COLORMATRIX
	update_tgui_static_data(ui.user, ui)
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "set_matrix_color", ui_act_set_matrix_color, UI_ARG_NUM("color"), UI_ARG_NUM("value"))
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_set_matrix_color)
	color_matrix_last[params["color"]] = params["value"]
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "set_matrix_string", ui_act_set_matrix_string, UI_ARG_TEXT("value"))
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_set_matrix_string)
	if(params["value"])
		var/list/colours = splittext(params["value"], ",")
		if(length(colours) > 12)
			colours.Cut(13)
		for(var/i = 1, i <= length(colours), i++)
			var/number = text2num(colours[i])
			if(isnum(number))
				color_matrix_last[i] = clamp(number, -10, 10)
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "set_hue", ui_act_set_hue, UI_ARG_NUM("buildhue", 0, 360))
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_set_hue)
	build_hue = params["buildhue"]
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "set_sat", ui_act_set_sat, UI_ARG_NUM("buildsat", -10, 10))
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_set_sat)
	build_sat = params["buildsat"]
	return TRUE

UI_ACT(/datum/tgui_input_colormatrix, "set_val", ui_act_set_val, UI_ARG_NUM("buildval", -10, 10))
UI_ACT_PROC(/datum/tgui_input_colormatrix, ui_act_set_val)
	build_val = params["buildval"]
	return TRUE

/datum/tgui_input_colormatrix/proc/color_chosen(datum/om/prompt/color/ask)
	activecolor = ask.picked_color

/datum/tgui_input_colormatrix/proc/set_entry(entry)
	src.entry = entry

/datum/tgui_input_colormatrix/proc/do_paint(mob/user, apply)
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
	if(apply)
		target().add_atom_colour(color_to_use, FIXED_COLOUR_PRIORITY)
		play_sfx(src, SFX_EFFECTS_SPRAY3)
		if(isanimal(target()))
			var/mob/living/simple_mob/M = target()
			M.has_recoloured = TRUE
		if(isrobot(target()))
			var/mob/living/silicon/robot/R = target()
			R.has_recoloured = TRUE
	return TRUE

/// Produces the preview image of the item, used in the UI, the way the color is not stacking is a sin.
/datum/tgui_input_colormatrix/proc/build_preview(mob/user)
	if(target()) //sanity
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
					return get_flat_icon(target(), dir=SOUTH, no_anim=TRUE)

			if(COLORMATE_TINT)
				if(!check_valid_color(activecolor, user))
					return get_flat_icon(target(), dir=SOUTH, no_anim=TRUE)

			if(COLORMATE_HSV)
				cm = color_matrix_hsv(build_hue, build_sat, build_val)
				color_matrix_last = cm
				if(!check_valid_color(cm, user))
					return get_flat_icon(target(), dir=SOUTH, no_anim=TRUE)

		var/cur_color = target().color
		target().color = null
		target().color = (active_mode == COLORMATE_TINT ? activecolor : cm)
		var/icon/preview = get_flat_icon(target(), dir=SOUTH, no_anim=TRUE)
		target().color = cur_color
		temp = ""

		. = preview

/datum/tgui_input_colormatrix/proc/check_valid_color(list/cm, mob/user)
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

/// DECLARE_REF(..., STATIC): a shared definition/flyweight, held strongly and never cleared.
/datum/tgui_input_colormatrix/proc/state() as /datum/tgui_state
	return state_static
DECLARE_REF(/datum/tgui_input_colormatrix, "state_static", STATIC, null)

/// LC-refs: the target this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/tgui_input_colormatrix/proc/target() as /atom/movable
	return om_resolve(target_handle)
