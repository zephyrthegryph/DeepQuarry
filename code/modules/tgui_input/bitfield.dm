/datum/tgui_bitfield_input
	var/title
	// Map of flag name → flag value (the bit constant).
	var/list/bitflags
	// Mask of which flags the user is allowed to toggle. Read-only flags
	// are still displayed but their checkbox is disabled.
	var/allowed_edit_field
	// Bitfield being edited.
	var/value
	// Bitfield as it was when the window opened, for the "Cancel" path.
	var/initial_value
	EXPIRY_DECLARE(start_time)
	var/timeout
	var/submitted = FALSE
	var/closed = FALSE

/datum/tgui_bitfield_input/New(mob/user, title, list/bitflags, current_value, allowed_edit_field, timeout)
	src.title = title
	src.bitflags = bitflags
	src.value = current_value
	src.initial_value = current_value
	src.allowed_edit_field = allowed_edit_field
	if(timeout)
		src.timeout = timeout
		EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
		om_qdel_after(src, timeout)

/datum/tgui_bitfield_input/proc/wait()
	while(!submitted && !closed && !QDELETED(src))
		stoplag(1) // ALLOW(scheduler): tgui_input is the blocking prompt API itself: it waits on the player by design

DECLARE_UI_STATE(/datum/tgui_bitfield_input, GLOB.tgui_always_state)

DECLARE_UI(/datum/tgui_bitfield_input, "BitfieldInput")

/datum/tgui_bitfield_input/ui_title(mob/user)
	return title

/datum/tgui_bitfield_input/tgui_close(mob/user)
	. = ..()
	closed = TRUE

UI_DATA_REPLACE(/datum/tgui_bitfield_input, "merge:ui_data_datum_tgui_bitfield_input{title:text,flags:list}")

/// The computed part of /datum/tgui_bitfield_input's window data (declared on its UI_DATA row).
/datum/tgui_bitfield_input/proc/ui_data_datum_tgui_bitfield_input(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/flags = list()
	for(var/name in bitflags)
		var/bit = bitflags[name]
		flags += list(list(
			"name" = name,
			"bit" = bit,
			"checked" = !!(value & bit),
			"editable" = !!(allowed_edit_field & bit),
		))
	return list(
		"title" = title,
		"flags" = flags,
	)

UI_ACT(/datum/tgui_bitfield_input, "toggle", ui_act_toggle, UI_ARG_NUM("bit"))
UI_ACT_PROC(/datum/tgui_bitfield_input, ui_act_toggle)
	var/bit = params["bit"]
	if(!isnum(bit))
		return
	if(!(allowed_edit_field & bit))
		return
	if(value & bit)
		value &= ~bit
	else
		value |= bit
	return TRUE

UI_ACT(/datum/tgui_bitfield_input, "submit", ui_act_submit)
UI_ACT_PROC(/datum/tgui_bitfield_input, ui_act_submit)
	submitted = TRUE
	SStgui.close_uis(src)
	return TRUE

UI_ACT(/datum/tgui_bitfield_input, "cancel", ui_act_cancel)
UI_ACT_PROC(/datum/tgui_bitfield_input, ui_act_cancel)
	value = initial_value
	submitted = FALSE
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE
