/// Opens the ignore list (the Game Preferences window's Ignore List button).
/client/proc/open_ignore_list()
	var/datum/ignore_list_window/window = new(mob)
	window.tgui_interact(mob)

/// The window where a player reads, adds to and takes from the list of players whose OOC and deadchat they do not see.
/datum/ignore_list_window
	var/tmp/mob/viewer

/datum/ignore_list_window/New(mob/viewing)
	..()
	rel_set(src, nameof(viewer), viewing)

CAPABILITIES(/datum/ignore_list_window)
	ref_one(nameof(viewer))
	interface("IgnoreList", title = "Ignore List", state = nameof(GLOB.tgui_always_state))
	op("ignore", ui_act("ignore"), needs(req(PROC_REF(req_own_list))), asks(/datum/prompt/text, fields = list("title" = "Ignore a player", "question" = "The ckey of the player whose OOC and deadchat messages should not appear to you.", "max_len" = 64, "timeout" = 0), step = "key"), needs(req_answer(PROC_REF(ignore_refusal), step = "key")), then(PROC_REF(ui_act_ignore)))
	op("unignore", ui_act("unignore", arg("key", schema_text(64))), needs(req(PROC_REF(req_own_list)), req(PROC_REF(unignore_refusal))), then(PROC_REF(ui_act_unignore)))

/// /datum/ignore_list_window's window data.
/datum/ignore_list_window/ui_data(datum/act/eval/A)
	var/list/ignored = viewer?.client?.prefs?.read_preference(/datum/preference/ignored_players)
	return list("ignored" = ignored ? ignored.Copy() : list())

/// Requirement: the list is the viewer's own, and they have saved settings to keep it in.
/datum/ignore_list_window/proc/req_own_list(datum/act/op/A)
	return (A.actor == viewer && viewer?.client?.prefs) ? null : MSG(req_silent)

MSG_DEF_SELF(ignore_list/no_key, "Enter the ckey of the player to ignore.")
MSG_DEF_SELF(ignore_list/already, "That player is already being ignored.")
MSG_DEF_SELF(ignore_list/yourself, "You can't ignore yourself.")
MSG_DEF_SELF(ignore_list/not_ignored, "That player isn't being ignored.")

/// The ckey an Ignore answer names.
/datum/ignore_list_window/proc/ignore_key(datum/act/op/A)
	return ckey(sanitize(A.step_value("key")))

/// An empty key, a key already on the list and your own key are refused.
/datum/ignore_list_window/proc/ignore_refusal(datum/act/op/A)
	var/key_to_ignore = ignore_key(A)
	if(!key_to_ignore)
		return MSG(ignore_list/no_key)
	if(key_to_ignore in viewer?.client?.prefs?.read_preference(/datum/preference/ignored_players))
		return MSG(ignore_list/already)
	if(key_to_ignore == viewer?.ckey)
		return MSG(ignore_list/yourself)
	return null

/// A key that is not on the list cannot be taken off it.
/datum/ignore_list_window/proc/unignore_refusal(datum/act/op/A)
	var/key_to_unignore = ckey(sanitize(A.args ? A.args["key"] : null))
	if(key_to_unignore in viewer?.client?.prefs?.read_preference(/datum/preference/ignored_players))
		return null
	return MSG(ignore_list/not_ignored)

/datum/ignore_list_window/proc/ui_act_ignore(datum/act/op/A)
	var/client/player = viewer.client
	var/key_to_ignore = ignore_key(A)
	var/list/ignored_players = player.prefs.read_preference(/datum/preference/ignored_players)
	ignored_players |= key_to_ignore
	player.prefs.write_preference_by_type(/datum/preference/ignored_players, ignored_players)
	to_chat(viewer, span_notice("Now ignoring <b>[key_to_ignore]</b>."))
	SStgui.update_uis(src)
	return OP_OK

/datum/ignore_list_window/proc/ui_act_unignore(datum/act/op/A, key)
	var/client/player = viewer.client
	var/key_to_unignore = ckey(sanitize(key))
	var/list/ignored_players = player.prefs.read_preference(/datum/preference/ignored_players)
	ignored_players -= key_to_unignore
	player.prefs.write_preference_by_type(/datum/preference/ignored_players, ignored_players)
	to_chat(viewer, span_notice("Reverted ignore on <b>[key_to_unignore]</b>."))
	SStgui.update_uis(src)
	return OP_OK

/mob/proc/is_key_ignored(key_to_check)
	if(client)
		return client.is_key_ignored(key_to_check)
	return 0

/client/proc/is_key_ignored(key_to_check)
	key_to_check = ckey(key_to_check)
	var/list/ignored_players = prefs?.read_preference(/datum/preference/ignored_players)
	if(key_to_check in ignored_players)
		if(GLOB.directory[key_to_check] in GLOB.admins) // This is here so this is only evaluated if someone is actually being blocked.
			return 0
		return 1
	return 0
