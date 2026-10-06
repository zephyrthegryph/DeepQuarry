// The prompt kinds the library declares (doc/rewrite/final_api.html, section 13 "Requests, prompts and workflows (X3)": text, number, list, checklist, yes_no,
// color, bitfield...). The base and the three the engine uses (yes_no, text, number) are code/engine/parts/prompts.dm; each kind here brings its value's
// normaliser and refusal, and the window it is shown in (code/engine/present/prompt_windows.dm). All answer in the uniform `value`.
//
//   asks(/datum/prompt/choice, fields = list("question" = "Which?", "choices" = list("red", "blue")), step = "pick")
//   asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(skins)), "radial" = TRUE))     // x(datum/act/op/A) returns the list
//   asks(/datum/prompt/color, fields = list("question" = "Pick a new color", "default" = nameof(color)))
//   asks(/datum/prompt/checklist, fields = list("choices" = list("a", "b", "c"), "min_picks" = 1, "max_picks" = 2))
//   asks(/datum/prompt/bitfield, fields = list("bitfield" = "obj_flags", "default" = nameof(obj_flags)))
//
// A kind with its own question (a type under it: /datum/prompt/choice/skin) overrides prepare(datum/act/A) to fill its fields from the asking op.

/// One of a list. `choices` is a list of texts, or text -> icon/image for a radial ring; the answer is one of its keys.
/datum/prompt/choice
	question = "Choose one."
	timeout = 60 SECONDS
	/// What to pick from: the answer is one of these (an assoc list's keys; its values are the icons of a radial ring).
	var/list/choices
	/// The list window opens on this one.
	var/default
	/// A few choices as buttons instead of a list.
	var/buttons = FALSE
	/// Inline only (asks(..., "inline" = TRUE)): the choices are shown as a grid of images ("bento"), or of spritesheet classes ("spritesheet"), and the
	/// window answers with the index of one: the old bento modals. Null: a dropdown.
	var/bento
	/// A radial ring around `anchor` (default: the answerer) instead of a window.
	var/radial = FALSE
	/// Where the radial ring is drawn.
	var/atom/anchor
	/// The radial ring's radius in pixels (null: the ring's own).
	var/radius
	/// The radial ring shows each choice's name as a tooltip.
	var/tooltips = FALSE
	/// The ring's slice icon state.
	var/radial_slice_icon = "radial_slice"
	/// A ring with one choice answers with it at once, without drawing (default off: the old radial kind turned it on).
	var/autopick_single_option = FALSE
	/// The ring's entries slide out when it opens.
	var/entry_animation = TRUE
	/// Hovering an entry picks it.
	var/click_on_hover = FALSE
	/// Draw the ring around the answerer, offset toward the anchor.
	var/user_space = FALSE
	/// Drop an answer given out of reach (in_range) of the anchor, or of the subject when there is none.
	var/require_near = FALSE
	/// The key GLOB.radial_menus holds the ring under (default: the answerer and the anchor); asking again with the same key closes the open ring.
	var/uniqueid

/datum/prompt/choice/inline_type()
	if(radial)
		return null
	if(bento)
		return bento == "spritesheet" ? "bentospritesheet" : "bento"
	return "choice"

/datum/prompt/choice/inline_preprocess(answer)
	return bento ? (text2num(answer) || 0) : answer

/// A dropdown answers with one of the choices; a bento grid answers with the index of one (its value is the choice).
/datum/prompt/choice/inline_answer(answer)
	if(bento)
		return (isnum(answer) && answer >= 1 && answer <= length(choices)) ? choices[answer] : null
	return (answer in choices) ? answer : null

/datum/prompt/choice/inline_data(list/data)
	if(bento)
		data["choices"] = choices.Copy()
		data["value"] = default ? choices.Find(default) : 0
		return
	var/list/names = list()
	for(var/name in choices)
		names += "[name]"
	data["choices"] = names
	data["value"] = default

/datum/prompt/choice/refusal(given)
	if(isnull(given) || !(given in choices))
		return "that is not one of the choices"
	return null

/// A ring with a single choice and autopick_single_option answers itself, after the request has finished opening.
/datum/prompt/choice/begin()
	var/mob/user = answerer
	if(radial && autopick_single_option && length(choices) == 1 && istype(user) && user.client)
		after(src, 0, TYPE_PROC_REF(/datum/prompt/choice, autopick), key = "request_begin")
		return
	return ..()

/datum/prompt/choice/proc/autopick()
	if(is_open())
		prompt_window_answer(src, choices[1])

/// require_near: an answer given out of reach of the anchor (else the subject) is dropped.
/datum/prompt/choice/recheck_extra()
	if(!require_near)
		return null
	var/mob/user = answerer
	var/atom/where = anchor || subject || (isatom(owner) ? owner : null)
	if(where && user && !in_range(where, user))
		return "out of reach"
	return null

/datum/prompt/choice/present(mob/user)
	if(!length(choices))
		return null
	if(radial)
		return present_radial(user)
	if(buttons)
		var/datum/tgui_alert/prompt/alert = new(user, question, title || "Choose", choices, timeout, TRUE, GLOB.tgui_always_state)
		rel_set(alert, nameof(alert.prompt), src)
		alert.tgui_interact(user)
		return alert
	var/datum/tgui_list_input/prompt/list_window = new(user, question, title || "Select", choices, default, timeout, GLOB.tgui_always_state)
	if(list_window.invalid)
		qdel(list_window) // ALLOW(lifecycle): a window that was never shown is dropped, nothing owns it yet
		return null
	rel_set(list_window, nameof(list_window.prompt), src)
	list_window.tgui_interact(user)
	return list_window

/datum/prompt/choice/proc/present_radial(mob/user)
	var/atom/where = anchor || user
	var/id = uniqueid || "defmenu_[REF(user)]_[REF(where)]"
	var/datum/radial_menu/prompt/open_menu = GLOB.radial_menus[id]
	if(open_menu)
		// asking again while it is open toggles it shut (and this question with it)
		open_menu.close_menu()
		return null
	var/datum/radial_menu/prompt/menu = new
	menu.menu_id = id
	GLOB.radial_menus[id] = menu
	if(radius)
		menu.radius = radius
	menu.entry_animation = entry_animation
	menu.radial_slice_icon = radial_slice_icon
	rel_set(menu, nameof(menu.anchor), user_space ? user : where)
	menu.check_screen_border(user)
	menu.set_choices(choices, tooltips, click_on_hover)
	rel_set(menu, nameof(menu.prompt), src)
	var/offset_x = 0
	var/offset_y = 0
	if(user_space)
		var/turf/user_turf = get_turf(user)
		var/turf/anchor_turf = get_turf(where)
		offset_x = (anchor_turf.x - user_turf.x) * ICON_SIZE_X + where.pixel_x - user.pixel_x
		offset_y = (anchor_turf.y - user_turf.y) * ICON_SIZE_Y + where.pixel_y - user.pixel_y
	menu.show_to(user, offset_x, offset_y)
	log_input("Input: [key_name(user)] was shown a radial menu ([type]) on [where].")
	return menu

/datum/prompt/choice/dismiss()
	var/datum/shown = window
	if(!istype(shown, /datum/radial_menu/prompt))
		return ..()
	rel_clear(src, nameof(window))
	var/datum/radial_menu/prompt/menu = shown
	rel_clear(menu, nameof(menu.prompt))
	if(!QDELETED(menu))
		menu.dismiss()

/// A colour: the answer is "#rrggbb".
/datum/prompt/color
	question = "Pick a color."
	timeout = 60 SECONDS
	/// What the picker starts on.
	var/default = "#000000"

/datum/prompt/color/normalize(given)
	var/hex = sanitize_hexcolor(given, "invalid") // a null default would be taken for none given
	return hex == "invalid" ? null : hex

/datum/prompt/color/refusal(given)
	return isnull(given) ? "that is not a color" : null

/datum/prompt/color/present(mob/user)
	var/datum/tgui_color_picker/prompt/picker = new(user, question, title || "Pick a color", sanitize_hexcolor(default), timeout, TRUE, GLOB.tgui_always_state)
	rel_set(picker, nameof(picker.prompt), src)
	picker.tgui_interact(user)
	return picker

/// Several of a list: the answer is the list of the ticked choices.
/datum/prompt/checklist
	question = "Select any."
	timeout = 60 SECONDS
	var/list/choices
	/// The fewest and most that may be ticked.
	var/min_picks = 0
	var/max_picks = 50

/datum/prompt/checklist/normalize(given)
	if(!islist(given))
		return null
	var/list/ticked = list()
	for(var/entry in choices)
		if(entry in given)
			ticked += entry
	return ticked

/datum/prompt/checklist/refusal(given)
	if(!islist(given))
		return "that is not a list of choices"
	if(length(given) < min_picks)
		return "pick at least [min_picks]"
	if(length(given) > max_picks)
		return "pick at most [max_picks]"
	return null

/datum/prompt/checklist/present(mob/user)
	if(!length(choices))
		return null
	var/datum/tgui_checkbox_input/prompt/boxes = new(user, question, title || "Select", choices, min_picks, max_picks, timeout, GLOB.tgui_always_state)
	rel_set(boxes, nameof(boxes.prompt), src)
	boxes.tgui_interact(user)
	return boxes

/// Flag checkboxes: `bitfield` names the flag set (get_valid_bitflags()), `default` is the value, `editable` the mask of flags that may change; the answer is
/// the new value.
/datum/prompt/bitfield
	question = "Set the flags."
	timeout = 5 MINUTES
	var/bitfield
	var/default = 0
	var/editable = ALL

/datum/prompt/bitfield/normalize(given)
	if(!isnum(given))
		return null
	return (given & editable) | (default & ~editable)

/datum/prompt/bitfield/refusal(given)
	return isnum(given) ? null : "that is not a set of flags"

/datum/prompt/bitfield/present(mob/user)
	var/list/flags = get_valid_bitflags(bitfield)
	if(!length(flags))
		return null
	var/datum/tgui_bitfield_input/prompt/boxes = new(user, title || question, flags, default, editable, timeout)
	rel_set(boxes, nameof(boxes.prompt), src)
	boxes.tgui_interact(user)
	return boxes

/// The ColorMate window: `preview` is the atom painted in place, or a path (a preview is made for the window and deleted with it). The
/// answer is the colour matrix.
/datum/prompt/colormatrix
	question = "Pick a color matrix."
	timeout = 30 MINUTES
	var/preview
	var/list/default
	var/matrix_only = FALSE
	/// The tgui state the window uses (null: always).
	var/datum/tgui_state/ui_state

/datum/prompt/colormatrix/present(mob/user)
	if(!ispath(preview) && !isatom(preview))
		return null
	var/was_path = ispath(preview)
	var/atom/movable/shown = was_path ? new preview : preview
	var/list/start = length(default) ? default : DEFAULT_COLORMATRIX
	if(length(start) < 12)
		start = start.Copy()
		start.len = 12
	var/datum/tgui_input_colormatrix/prompt/window = new(user, question, title || "Matrix Recolor", shown, start, matrix_only, timeout || 30 MINUTES, ui_state || GLOB.tgui_always_state, was_path)
	rel_set(window, nameof(window.prompt), src)
	window.tgui_interact(user)
	return window

/datum/prompt/colormatrix/refusal(given)
	return islist(given) ? null : "that is not a colour matrix"

/// kind colormatrix: the ColorMate window answers its matrix.
/datum/tgui_input_colormatrix/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_input_colormatrix/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_input_colormatrix/prompt/set_entry(entry)
	. = ..()
	if(prompt && !isnull(src.entry))
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_answer(P, src.entry)

/datum/tgui_input_colormatrix/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	spent(src, user)

/datum/tgui_input_colormatrix/prompt/on_destroy(force)
	if(was_path && target())
		destroyed(target())
	..()
