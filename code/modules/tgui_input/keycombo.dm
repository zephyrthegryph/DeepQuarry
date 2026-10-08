/**
 * # tgui_input_keycombo
 *
 * Datum used for instantiating and using a TGUI-controlled key input that prompts the user with
 * a message and listens for key presses.
 */
/datum/tgui_input_keycombo
	/// Boolean field describing if the tgui_input_number was closed by the user.
	var/closed
	/// The default (or current) value, shown as a default. Users can press reset with this.
	var/default
	/// The entry that the user has return_typed in.
	var/entry
	/// The prompt's body, if any, of the TGUI window.
	var/message
	/// The time at which the number input was created, for displaying timeout progress.
	EXPIRY_DECLARE(start_time)
	/// The lifespan of the number input, after which the window will close and delete itself.
	var/timeout
	/// The title of the TGUI window
	var/title
	/// The TGUI UI state that will be returned in ui_state(). Default: always_state
	var/tmp/datum/tgui_state/state_static

/datum/tgui_input_keycombo/New(mob/user, message, title, default, timeout, ui_state)
	src.default = default
	src.message = message
	src.title = title
	src.state_static = ui_state
	if (timeout)
		src.timeout = timeout
		EXPIRY_STAMP(src, start_time, CLOCK_WORLD)
		expire(timeout)

/**
 * Waits for a user's response to the tgui_input_keycombo's prompt before returning. Returns early if
 * the window was closed by the user.
 */
/datum/tgui_input_keycombo/proc/wait()
	while (!entry && !closed && !QDELETED(src))
		stoplag(1) // ALLOW(scheduler): tgui_input is the blocking prompt API itself: it waits on the player by design

CAPABILITIES(/datum/tgui_input_keycombo)
	interface("KeyComboModal")
	op("submit", ui_act("submit", arg("entry", schema_text(4096))), then(PROC_REF(ui_act_submit)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))

/datum/tgui_input_keycombo/tgui_close(mob/user)
	. = ..()
	closed = TRUE

/datum/tgui_input_keycombo/tgui_state(mob/user)
	return state()

/datum/tgui_input_keycombo/tgui_static_data(mob/user)
	var/list/data = list()
	data["init_value"] = default // Default is a reserved keyword
	data["large_buttons"] = !user.client?.prefs || user.client.prefs.read_preference(/datum/preference/toggle/tgui_large_buttons)
	data["message"] = message
	data["swapped_buttons"] = !user.client?.prefs || user.client.prefs.read_preference(/datum/preference/toggle/tgui_swapped_buttons)
	data["title"] = title
	return data

/// /datum/tgui_input_keycombo's window data.
/datum/tgui_input_keycombo/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(timeout)
		data["timeout"] = CLAMP01((timeout - (world.time - start_time) - 1 SECONDS) / (timeout - 1 SECONDS))
	return data

/datum/tgui_input_keycombo/proc/ui_act_submit(datum/act/op/A, entry)
	set_entry(entry)
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_input_keycombo/proc/ui_act_cancel(datum/act/op/A)
	closed = TRUE
	SStgui.close_uis(src)
	return TRUE

/datum/tgui_input_keycombo/proc/set_entry(entry)
	src.entry = entry

/// A shared (registered) definition/flyweight: never cleared.
/datum/tgui_input_keycombo/proc/state() as /datum/tgui_state
	return state_static
