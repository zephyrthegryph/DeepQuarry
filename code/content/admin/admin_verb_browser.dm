// The admin verb browser: one searchable window for every ADMIN_VERB the admin's rights allow.
//
// The verb panel shows only the verbs an admin pinned (admin_verb_default_pins() until they choose their own) under one "Admin" tab,
// plus the "Admin Verbs" button that opens this window. The window lists the rest by category, remembers the recently used ones, and
// holds the server settings as one checkbox panel. Pins and the recent list are the admin's own player preferences.
//
// Running a verb from the window sends the same command the verb panel sends (the verb's name with dashes), so the verb's own arguments
// prompt as they always did, and the verb's body checks the rights again (SSadmin_verbs.dynamic_invoke_verb). A setting checkbox calls the
// setting's ADMIN_VERB through dynamic_invoke_verb, so its rights check, its log line and its announcement are the verb's own.

/// The pins preference value before the admin chose any: the default set applies.
#define ADMIN_VERB_PINS_UNSET "*"
/// The pins preference value of an admin who unpinned everything (an empty value would read as unset).
#define ADMIN_VERB_PINS_NONE "-"
/// The most verbs one admin can pin.
#define ADMIN_VERB_PINS_MAX 60
/// The most recently used verbs the window remembers.
#define ADMIN_VERB_RECENT_MAX 12

/// The verbs the verb panel pins for an admin who has not chosen their own: the ~25 used most, as ADMIN_VERB path names. The one place the default
/// list is written. A verb the admin's rights do not allow is left out of their panel. "admin_verb_browser" is the Admin Verbs button.
GLOBAL_LIST_INIT(admin_verb_default_pin_ids, list(
		"admin_verb_browser",
		"player_panel",
		"game_panel",
		"check_antagonists",
		"admin_ghost",
		"invisimin",
		"jumptomob",
		"Jump",
		"Getmob",
		"cmd_admin_pm_panel",
		"cmd_admin_say",
		"cmd_mod_say",
		"dsay",
		"debug_variables",
		"advanced_proc_call",
		"sdql2_query",
		"spawn_atom",
		"spawn_panel",
		"reload_configuration",
		"cmd_controller_view_ui",
		"view_runtimes",
		"cmd_admin_world_narrate",
		"show_game_mode",
		"delay",
		"startnow",
))

/proc/admin_verb_default_pins()
	return GLOB.admin_verb_default_pin_ids

// ---- the preferences ----

/datum/preference/text/admin_verb_pins
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "ADMIN_VERB_PINS"
	savefile_identifier = PREFERENCE_PLAYER
	maximum_value_length = 2048
	should_strip_html = FALSE

/datum/preference/text/admin_verb_pins/create_default_value()
	return ADMIN_VERB_PINS_UNSET

/datum/preference/text/admin_verb_recent
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "ADMIN_VERB_RECENT"
	savefile_identifier = PREFERENCE_PLAYER
	maximum_value_length = 512
	should_strip_html = FALSE

/// The verb ids a comma list holds, each once.
/proc/admin_verb_ids_from_text(text)
	var/list/ids = list()
	if(!istext(text))
		return ids
	for(var/id in splittext(text, ","))
		if(id && !(id in ids))
			ids += id
	return ids

/// A list of verb ids as the text the preferences keep.
/proc/admin_verb_ids_to_text(list/ids)
	return length(ids) ? jointext(ids, ",") : ADMIN_VERB_PINS_NONE

/// The ids a pins preference value stands for: the default set while unset, else the admin's own list.
/proc/admin_verb_pins_from_pref(raw)
	if(isnull(raw) || raw == ADMIN_VERB_PINS_UNSET)
		return admin_verb_default_pins().Copy()
	return admin_verb_ids_from_text(raw)

/// The ids in `ids` that `known` (an id-keyed list) holds, in order.
/proc/admin_verb_ids_known(list/ids, list/known)
	var/list/kept = list()
	for(var/id in ids)
		if(id in known)
			kept += id
	return kept

/// `ids` with `id` added (when absent) or removed (when present). The newest pin is last.
/proc/admin_verb_ids_flipped(list/ids, id)
	var/list/flipped = ids.Copy()
	if(id in flipped)
		flipped -= id
	else if(length(flipped) < ADMIN_VERB_PINS_MAX)
		flipped += id
	return flipped

/// `ids` with `id` moved to the front, at most ADMIN_VERB_RECENT_MAX of them.
/proc/admin_verb_ids_touched(list/ids, id)
	var/list/touched = list(id)
	for(var/other in ids)
		if(other != id && length(touched) < ADMIN_VERB_RECENT_MAX)
			touched += other
	return touched

/// The ids of the verbs in `verbs`, as an id-keyed list.
/proc/admin_verb_id_set(list/verbs)
	var/list/set_of = list()
	for(var/datum/admin_verb/V as anything in verbs)
		set_of[V.id] = TRUE
	return set_of

// ---- who may see what ----

/// The admin verbs this client's rights allow and the browser lists: none for a player.
/proc/admin_verbs_listed_for(client/subject)
	if(!admin_holder_of(subject))
		return list()
	return SSadmin_verbs.browser_verbs_for(subject)

/// The ids the client's verb panel shows: the pins the admin's rights allow. The Admin Verbs button is always among them.
/proc/admin_verb_panel_ids(client/subject)
	var/list/pins = admin_verb_ids_known(admin_verb_pins_from_pref(subject.prefs?.read_preference(/datum/preference/text/admin_verb_pins)), admin_verb_id_set(admin_verbs_listed_for(subject)))
	if(!("admin_verb_browser" in pins))
		pins += "admin_verb_browser"
	return pins

/// The names of the verbs the client's verb panel shows, as a name-keyed list (the stat panel knows verbs by name).
/proc/admin_verb_panel_names(client/subject)
	var/list/names = list()
	for(var/id in admin_verb_panel_ids(subject))
		var/datum/admin_verb/V = SSadmin_verbs.verb_by_id(id)
		if(V)
			names[V.name] = TRUE
	return names

// ---- the window ----

/datum/admin_verb_browser
	var/datum/admins/owner_admin

/datum/admin_verb_browser/New(datum/admins/owner_admin)
	..()
	rel_set(src, nameof(owner_admin), owner_admin)

// The admin holder owns this window (verb_browser); owner_admin is a plain relation back.

CAPABILITIES(/datum/admin_verb_browser)
	ref_one(nameof(owner_admin))
	interface("AdminVerbBrowser", title = "Admin Verbs", rights = R_HOLDER)
	op("run_verb", ui_act("run_verb", arg("id", schema_text(96))), then(PROC_REF(ui_act_run_verb)))
	op("toggle_pin", ui_act("toggle_pin", arg("id", schema_text(96))), then(PROC_REF(ui_act_toggle_pin)))
	op("reset_pins", ui_act("reset_pins"), then(PROC_REF(ui_act_reset_pins)))
	op("toggle_setting", ui_act("toggle_setting", arg("id", schema_text(96))), then(PROC_REF(ui_act_toggle_setting)))

/datum/admin_verb_browser/tgui_close(mob/user)
	SStgui.close_uis(src)

/// The verbs and the default pins this admin can use: sent once when the window opens.
/datum/admin_verb_browser/tgui_static_data(mob/user)
	var/client/C = user?.client
	var/list/listed = admin_verbs_listed_for(C)
	var/list/rows = list()
	for(var/datum/admin_verb/V as anything in listed)
		rows += list(list("id" = V.id, "name" = V.name, "desc" = V.description, "cat" = V.category))
	return list("verbs" = rows, "defaults" = admin_verb_ids_known(admin_verb_default_pins(), admin_verb_id_set(listed)))

/// /datum/admin_verb_browser's window data: the pins, the recent verbs and the server settings with their live state.
/datum/admin_verb_browser/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/client/C = user?.client
	if(!C)
		return list("pins" = list(), "recent" = list(), "toggles" = list())
	var/list/known = admin_verb_id_set(admin_verbs_listed_for(C))
	return list(
		"pins" = admin_verb_ids_known(admin_verb_pins_from_pref(C.prefs?.read_preference(/datum/preference/text/admin_verb_pins)), known),
		"recent" = admin_verb_ids_known(admin_verb_ids_from_text(C.prefs?.read_preference(/datum/preference/text/admin_verb_recent)), known),
		"toggles" = admin_setting_rows(C),
	)

/datum/admin_verb_browser/proc/ui_gate(datum/act/op/A)
	return !!owner_admin && !!admin_holder_of(A.actor?.client)

/datum/admin_verb_browser/proc/ui_act_run_verb(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/client/C = A.actor.client
	if(!SSadmin_verbs.browser_run(C, "[id]"))
		return FALSE
	admin_verb_remember(C, "[id]")
	SStgui.update_uis(src)
	return TRUE

/datum/admin_verb_browser/proc/ui_act_toggle_pin(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/client/C = A.actor.client
	var/list/known = admin_verb_id_set(admin_verbs_listed_for(C))
	if(!(id in known))
		return FALSE
	var/list/pins = admin_verb_ids_known(admin_verb_pins_from_pref(C.prefs?.read_preference(/datum/preference/text/admin_verb_pins)), known)
	admin_verb_write_pins(C, admin_verb_ids_flipped(pins, "[id]"))
	C.init_verbs()
	SStgui.update_uis(src)
	return TRUE

/datum/admin_verb_browser/proc/ui_act_reset_pins(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/client/C = A.actor.client
	C.prefs?.write_preference_by_type(/datum/preference/text/admin_verb_pins, ADMIN_VERB_PINS_UNSET)
	C.init_verbs()
	SStgui.update_uis(src)
	return TRUE

/datum/admin_verb_browser/proc/ui_act_toggle_setting(datum/act/op/A, id)
	if(!ui_gate(A))
		return FALSE
	var/client/C = A.actor.client
	if(!admin_setting_flip(C, "[id]"))
		return FALSE
	SStgui.update_uis(src)
	return TRUE

/// Save the admin's pins.
/proc/admin_verb_write_pins(client/C, list/ids)
	C.prefs?.write_preference_by_type(/datum/preference/text/admin_verb_pins, admin_verb_ids_to_text(ids))

/// Put `id` first in the admin's recent list.
/proc/admin_verb_remember(client/C, id)
	var/datum/preferences/prefs = C.prefs
	if(!prefs)
		return
	var/list/recent = admin_verb_ids_touched(admin_verb_ids_from_text(prefs.read_preference(/datum/preference/text/admin_verb_recent)), id)
	prefs.write_preference_by_type(/datum/preference/text/admin_verb_recent, jointext(recent, ","), WRITE_PREF_MANUAL)
	SScharacter_setup.queue_preferences_save(prefs)

/datum/admins
	var/datum/admin_verb_browser/verb_browser

/datum/admins/proc/open_admin_verb_browser(client/user)
	if(!check_rights_for(user, R_HOLDER))
		return
	if(!verb_browser)
		rel_set(src, nameof(verb_browser), new /datum/admin_verb_browser(src))
	verb_browser.tgui_interact(user.mob)

ADMIN_VERB(admin_verb_browser, R_HOLDER, "Admin Verbs", "Open the searchable browser of every admin verb your rights allow: pins, recent verbs and the server settings.", ADMIN_CATEGORY_MAIN)
	admin_holder_of(user)?.open_admin_verb_browser(user)
	feedback_add_details("admin_verb","AVB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

// ---- the server settings ----

/// The server settings panel: one row per setting that has an ADMIN_VERB flipping it. list(id, label, group, description, verb ids). The first verb
/// of the row the admin's rights allow is the one run, so a setting two verbs flip is one row.
GLOBAL_LIST_INIT(admin_setting_rows, list(
		list("ooc", "Player OOC", "Chat", "Players can use the OOC channel.", list("toggleooc")),
		list("looc", "Player LOOC", "Chat", "Players can use the LOOC channel.", list("togglelooc")),
		list("dsay", "Deadchat", "Chat", "Ghosts can use deadchat.", list("toggledsay")),
		list("dooc", "Dead OOC", "Chat", "Ghosts can use the OOC channel.", list("toggleoocdead")),
		list("enter", "New players may enter", "Game", "People can join the round.", list("toggleenter")),
		list("ai", "AI job open", "Game", "People can play as the AI.", list("toggleAI")),
		list("respawn", "Respawn", "Game", "Players may respawn.", list("toggleaban")),
		list("aliens", "Aliens", "Game", "Alien mobs are allowed.", list("toggle_aliens")),
		list("ninjas", "Space ninjas", "Game", "Space ninjas may spawn.", list("toggle_space_ninja")),
		list("traitor_scaling", "Traitor scaling", "Game", "The number of traitors scales with the crew.", list("toggletraitorscaling")),
		list("random_events", "Random events", "Game", "Meteors, black holes and blob (not space dust).", list("toggle_random_events")),
		list("ghost_writers", "Ghost writers", "Game", "Ghosts can write with cult ghost writing.", list("toggleghostwriters")),
		list("drones", "Maintenance drones", "Game", "Maintenance drones may be spawned.", list("toggledrones")),
		list("antaghud", "AntagHUD for observers", "Game", "Observers can use the antagonist HUD.", list("toggle_antagHUD_use")),
		list("antaghud_restricted", "AntagHUD restrictions", "Game", "Players that used AntagHUD cannot join the round.", list("toggle_antagHUD_restrictions")),
		list("admin_jump", "Admin jumping", "Game", "Admins may jump.", list("adjump")),
		list("admin_spawn", "Admin spawning", "Game", "Admins may spawn items.", list("adspawn")),
		list("admin_revive", "Admin reviving", "Game", "Admins may revive.", list("adrev")),
		list("panic_bunker", "Panic bunker", "Config", "Locks the server down to known players.", list("panicbunker")),
		list("paranoia", "New player warnings", "Config", "Warn admins about new players.", list("paranoia_logging")),
		list("ip_rep", "IP reputation checks", "Config", "Check the reputation of connecting addresses.", list("ip_reputation")),
		list("persistence", "Persistent data saved", "Config", "Persistent data is saved from now on.", list("togglepersistence")),
		list("hub", "Hub visibility", "Config", "The server shows on the BYOND hub.", list("togglehubvisibility")),
		list("guests", "Guests may enter", "Config", "Guest keys can join.", list("toggleguests")),
		list("welder_vision", "Tinted welding helmets", "Config", "Welding helmets reduce view range.", list("toggletintedweldhelmets")),
		list("href_log", "href logging", "Config", "Log the hrefs players use.", list("toggle_log_hrefs")),
))

/proc/admin_setting_table()
	return GLOB.admin_setting_rows

/// The live state of a setting row, as the checkbox shows it. Null for an id that is not in the table.
/proc/admin_setting_state(id)
	switch(id)
		if("ooc")
			return !!CONFIG_GET(flag/ooc_allowed)
		if("looc")
			return !!CONFIG_GET(flag/looc_allowed)
		if("dsay")
			return !!CONFIG_GET(flag/dsay_allowed)
		if("dooc")
			return !!CONFIG_GET(flag/dooc_allowed)
		if("enter")
			return !!CONFIG_GET(flag/enter_allowed)
		if("ai")
			return !!CONFIG_GET(flag/allow_ai)
		if("respawn")
			return !!CONFIG_GET(flag/abandon_allowed)
		if("aliens")
			return !!CONFIG_GET(flag/aliens_allowed)
		if("ninjas")
			return !!CONFIG_GET(flag/ninjas_allowed)
		if("traitor_scaling")
			return !!CONFIG_GET(flag/traitor_scaling)
		if("random_events")
			return !!CONFIG_GET(flag/allow_random_events)
		if("ghost_writers")
			return !!CONFIG_GET(flag/cult_ghostwriter)
		if("drones")
			return !!CONFIG_GET(flag/allow_drone_spawn)
		if("antaghud")
			return !!CONFIG_GET(flag/antag_hud_allowed)
		if("antaghud_restricted")
			return !!CONFIG_GET(flag/antag_hud_restricted)
		if("admin_jump")
			return !!CONFIG_GET(flag/allow_admin_jump)
		if("admin_spawn")
			return !!CONFIG_GET(flag/allow_admin_spawning)
		if("admin_revive")
			return !!CONFIG_GET(flag/allow_admin_rev)
		if("panic_bunker")
			return !!CONFIG_GET(flag/panic_bunker)
		if("paranoia")
			return !!CONFIG_GET(flag/paranoia_logging)
		if("ip_rep")
			return !!CONFIG_GET(flag/ip_reputation)
		if("persistence")
			return !CONFIG_GET(flag/persistence_disabled)
		if("hub")
			return !!world.visibility
		if("guests")
			return !!CONFIG_GET(flag/guests_allowed)
		if("welder_vision")
			return !!CONFIG_GET(flag/welder_vision)
		if("href_log")
			return !!CONFIG_GET(flag/log_hrefs)
	return null

/// The verb that flips a setting row for a holder with `rights`: the first of the row's verbs those rights allow, or null.
/proc/admin_setting_verb(list/row, rights, list/visibility_flags)
	for(var/verb_id in row[5])
		var/datum/admin_verb/V = SSadmin_verbs.browser_resolve(verb_id, rights, visibility_flags)
		if(V)
			return V
	return null

/// The rows of the settings panel for a client: label, group, state, and whether their rights allow flipping it.
/proc/admin_setting_rows(client/subject)
	var/rights = admin_rank_flags(subject)
	var/list/flags = SSadmin_verbs.visibility_flags_of(subject)
	var/list/rows = list()
	for(var/list/row as anything in admin_setting_table())
		rows += list(list(
			"id" = row[1],
			"label" = row[2],
			"group" = row[3],
			"desc" = row[4],
			"value" = admin_setting_state(row[1]),
			"can" = !!admin_setting_verb(row, rights, flags),
		))
	return rows

/// Flip a setting by running its verb as the admin. FALSE for an unknown row or rights that allow none of its verbs.
/proc/admin_setting_flip(client/subject, id)
	if(!admin_holder_of(subject))
		return FALSE
	for(var/list/row as anything in admin_setting_table())
		if(row[1] != id)
			continue
		var/datum/admin_verb/V = admin_setting_verb(row, admin_rank_flags(subject), SSadmin_verbs.visibility_flags_of(subject))
		if(!V)
			return FALSE
		SSadmin_verbs.dynamic_invoke_verb(subject, V.type)
		return TRUE
	return FALSE
