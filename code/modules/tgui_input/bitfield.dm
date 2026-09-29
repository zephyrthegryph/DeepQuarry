// TGUI bitfield input — replaces the legacy /datum/browser/modal/list_picker
// "checkboxes for each flag" dialog that input_bitfield() used to render
// in a browse() window.
//
// Used by:
//   - View Variables (vv) when editing a bitfield var
//   - permissionedit (admin rights flag editing)
//
// Returns the new bitfield value (an int) or null if the user cancelled.

// Replacement for the legacy /proc/input_bitfield. Same callsite shape
// (5+ positional args), same return type. Width/height/slide_color are
// kept for source compatibility but are no longer used (TGUI handles
// sizing/styling). `bitfield` is whatever the original first arg was
// — a path or string identifier that get_valid_bitflags resolves to
// a {name → bit} list. We forward it unchanged.
/proc/input_bitfield(mob/user, title, bitfield, current_value, width, height, slide_color, allowed_edit_field = ALL)
	return tgui_input_bitfield(user, title, bitfield, current_value, allowed_edit_field) // ALLOW(scheduler): the blocking prompt API itself (the non-tgui fallback om_prompt never uses)

/proc/tgui_input_bitfield(mob/user, title, bitfield_path, current_value, allowed_edit_field = ALL, timeout = 0)
	if(!user)
		user = usr
	if(!ismob(user))
		if(istype(user, /client))
			var/client/c = user
			user = c.mob
		else
			return null
	if(!user.client)
		return null
	var/list/bitflags = get_valid_bitflags(bitfield_path)
	if(!length(bitflags))
		return null
	var/datum/tgui_bitfield_input/input = new(user, title, bitflags, current_value, allowed_edit_field, timeout)
	input.tgui_interact(user)
	input.wait()
	if(QDELETED(input))
		return null
	. = input.submitted ? input.value : null
	qdel(input)

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
		stoplag(1) // ALLOW(scheduler): tgui_input waits on the player (prompts, S10)

DECLARE_UI_STATE(/datum/tgui_bitfield_input, GLOB.tgui_always_state)

DECLARE_UI(/datum/tgui_bitfield_input, "BitfieldInput")

/datum/tgui_bitfield_input/ui_title(mob/user)
	return title

/datum/tgui_bitfield_input/tgui_close(mob/user)
	. = ..()
	closed = TRUE

UI_DATA_REPLACE(/datum/tgui_bitfield_input)

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
