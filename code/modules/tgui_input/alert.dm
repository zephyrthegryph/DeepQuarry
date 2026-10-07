/**
 * Creates a TGUI alert window and returns the user's response.
 *
 * This proc should be used to create alerts that the caller will wait for a response from.
 * Arguments:
 * * user - The user to show the alert to.
 * * message - The content of the alert, shown in the body of the TGUI window.
 * * title - The of the alert modal, shown on the top of the TGUI window.
 * * buttons - The options that can be chosen by the user, each string is assigned a button on the UI.
 * * timeout - The timeout of the alert, after which the modal will close and qdel itself. Set to zero for no timeout.
 * * autofocus - The bool that controls if this alert should grab window focus.
 */
/proc/tgui_alert(mob/user, message = "", title, list/buttons = list("Ok"), timeout = 0, autofocus = TRUE, strict_byond = FALSE, ui_state = GLOB.tgui_always_state)
	if (istext(buttons))
		stack_trace("tgui_alert() received text for buttons instead of list")
		return
	if (istext(user))
		stack_trace("tgui_alert() received text for user instead of list")
		return
	if (!istype(user))
		if (istype(user, /client))
			var/client/client = user
			user = client.mob
		else
			return null

	if(isnull(user.client))
		return null

	// Client does NOT have tgui_input on: Returns regular input
	if(!user.read_preference(/datum/preference/toggle/tgui_input_mode) || strict_byond)
		if(length(buttons) == 2)
			return alert(user, message, title, buttons[1], buttons[2]) // ALLOW(scheduler): the blocking prompt API itself (the non-tgui fallback om_prompt never uses)
		if(length(buttons) == 3)
			return alert(user, message, title, buttons[1], buttons[2], buttons[3]) // ALLOW(scheduler): the blocking prompt API itself (the non-tgui fallback om_prompt never uses)

	var/datum/tgui_alert/alert = new(user, message, title, buttons, timeout, autofocus, ui_state)
	alert.tgui_interact(user)
	alert.wait()
	if (alert)
		. = alert.choice
		spent(alert, user)

/**
 * # tgui_alert
 *
 * Datum used for instantiating and using a TGUI-controlled modal that prompts the user with
 * a message and has buttons for responses.
 */
/datum/tgui_alert
	/// The title of the TGUI window
	var/title
	/// The textual body of the TGUI window
	var/message
	/// The list of buttons (responses) provided on the TGUI window
	var/list/buttons
	/// The button that the user has pressed, null if no selection has been made
	var/choice
	/// The time at which the tgui_modal was created, for displaying timeout progress.
	EXPIRY_DECLARE(start_time)
	/// The lifespan of the tgui_modal, after which the window will close and delete itself.
	var/timeout
	/// The bool that controls if this modal should grab window focus
	var/autofocus
	/// Boolean field describing if the tgui_modal was closed by the user.
	var/closed
	/// The TGUI UI state that will be returned in ui_state(). Default: always_state
	var/tmp/datum/tgui_state/state_static

/datum/tgui_alert/New(mob/user, message, title, list/buttons, timeout, autofocus, ui_state)
	src.autofocus = autofocus
	src.buttons = buttons.Copy()
	src.message = message
	src.title = title
	src.state_static = ui_state
	if (timeout)
		src.timeout = timeout
		EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
		expire(timeout)

/**
 * Waits for a user's response to the tgui_modal's prompt before returning. Returns early if
 * the window was closed by the user.
 */
/datum/tgui_alert/proc/wait()
	while (!choice && !closed && !QDELETED(src))
		stoplag(1) // ALLOW(scheduler): tgui_input is the blocking prompt API itself: it waits on the player by design

CAPABILITIES(/datum/tgui_alert)
	interface("AlertModal")
	op("choose", ui_act("choose", arg("choice", schema_text(4096))), then(PROC_REF(ui_act_choose)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))

/datum/tgui_alert/tgui_close(mob/user)
	. = ..()
	closed = TRUE

/datum/tgui_alert/tgui_state(mob/user)
	return state()

/datum/tgui_alert/tgui_static_data(mob/user)
	var/list/data = list()
	data["autofocus"] = autofocus
	data["buttons"] = buttons
	data["message"] = message
	data["large_buttons"] = user.read_preference(/datum/preference/toggle/tgui_large_buttons)
	data["swapped_buttons"] = !user.read_preference(/datum/preference/toggle/tgui_swapped_buttons)
	data["title"] = title
	return data

/// /datum/tgui_alert's window data.
/datum/tgui_alert/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(timeout)
		data["timeout"] = CLAMP01((timeout - (world.time - start_time) - 1 SECONDS) / (timeout - 1 SECONDS))
	return data

/datum/tgui_alert/proc/ui_act_choose(datum/act/op/A, choice)
	if (!(choice in buttons))
		return
	set_choice(choice)
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_alert/proc/ui_act_cancel(datum/act/op/A)
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_alert/proc/set_choice(choice)
	src.choice = choice

/**
 * Creates an asynchronous TGUI alert window with an associated callback.
 *
 * This proc should be used to create alerts that invoke a callback with the user's chosen option.
 * Arguments:
 * * user - The user to show the alert to.
 * * message - The content of the alert, shown in the body of the TGUI window.
 * * title - The of the alert modal, shown on the top of the TGUI window.
 * * buttons - The options that can be chosen by the user, each string is assigned a button on the UI.
 * * callback - The callback to be invoked when a choice is made.
 * * timeout - The timeout of the alert, after which the modal will close and qdel itself. Disabled by default, can be set to seconds otherwise.
 */
/proc/tgui_alert_async(mob/user, message = "", title, list/buttons = list("Ok"), list/callback, timeout = 0, autofocus = TRUE, ui_state = GLOB.tgui_always_state)
	if (istext(buttons))
		stack_trace("tgui_alert() received text for buttons instead of list")
		return
	if (istext(user))
		stack_trace("tgui_alert() received text for user instead of list")
		return
	if (!istype(user))
		if (istype(user, /client))
			var/client/client = user
			user = client.mob
		else
			return null

	if(isnull(user.client))
		return null

	var/datum/tgui_alert/async/alert = new(user, message, title, buttons, callback, timeout, autofocus, ui_state)
	alert.tgui_interact(user)

/**
 * # async tgui_modal
 *
 * An asynchronous version of tgui_modal to be used with callbacks instead of waiting on user responses.
 */
/datum/tgui_alert/async
	/// The om_callable() spec run with the choice once one is made.
	var/list/callback

/datum/tgui_alert/async/New(mob/user, message, title, list/buttons, callback, timeout, autofocus, ui_state)
	..(user, message, title, buttons, timeout, autofocus, ui_state)
	src.callback = callback


/datum/tgui_alert/async/set_choice(choice)
	. = ..()
	if(!isnull(src.choice))
		if(callback)
			om_run_async(callback, src.choice)

/datum/tgui_alert/async/wait()
	return

/// A shared (registered) definition/flyweight: never cleared.
/datum/tgui_alert/proc/state() as /datum/tgui_state
	return state_static
