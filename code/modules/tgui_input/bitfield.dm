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

CAPABILITIES(/datum/tgui_bitfield_input)
	interface("BitfieldInput", state = nameof(GLOB.tgui_always_state))
	op("toggle", ui_act("toggle", arg("bit", num())), then(PROC_REF(ui_act_toggle)))
	op("submit", ui_act("submit"), then(PROC_REF(ui_act_submit)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))

/datum/tgui_bitfield_input/ui_title(mob/user)
	return title

/datum/tgui_bitfield_input/tgui_close(mob/user)
	. = ..()
	closed = TRUE

/// /datum/tgui_bitfield_input's window data.
/datum/tgui_bitfield_input/ui_data(datum/act/eval/A)
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

/datum/tgui_bitfield_input/proc/ui_act_toggle(datum/act/op/A, bit_arg)
	var/bit = bit_arg
	if(!isnum(bit))
		return
	if(!(allowed_edit_field & bit))
		return
	if(value & bit)
		value &= ~bit
	else
		value |= bit
	return TRUE

/datum/tgui_bitfield_input/proc/ui_act_submit(datum/act/op/A)
	submitted = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_bitfield_input/proc/ui_act_cancel(datum/act/op/A)
	value = initial_value
	submitted = FALSE
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE
