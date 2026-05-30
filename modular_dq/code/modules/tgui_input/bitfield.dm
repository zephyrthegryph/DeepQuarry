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
	return tgui_input_bitfield(user, title, bitfield, current_value, allowed_edit_field)


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
	var/start_time
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
		start_time = world.time
		QDEL_IN(src, timeout)

/datum/tgui_bitfield_input/Destroy(force)
	SStgui.close_uis(src)
	bitflags = null
	return ..()

/datum/tgui_bitfield_input/proc/wait()
	while(!submitted && !closed && !QDELETED(src))
		stoplag(1)

/datum/tgui_bitfield_input/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/tgui_bitfield_input/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BitfieldInput", title)
		ui.open()

/datum/tgui_bitfield_input/tgui_close(mob/user)
	. = ..()
	closed = TRUE

/datum/tgui_bitfield_input/tgui_data(mob/user)
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

/datum/tgui_bitfield_input/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("toggle")
			var/bit = text2num("[params["bit"]]")
			if(!isnum(bit))
				return
			if(!(allowed_edit_field & bit))
				return
			if(value & bit)
				value &= ~bit
			else
				value |= bit
			return TRUE
		if("submit")
			submitted = TRUE
			SStgui.close_uis(src)
			return TRUE
		if("cancel")
			value = initial_value
			submitted = FALSE
			closed = TRUE
			SStgui.close_uis(src)
			return TRUE
