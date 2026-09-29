// Game Panel — structured TGUI.
//
// The legacy /datum/admins/proc/Game() was a vertical list of 5–6
// labelled byond:// links. Each one forwarded to the existing
// /datum/admins/Topic handler; the structured panel does the same via
// tgui_act, with explicit buttons.

/datum/game_panel
	var/datum/admins/owner_admin

/datum/game_panel/New(datum/admins/owner_admin)
	..()
	rel_set(src, "owner_admin", owner_admin)

// The admin holder owns this panel (tgui_game_panel); owner_admin is a plain relation back.

DECLARE_UI_STATE(/datum/game_panel, ADMIN_STATE(R_ADMIN))

DECLARE_UI(/datum/game_panel, "GamePanel", UI_TITLE("Game Panel"))

/datum/game_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

UI_DATA_REPLACE(/datum/game_panel, "merge:ui_data_datum_game_panel{master_mode:unknown,secret_mode:bool}")

/// The computed part of /datum/game_panel's window data (declared on its UI_DATA row).
/datum/game_panel/proc/ui_data_datum_game_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list(
		"master_mode" = GLOB.master_mode,
		"secret_mode" = GLOB.master_mode == "secret",
	)

/datum/game_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!owner_admin || !ui.user?.client || !check_rights_for(ui.user.client, R_ADMIN))
		return FALSE
	return TRUE

UI_ACT(/datum/game_panel, "change_mode", ui_act_change_mode)
UI_ACT_PROC(/datum/game_panel, ui_act_change_mode)
	owner_admin.topic_internal(ui.user, list("c_mode" = "1"))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/game_panel, "force_secret", ui_act_force_secret)
UI_ACT_PROC(/datum/game_panel, ui_act_force_secret)
	owner_admin.topic_internal(ui.user, list("f_secret" = "1"))
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/game_panel, "spawn_panel", ui_act_spawn_panel)
UI_ACT_PROC(/datum/game_panel, ui_act_spawn_panel)
	owner_admin.topic_internal(ui.user, list("spawn_panel" = "1"))
	return TRUE

UI_ACT(/datum/game_panel, "vsc", ui_act_vsc, UI_ARG_TEXT("setting"))
UI_ACT_PROC(/datum/game_panel, ui_act_vsc)
	var/setting = "[params["setting"]]"
	owner_admin.topic_internal(ui.user, list("vsc" = setting))
	return TRUE

/datum/admins
	var/datum/game_panel/tgui_game_panel

/datum/admins/proc/open_game_panel(mob/user)
	if(!tgui_game_panel)
		own_set(src, "tgui_game_panel", new /datum/game_panel(src))
	tgui_game_panel.tgui_interact(user)
