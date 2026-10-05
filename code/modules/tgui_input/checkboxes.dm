/// Window for tgui_input_checkboxes
/datum/tgui_checkbox_input
	/// Title of the window
	var/title
	/// Message to display
	var/message
	/// List of items to display
	var/list/items
	/// List of selected items
	var/list/choices
	/// Time when the input was created
	EXPIRY_DECLARE(start_time)
	/// Timeout for the input
	var/timeout
	/// Whether the input was closed
	var/closed
	/// Minimum number of checkboxes that must be checked
	var/min_checked
	/// Maximum number of checkboxes that can be checked
	var/max_checked
	/// The TGUI UI state that will be returned in ui_state(). Default: always_state
	var/tmp/datum/tgui_state/state_static

/datum/tgui_checkbox_input/New(mob/user, message, title, list/items, min_checked, max_checked, timeout, ui_state)
	src.title = title
	src.message = message
	src.items = items.Copy()
	src.min_checked = min_checked
	src.max_checked = max_checked
	src.state_static = ui_state

	if (timeout)
		src.timeout = timeout
		EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
		om_qdel_after(src, timeout)

/datum/tgui_checkbox_input/proc/wait()
	while (!closed && !QDELETED(src))
		stoplag(1) // ALLOW(scheduler): tgui_input is the blocking prompt API itself: it waits on the player by design

DECLARE_UI(/datum/tgui_checkbox_input, "CheckboxInput")

/datum/tgui_checkbox_input/tgui_close(mob/user)
	. = ..()
	closed = TRUE

/datum/tgui_checkbox_input/tgui_state(mob/user)
	return state()

UI_DATA_REPLACE(/datum/tgui_checkbox_input, "merge:ui_data_datum_tgui_checkbox_input{timeout:num}")

/// The computed part of /datum/tgui_checkbox_input's window data (declared on its UI_DATA row).
/datum/tgui_checkbox_input/proc/ui_data_datum_tgui_checkbox_input(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	if(timeout)
		data["timeout"] = CLAMP01((timeout - (world.time - start_time) - 1 SECONDS) / (timeout - 1 SECONDS))

	return data

/datum/tgui_checkbox_input/tgui_static_data(mob/user)
	var/list/data = list()

	data["items"] = items
	data["min_checked"] = min_checked
	data["max_checked"] = max_checked
	data["large_buttons"] = user.read_preference(/datum/preference/toggle/tgui_large_buttons)
	data["message"] = message
	data["swapped_buttons"] = !user.read_preference(/datum/preference/toggle/tgui_swapped_buttons)
	data["title"] = title

	return data

UI_ACT(/datum/tgui_checkbox_input, "submit", ui_act_submit, UI_ARG_LIST("entry"))
UI_ACT_PROC(/datum/tgui_checkbox_input, ui_act_submit)
	var/list/selections = params["entry"]
	if(length(selections) >= min_checked && length(selections) <= max_checked)
		var/list/valid_selections = list()
		for(var/raw_entry in selections)
			if(raw_entry in items)
				valid_selections += raw_entry
		set_choices(valid_selections)
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

UI_ACT(/datum/tgui_checkbox_input, "cancel", ui_act_cancel)
UI_ACT_PROC(/datum/tgui_checkbox_input, ui_act_cancel)
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_checkbox_input/proc/set_choices(list/selections)
	src.choices = selections.Copy()

/// A shared (registered) definition/flyweight: never cleared.
/datum/tgui_checkbox_input/proc/state() as /datum/tgui_state
	return state_static
