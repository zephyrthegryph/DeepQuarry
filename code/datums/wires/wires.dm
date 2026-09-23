#define MAXIMUM_EMP_WIRES 3

/datum/wires
	/// TRUE if the wires will be different every time a new wire datum is created.
	var/randomize = FALSE
	/// The atom the wires belong too. For example: an airlock.
	var/atom/holder
	/// The holder type; used to make sure that the holder is the correct type.
	var/holder_type
	/// The display name for the TGUI window. For example, given the var is "APC"...
	/// When the TGUI window is opened, "wires" will be appended to it's title, and it would become "APC wires".
	var/proper_name = "Unknown"
	/// The template to use for TGUI.
	var/tgui_template = "Wires"
	/// The total number of wires that our holder atom has.
	var/wire_count = NONE
	/// A list of all wires. For a list of valid wires defines that can go here, see `code/__DEFINES/wires.dm`
	var/list/wires
	/// Lazy list of all cut wires. The same values that can go into `wires` will get added and removed from this list.
	var/list/cut_wires
	/// An associative list with the wire color as the key, and the wire define as the value.
	/// Non-randomized types share their type's list from `GLOB.wire_color_directory`: treat it as read-only
	/// and replace it (never mutate it) when this instance needs its own colours.
	var/list/colors
	/// Lazy associative list of signalers attached to the wires. The wire color is the key, and the signaler object reference is the value.
	var/list/assemblies
	/// Admin var to disable seeing wire descriptions
	var/force_hide_wires = FALSE

/datum/wires/New(atom/_holder)
	..()
	// A null holder is the state materializer building a bare instance
	// (owned codec, C5); state_post_apply() on the atom fixes holder up
	// once its own vars (including this datum) are applied.
	if(_holder && !istype(_holder, holder_type))
		CRASH("Our holder is null/the wrong type!")

	holder = _holder

	// Add in the appropriate amount of dud wires.
	var/wire_len = length(wires)
	if(wire_len < wire_count) // If the amount of "real" wires is less than the total we're suppose to have...
		add_duds(wire_count - wire_len) // Add in the appropriate amount of duds to reach `wire_count`.

	// If the randomize is true, we need to generate a new set of wires and ignore any wire color directories.
	if(randomize)
		randomize()
		return

	colors = GLOB.wire_color_directory[holder_type]
	if(!colors)
		randomize()
		GLOB.wire_color_directory[holder_type] = colors
		GLOB.wire_name_directory[holder_type] = proper_name

// holder is restored by the owning atom's state_post_apply() (C5, base_codecs.dm);
// assemblies (attached signalers) are external items that outlive a wire
// reset and are rare enough to just re-attach by hand after a round trip.
/datum/wires/state_exclude()
	return ..() + list("holder", "assemblies")

/datum/wires/Destroy()
	for(var/color in assemblies)
		detach_assembly(color)
	holder = null
	return ..()

/**
 * Randomly generates a new set of wires. and corresponding colors from the given pool. Assigns the information as an associative list, to `colors`.
 *
 * In the `colors` list, the name of the color is the key, and the wire is the value.
 * For example: `colors["red"] = WIRE_ELECTRIFY`. This will look like `list("red" = WIRE_ELECTRIFY)` internally.
 */
/datum/wires/proc/randomize()
	var/static/list/possible_colors = list("red", "blue", "green", "darkmagenta", "orange", "brown", "gold", "grey", "cyan", "white", "purple", "pink", "darkslategrey", "yellow")
	var/list/my_possible_colors = possible_colors.Copy()

	// Always build a fresh list: `colors` may be the type's shared directory entry.
	var/list/new_colors = list()
	for(var/wire in shuffle(wires))
		new_colors[pick_n_take(my_possible_colors)] = wire
	colors = new_colors

/**
 * Proc called when the user attempts to interact with wires UI.
 *
 * Checks if the user exists, is a mob, the wires are attached to something (`holder`) and makes sure `interactable(user)` returns TRUE.
 * If all the checks succeed, open the TGUI interface for the user.
 *
 * Arugments:
 * * user - the mob trying to interact with the wires.
 */
/datum/wires/proc/Interact(mob/user)
	if(user && istype(user) && holder && interactable(user))
		tgui_interact(user)

/**
 * Base proc, intended to be overriden. Wire datum specific checks you want to run before the TGUI is shown to the user should go here.
 */
/datum/wires/proc/interactable(mob/user)
	return TRUE

/// Users will be interacting with our holder object and not the wire datum directly, therefore we need to return the holder.
/datum/wires/tgui_host()
	return holder

/datum/wires/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, tgui_template, "[proper_name] wires")
		ui.open()

/datum/wires/tgui_state(mob/user)
	return GLOB.tgui_physical_state

/datum/wires/tgui_data(mob/user)
	var/list/data = list()
	var/list/replace_colors

	if(isliving(user))
		var/mob/living/L = user
		for(var/datum/modifier/M in L.modifiers)
			if(!isnull(M.wire_colors_replace))
				replace_colors = M.wire_colors_replace
				break

	var/list/wires_list = list()

	for(var/color in colors)
		var/replaced_color = color
		var/color_name = color

		if(color in replace_colors) // If this color is one that needs to be replaced using the colorblindness list.
			replaced_color = replace_colors[color]
			if(replaced_color in LIST_COLOR_RENAME) // If its an ugly written color name like "darkolivegreen", rename it to something like "dark green".
				color_name = LIST_COLOR_RENAME[replaced_color]
			else
				color_name = replaced_color // Else just keep the normal color name

		if(color in LIST_COLOR_RENAME)
			color_name = LIST_COLOR_RENAME[color]

		wires_list += list(list(
			"seen_color" = replaced_color, // The color of the wire that the mob will see. This will be the same as `color` if the user is NOT colorblind.
			"color_name" = color_name, // The wire's name. This will be the same as `color` if the user is NOT colorblind.
			"color" = color, // The "real" color of the wire. No replacements.
			"wire" = can_see_wire_info(user) && !is_dud_color(color) ? get_wire(color) : null, // Wire define information like "Contraband" or "Door Bolts".
			"cut" = is_color_cut(color), // Whether the wire is cut or not. Used to display "cut" or "mend".
			"attached" = is_attached(color) // Whether or not a signaler is attached to this wire.
		))
	data["wires"] = wires_list

	// Get the information shown at the bottom of wire TGUI window, such as "The red light is blinking", etc.
	// If the user is colorblind, we need to replace these colors as well.
	var/list/status = get_status()

	if(replace_colors)
		var/i
		for(i in 1 to length(status))
			for(var/color in replace_colors)
				var/new_color = replace_colors[color]
				if(new_color in LIST_COLOR_RENAME)
					new_color = LIST_COLOR_RENAME[new_color]
				if(findtext(status[i], color))
					status[i] = replacetext(status[i], color, new_color)
					break

	data["status"] = status
	return data

/datum/wires/tgui_act(action, list/params, datum/tgui/ui)
	if(..())
		return TRUE

	if(!interactable(ui.user))
		return

	var/obj/item/I = ui.user.get_active_hand()
	if(istype(I, /obj/item/paicard)) // Get pai builtin emag tools
		var/obj/item/paicard/card = I
		if(card.emagged && card.has_emag_toolkit)
			switch(card.selected_system)
				if("MultiTool")
					I = card.multitool
				if("Signaler")
					I = card.signaler
	var/color = lowertext(params["wire"])
	holder.add_hiddenprint(ui.user)

	switch(action)
		// Toggles the cut/mend status.
		if("cut")
			if(!istype(I) || !I.has_tool_quality(TOOL_WIRECUTTER))
				to_chat(ui.user, span_warning("You need wirecutters!"))
				return

			playsound(holder, I.usesound, 20, 1)
			cut_color(color)
			return TRUE

		// Pulse a wire.
		if("pulse")
			if(!istype(I) || !I.has_tool_quality(TOOL_MULTITOOL))
				to_chat(ui.user, span_warning("You need a multitool!"))
				return

			playsound(holder, 'sound/weapons/empty.ogg', 20, 1)
			pulse_color(color)

			// If they pulse the electrify wire, call interactable() and try to shock them.
			if(get_wire(color) == WIRE_ELECTRIFY)
				interactable(ui.user)

			return TRUE

		// Attach a signaler to a wire.
		if("attach")
			if(is_attached(color))
				var/obj/item/O = detach_assembly(color)
				if(O)
					ui.user.put_in_hands(O)
					return TRUE

			if(!istype(I, /obj/item/assembly/signaler))
				to_chat(ui.user, span_warning("You need a remote signaller!"))
				return

			if(ui.user.unEquip(I))
				attach_assembly(color, I)
				return TRUE
			else
				to_chat(ui.user, span_warning("[I] is stuck to your hand!"))

/**
 * Proc called to determine if the user can see wire define information, such as "Contraband", "Door Bolts", etc.
 *
 * If the user is an admin, or has a multitool which reveals wire information in their active hand, the proc returns TRUE.
 *
 * Arguments:
 * * user - the mob who is interacting with the wires.
 */
/datum/wires/proc/can_see_wire_info(mob/user)
	// TODO: Reimplement this if we ever get Advanced Admin Interaction.
	// if(user.can_admin_interact())
		// return TRUE
	if(force_hide_wires)
		return FALSE
	var/obj/item/I = user.get_active_hand()
	if(istype(I, /obj/item/multitool/alien))
		return TRUE
	if(HAS_TRAIT(user, TRAIT_CAN_SEE_WIRES))
		return TRUE
	if(user.mind && HAS_TRAIT(user.mind, TRAIT_CAN_SEE_WIRES))
		return TRUE
	return FALSE

/**
 * Base proc, intended to be overwritten. Put wire information you'll see at the botton of the TGUI window here, such as "The red light is blinking".
 */
/datum/wires/proc/get_status()
	return list()

/**
 * Clears the `colors` list, and randomizes it to a new set of color-to-wire relations.
 */
/datum/wires/proc/shuffle_wires()
	randomize()

/**
 * Repairs all cut wires.
 */
/datum/wires/proc/repair()
	cut_wires = null

/**
 * Adds in dud wires, which do nothing when cut/pulsed.
 *
 * Arguments:
 * * duds - the amount of dud wires to generate.
 */
/datum/wires/proc/add_duds(duds)
	while(duds)
		var/dud = WIRE_DUD_PREFIX + "[--duds]"
		if(dud in wires)
			continue
		wires += dud

/**
 * Determines if the passed in wire is a dud or not. Returns TRUE if the wire is a dud, FALSE otherwise.
 *
 * Arugments:
 * * wire - a wire define, NOT a color. For example `WIRE_ELECTRIFY`.
 */
/datum/wires/proc/is_dud(wire)
	return findtext(wire, WIRE_DUD_PREFIX, 1, length(WIRE_DUD_PREFIX) + 1)

/**
 * Returns TRUE if the wire that corresponds to the passed in color is a dud. FALSE otherwise.
 *
 * Arugments:
 * * color - a wire color.
 */
/datum/wires/proc/is_dud_color(color)
	return is_dud(get_wire(color))

/**
 * Gets the wire associated with the color passed in.
 *
 * Arugments:
 * * color - a wire color.
 */
/datum/wires/proc/get_wire(color)
	return colors[color]

/**
 * Determines if the passed in wire is cut or not. Returns TRUE if it's cut, FALSE otherwise.
 *
 * Arugments:
 * * wire - a wire define, NOT a color. For example `WIRE_ELECTRIFY`.
 */
/datum/wires/proc/is_cut(wire)
	return (wire in cut_wires)

/**
 * Determines if the wire associated with the passed in color, is cut or not. Returns TRUE if it's cut, FALSE otherwise.
 *
 * Arugments:
 * * wire - a wire color.
 */
/datum/wires/proc/is_color_cut(color)
	return is_cut(get_wire(color))

/**
 * Determines if all of the wires are cut. Returns TRUE they're all cut, FALSE otherwise.
 */
/datum/wires/proc/is_all_cut()
	return (length(cut_wires) == length(wires))

/**
 * Cut or mend a wire. Calls `on_cut()`.
 *
 * Arugments:
 * * wire - a wire define, NOT a color. For example `WIRE_ELECTRIFY`.
 */
/datum/wires/proc/cut(wire)
	if(is_cut(wire))
		LAZYREMOVE(cut_wires, wire)
		on_cut(wire, mend = TRUE)
	else
		cut_wire(wire)

/**
 * Cuts an intact wire without ever mending it.
 *
 * Scripted damage and sabotage should use this proc. `cut()` remains the
 * interactive wirecutter toggle used by the wires UI. Returns TRUE only when
 * this call changed the wire's state.
 */
/datum/wires/proc/cut_wire(wire)
	if(is_cut(wire))
		return FALSE
	LAZYADD(cut_wires, wire)
	on_cut(wire, mend = FALSE)
	return TRUE

/**
 * Cut the wire which corresponds with the passed in color.
 *
 * Arugments:
 * * color - a wire color.
 */
/datum/wires/proc/cut_color(color)
	cut(get_wire(color))

/**
 * Cuts a random wire.
 */
/datum/wires/proc/cut_random()
	var/list/intact_wires = wires - cut_wires
	if(!length(intact_wires))
		return FALSE
	return cut_wire(pick(intact_wires))

/**
 * Cuts all wires.
 */
/datum/wires/proc/cut_all()
	var/cut_count = 0
	for(var/wire in wires)
		cut_count += cut_wire(wire)
	return cut_count

/**
 * Mends every cut wire. Returns the number of wires whose state changed.
 */
/datum/wires/proc/mend_all()
	var/mend_count = 0
	for(var/wire in cut_wires?.Copy())
		cut(wire)
		mend_count++
	return mend_count

/**
 * Proc called when any wire is cut.
 *
 * Base proc, intended to be overriden.
 * Place an behavior you want to happen when certain wires are cut, into this proc.
 *
 * Arugments:
 * * wire - a wire define, NOT color. For example 'WIRE_ELECTRIFY'.
 * * mend - TRUE if we're mending the wire. FALSE if we're cutting.
 */
/datum/wires/proc/on_cut(wire, mend = FALSE)
	return

/**
 * Pulses the given wire. Calls `on_pulse()`.
 *
 * Arugments:
 * * wire - a wire define, NOT a color. For example `WIRE_ELECTRIFY`.
 */
/datum/wires/proc/pulse(wire)
	if(is_cut(wire))
		return
	on_pulse(wire)

/**
 * Pulses the wire associated with the given color.
 *
 * Arugments:
 * * wire - a wire color.
 */
/datum/wires/proc/pulse_color(color)
	pulse(get_wire(color))

/**
 * Proc called when any wire is pulsed.
 *
 * Base proc, intended to be overriden.
 * Place behavior you want to happen when certain wires are pulsed, into this proc.
 *
 * Arugments:
 * * wire - a wire define, NOT color. For example 'WIRE_ELECTRIFY'.
 */
/datum/wires/proc/on_pulse(wire)
	return

/**
 * Proc called when an attached signaler receives a signal.
 *
 * Searches through the `assemblies` list for the wire that the signaler is attached to. Pulses the wire when it's found.
 *
 * Arugments:
 * * S - the attached signaler receiving the signal.
 */
/datum/wires/proc/pulse_assembly(obj/item/assembly/signaler/S)
	for(var/color in assemblies)
		if(S == assemblies[color])
			pulse_color(color)
			return TRUE

/**
 * Proc called when a mob tries to attach a signaler to a wire.
 *
 * Makes sure that `S` is actually a signaler and that something is not already attached to the wire.
 * Adds the signaler to the `assemblies` list as a value, with the `color` as a the key.
 *
 * Arguments:
 * * color - the wire color.
 * * S - the signaler that a mob is trying to attach.
 */
/datum/wires/proc/attach_assembly(color, obj/item/assembly/signaler/S)
	if(S && istype(S) && !is_attached(color))
		LAZYSET(assemblies, color, S)
		S.forceMove(holder)
		S.connected = src
		return S

/**
 * Proc called when a mob tries to detach a signaler from a wire.
 *
 * First checks if there is a signaler on the wire. If so, removes the signaler, and clears it from `assemblies` list.
 *
 * Arguments:
 * * color - the wire color.
 */
/datum/wires/proc/detach_assembly(color)
	var/obj/item/assembly/signaler/S = get_attached(color)
	if(S && istype(S))
		LAZYREMOVE(assemblies, color)
		S.connected = null
		S.forceMove(holder.drop_location())
		return S

/**
 * Gets the signaler attached to the given wire color, if there is one.
 *
 * Arguments:
 * * color - the wire color.
 */
/datum/wires/proc/get_attached(color)
	return LAZYACCESS(assemblies, color)

/**
 * Checks if the given wire has a signaler on it.
 *
 * Arguments:
 * * color - the wire color.
 */
/datum/wires/proc/is_attached(color)
	if(LAZYACCESS(assemblies, color))
		return TRUE

/datum/wires/proc/emp_pulse()
	var/list/possible_wires = shuffle(wires)
	var/remaining_pulses = MAXIMUM_EMP_WIRES

	for(var/wire in possible_wires)
		if(prob(33))
			pulse(wire)
			remaining_pulses--
			if(!remaining_pulses)
				break

#undef MAXIMUM_EMP_WIRES
