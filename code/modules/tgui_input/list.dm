/**
 * Creates a TGUI input list window and returns the user's response.
 *
 * This proc should be used to create alerts that the caller will wait for a response from.
 * Arguments:
 * * user - The user to show the input box to.
 * * message - The content of the input box, shown in the body of the TGUI window.
 * * title - The title of the input box, shown on the top of the TGUI window.
 * * items - The options that can be chosen by the user, each string is assigned a button on the UI.
 * * default - If an option is already preselected on the UI. Current values, etc.
 * * timeout - The timeout of the input box, after which the menu will close and qdel itself. Set to zero for no timeout.
 */
/proc/tgui_input_list(mob/user, message, title = "Select", list/items, default, timeout = 0, strict_modern = FALSE, ui_state = GLOB.tgui_always_state)
	if(!length(items))
		return null
	if (!istype(user))
		if (istype(user, /client))
			var/client/client = user
			user = client.mob
		else
			return null

	if(isnull(user.client))
		return null

	/// Client does NOT have tgui_input on: Returns regular input
	if(!user.read_preference(/datum/preference/toggle/tgui_input_mode) && !strict_modern)
		return input(user, message, title, default) as null|anything in items // ALLOW(scheduler): the blocking prompt API itself (the non-tgui fallback om_prompt never uses)
	var/datum/tgui_list_input/input = new(user, message, title, items, default, timeout, ui_state)
	if(input.invalid)
		spent(input, user)
		return
	input.tgui_interact(user)
	input.wait()
	if (input)
		. = input.choice
		spent(input, user)

/**
 * # tgui_list_input
 *
 * Datum used for instantiating and using a TGUI-controlled list input that prompts the user with
 * a message and shows a list of selectable options
 */
/datum/tgui_list_input
	/// The title of the TGUI window
	var/title
	/// The textual body of the TGUI window
	var/message
	/// The list of items (responses) provided on the TGUI window
	var/list/items
	/// Buttons (strings specifically) mapped to the actual value (e.g. a mob or a verb)
	var/list/items_map
	/// The button that the user has pressed, null if no selection has been made
	var/choice
	/// The default button to be selected
	var/default
	/// The time at which the tgui_list_input was created, for displaying timeout progress.
	EXPIRY_DECLARE(start_time)
	/// The lifespan of the tgui_list_input, after which the window will close and delete itself.
	var/timeout
	/// Boolean field describing if the tgui_list_input was closed by the user.
	var/closed
	/// The TGUI UI state that will be returned in ui_state(). Default: always_state
	var/tmp/datum/tgui_state/state_static
	/// Whether the tgui list input is invalid or not (i.e. due to all list entries being null)
	var/invalid = FALSE

/datum/tgui_list_input/New(mob/user, message, title, list/items, default, timeout, ui_state)
	src.title = title
	src.message = message
	src.items = list()
	src.items_map = list()
	src.default = default
	src.state_static = ui_state
	var/list/repeat_items = list()
	// Gets rid of illegal characters
	var/static/regex/whitelistedWords = regex(@{"([^\u0020-\u8000]+)"})
	for(var/i in items)
		if(!i)
			continue
		var/string_key = whitelistedWords.Replace("[i]", "")
		//avoids duplicated keys E.g: when areas have the same name
		string_key = avoid_assoc_duplicate_keys(string_key, repeat_items)
		src.items += string_key
		src.items_map[string_key] = i

	if(length(src.items) == 0)
		invalid = TRUE
	if (timeout)
		src.timeout = timeout
		EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
		om_qdel_after(src, timeout)

/**
 * Waits for a user's response to the tgui_list_input's prompt before returning. Returns early if
 * the window was closed by the user.
 */
/datum/tgui_list_input/proc/wait()
	while (!choice && !closed)
		stoplag(1) // ALLOW(scheduler): tgui_input is the blocking prompt API itself: it waits on the player by design

CAPABILITIES(/datum/tgui_list_input)
	interface("ListInputModal")
	op("submit", ui_act("submit", arg("entry")), then(PROC_REF(ui_act_submit)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))

/datum/tgui_list_input/tgui_close(mob/user)
	. = ..()
	closed = TRUE

/datum/tgui_list_input/tgui_state(mob/user)
	return state()

/datum/tgui_list_input/tgui_static_data(mob/user)
	var/list/data = list()
	data["init_value"] = default || items[1]
	data["items"] = items
	data["large_buttons"] = user.read_preference(/datum/preference/toggle/tgui_large_buttons)
	data["message"] = message
	data["swapped_buttons"] = !user.read_preference(/datum/preference/toggle/tgui_swapped_buttons)
	data["title"] = title
	return data

/// /datum/tgui_list_input's window data.
/datum/tgui_list_input/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(timeout)
		data["timeout"] = clamp((timeout - (world.time - start_time) - 1 SECONDS) / (timeout - 1 SECONDS), 0, 1)
	return data

/datum/tgui_list_input/proc/ui_act_submit(datum/act/op/A, entry)
	if (!(entry in items))
		return
	set_choice(items_map[entry])
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_list_input/proc/ui_act_cancel(datum/act/op/A)
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_list_input/proc/set_choice(choice)
	src.choice = choice

/// A shared (registered) definition/flyweight: never cleared.
/datum/tgui_list_input/proc/state() as /datum/tgui_state
	return state_static
