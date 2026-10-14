/datum/prompt/yes_no/present(mob/user)
	var/datum/tgui_alert/prompt/alert = new(user, question, title || "Confirm", no_first ? list(no_text, yes_text) : list(yes_text, no_text), timeout, TRUE, GLOB.tgui_always_state)
	rel_set(alert, nameof(alert.prompt), src)
	alert.tgui_interact(user)
	return alert


/datum/prompt/text/present(mob/user)
	var/datum/tgui_input_text/prompt/box = new(user, question, title || "Text Input", default, max_len, multiline, encode, timeout, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box


/datum/prompt/number/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, round_entry && isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box


/datum/prompt/dismiss()
	var/datum/shown = window
	if(istype(shown, /datum/tgui_modal/prompt))
		return dismiss_inline()
	rel_clear(src, nameof(window))
	if(shown && !QDELETED(shown))
		SStgui.close_uis(shown)


/datum/prompt/focus_transport(mob/user, datum/shown)
	if(istype(shown, /datum/tgui_modal/prompt))
		// an inline question is shown in the window of the holder that asked
		var/datum/tgui_modal/prompt/modal = shown
		shown = modal.owning_source()
		if(isnull(shown) || QDELETED(shown))
			return
	var/datum/tgui/ui = SStgui.get_open_ui(user, shown)
	if(!ui)
		return
	ui.send_full_update()
	var/datum/tgui_window/shown_window = ui.window()
	if(shown_window)
		winset(user, shown_window.id, "focus=true")
