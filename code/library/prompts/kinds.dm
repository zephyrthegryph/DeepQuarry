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
	/// A radial ring around `anchor` (default: the answerer) instead of a window.
	var/radial = FALSE
	/// Where the radial ring is drawn.
	var/atom/anchor
	/// The radial ring's radius in pixels (null: the ring's own).
	var/radius
	/// The radial ring shows each choice's name as a tooltip.
	var/tooltips = FALSE

/datum/prompt/choice/refusal(given)
	if(isnull(given) || !(given in choices))
		return "that is not one of the choices"
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
	var/id = "defmenu_[REF(user)]_[REF(where)]"
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
	rel_set(menu, nameof(menu.anchor), where)
	menu.check_screen_border(user)
	menu.set_choices(choices, tooltips)
	rel_set(menu, nameof(menu.prompt), src)
	menu.show_to(user)
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
