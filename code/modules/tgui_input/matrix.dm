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
	var/tmp/atom/movable/target
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
	rel_set(src, nameof(target), target)
	src.title = title
	src.state_static = ui_state
	src.was_path = was_path
	src.matrix_only = matrix_only
	if(matrix_only)
		active_mode = COLORMATE_MATRIX
	if (timeout)
		src.timeout = timeout
		EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
		expire(timeout)
	color_matrix_last = default.Copy()

/**
 * Waits for a user's response to the tgui_input_colormatrix's prompt before returning. Returns early if
 * the window was closed by the user.
 */
/datum/tgui_input_colormatrix/proc/wait()
	while (!entry && !closed && !QDELETED(src))
		stoplag(1) // ALLOW(scheduler): tgui_input is the blocking prompt API itself: it waits on the player by design

CAPABILITIES(/datum/tgui_input_colormatrix)
	interface("ColorMate")
	op("switch_modes", ui_act("switch_modes", arg("mode", num())), then(PROC_REF(ui_act_switch_modes)))
	op("choose_color", ui_act("choose_color"), asks(/datum/prompt/color/matrix_active_colour, fields = list("title" = computed(PROC_REF(choose_color_title)), "question" = "Choose a color: ", "default" = computed(PROC_REF(active_color_default))), step = "color"), then(PROC_REF(ui_act_choose_color)))
	op("paint", ui_act("paint"), then(PROC_REF(ui_act_paint)))
	op("drop", ui_act("drop"), then(PROC_REF(ui_act_drop)))
	op("clear", ui_act("clear"), then(PROC_REF(ui_act_clear)))
	op("set_matrix_color", ui_act("set_matrix_color", arg("color", num()), arg("value", num())), then(PROC_REF(ui_act_set_matrix_color)))
	op("set_matrix_string", ui_act("set_matrix_string", arg("value", schema_text(4096))), then(PROC_REF(ui_act_set_matrix_string)))
	op("set_hue", ui_act("set_hue", arg("buildhue", num(0, 360))), then(PROC_REF(ui_act_set_hue)))
	op("set_sat", ui_act("set_sat", arg("buildsat", num(-10, 10))), then(PROC_REF(ui_act_set_sat)))
	op("set_val", ui_act("set_val", arg("buildval", num(-10, 10))), then(PROC_REF(ui_act_set_val)))

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

/datum/tgui_input_colormatrix/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["activemode"] = active_mode
	data["buildhue"] = build_hue
	data["buildsat"] = build_sat
	data["buildval"] = build_val
	var/list/merged_1 = ui_data_datum_tgui_input_colormatrix(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/tgui_input_colormatrix's window data.
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

/datum/tgui_input_colormatrix/proc/ui_act_switch_modes(datum/act/op/A, mode)
	if(matrix_only && active_mode < 3)
		return FALSE
	active_mode = mode
	return TRUE

/datum/tgui_input_colormatrix/proc/choose_color_title(datum/act/op/A)
	return "[title] colour picking"

/datum/tgui_input_colormatrix/proc/active_color_default(datum/act/op/A)
	return activecolor

/datum/tgui_input_colormatrix/proc/ui_act_choose_color(datum/act/op/A)
	activecolor = A.step_value("color")
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_paint(datum/act/op/A)
	var/mob/user = A.actor
	if(!do_paint(user, !was_path))
		return TRUE
	set_entry(color_matrix_last)
	temp = "Painted Successfully!"
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_drop(datum/act/op/A)
	temp = ""
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_clear(datum/act/op/A)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	target().remove_atom_colour(FIXED_COLOUR_PRIORITY)
	play_sfx(src, SFX_EFFECTS_SPRAY3)
	temp = "Cleared Successfully!"
	color_matrix_last = DEFAULT_COLORMATRIX
	update_tgui_static_data(user, ui)
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_set_matrix_color(datum/act/op/A, color, value)
	color_matrix_last[color] = value
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_set_matrix_string(datum/act/op/A, value)
	if(value)
		var/list/colours = splittext(value, ",")
		if(length(colours) > 12)
			colours.Cut(13)
		for(var/i = 1, i <= length(colours), i++)
			var/number = text2num(colours[i])
			if(isnum(number))
				color_matrix_last[i] = clamp(number, -10, 10)
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_set_hue(datum/act/op/A, buildhue)
	build_hue = buildhue
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_set_sat(datum/act/op/A, buildsat)
	build_sat = buildsat
	return TRUE

/datum/tgui_input_colormatrix/proc/ui_act_set_val(datum/act/op/A, buildval)
	build_val = buildval
	return TRUE

/datum/prompt/color/matrix_active_colour
	timeout = 0

/datum/prompt/color/matrix_active_colour/normalize(given)
	return given

/datum/prompt/color/matrix_active_colour/refusal(given)
	return null

/datum/prompt/color/matrix_active_colour/present(mob/user)
	var/datum/tgui_color_picker/prompt/picker = new(user, question, title || "Pick a color", default || "#000000", timeout, TRUE, GLOB.tgui_always_state)
	rel_set(picker, nameof(picker.prompt), src)
	picker.tgui_interact(user)
	return picker

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

/// A shared (registered) definition/flyweight: never cleared.
/datum/tgui_input_colormatrix/proc/state() as /datum/tgui_state
	return state_static

/// The target this refers to (a relation view: null once that is deleted).
/datum/tgui_input_colormatrix/proc/target() as /atom/movable
	return target
