/// kind yes_no, and any choice shown as buttons.
/datum/tgui_alert/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_alert/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_alert/prompt/set_choice(choice)
	. = ..()
	if(prompt && !isnull(src.choice))
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_answer(P, P.answer_of_button(src.choice))

/datum/tgui_alert/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	qdel(src) // ALLOW(lifecycle): a tgui input is deleted when its window closes, nothing else owns it

/// A list window.
/datum/tgui_list_input/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_list_input/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_list_input/prompt/set_choice(choice)
	. = ..()
	if(prompt && !isnull(src.choice))
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_answer(P, src.choice)

/datum/tgui_list_input/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	qdel(src) // ALLOW(lifecycle): a tgui input is deleted when its window closes, nothing else owns it

/// kind text.
/datum/tgui_input_text/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_input_text/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_input_text/prompt/set_entry(entry)
	. = ..()
	if(prompt && !isnull(src.entry))
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_answer(P, src.entry)

/datum/tgui_input_text/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	qdel(src) // ALLOW(lifecycle): a tgui input is deleted when its window closes, nothing else owns it

/// kind number.
/datum/tgui_input_number/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_input_number/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_input_number/prompt/set_entry(entry)
	. = ..()
	if(prompt && !isnull(src.entry))
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_answer(P, src.entry)

/datum/tgui_input_number/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	qdel(src) // ALLOW(lifecycle): a tgui input is deleted when its window closes, nothing else owns it

/// kind color.
/datum/tgui_color_picker/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_color_picker/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_color_picker/prompt/set_choice(choice)
	. = ..()
	if(prompt && !isnull(src.choice))
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_answer(P, src.choice)

/datum/tgui_color_picker/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	qdel(src) // ALLOW(lifecycle): a tgui input is deleted when its window closes, nothing else owns it

/// kind checklist.
/datum/tgui_checkbox_input/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_checkbox_input/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_checkbox_input/prompt/set_choices(list/selections)
	. = ..()
	if(prompt && !isnull(src.choices))
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_answer(P, src.choices)

/datum/tgui_checkbox_input/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	qdel(src) // ALLOW(lifecycle): a tgui input is deleted when its window closes, nothing else owns it

/// kind bitfield: submit answers the value; cancel or close cancels.
/datum/tgui_bitfield_input/prompt
	var/datum/prompt/prompt

CAPABILITIES(/datum/tgui_bitfield_input/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/tgui_bitfield_input/prompt/ui_act_submit(datum/act/op/A)
	// Answer before the window closes: closing it means cancel.
	if(!prompt)
		return ..()
	var/datum/prompt/P = prompt
	rel_clear(src, nameof(prompt))
	prompt_window_answer(P, value)
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_bitfield_input/prompt/tgui_close(mob/user)
	. = ..()
	if(prompt)
		var/datum/prompt/P = prompt
		rel_clear(src, nameof(prompt))
		prompt_window_closed(P)
	qdel(src) // ALLOW(lifecycle): a tgui input is deleted when its window closes, nothing else owns it

/// A radial ring that answers the prompt which opened it (kind choice with radial = TRUE).
/datum/radial_menu/prompt
	var/datum/prompt/prompt
	/// The key GLOB.radial_menus holds it under: asking again while it is open toggles it shut.
	var/menu_id

CAPABILITIES(/datum/radial_menu/prompt)
	ref_one(nameof(prompt), /datum/prompt)

/datum/radial_menu/prompt/element_chosen(choice_id, mob/user)
	var/answer = LAZYACCESS(choices_values, choice_id)
	if(isnull(answer))
		return
	var/datum/prompt/P = prompt
	rel_clear(src, nameof(prompt))
	dismiss()
	if(P)
		prompt_window_answer(P, answer)

/datum/radial_menu/prompt/close_menu()
	var/datum/prompt/P = prompt
	rel_clear(src, nameof(prompt))
	dismiss()
	if(P)
		prompt_window_closed(P)

/// Takes the ring off screen and deletes it.
/datum/radial_menu/prompt/proc/dismiss()
	if(menu_id && GLOB.radial_menus[menu_id] == src)
		GLOB.radial_menus -= menu_id
	hide()
	qdel(src) // ALLOW(lifecycle): the ring is deleted when it is dismissed, nothing else owns it
