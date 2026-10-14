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
	rel_set(src, nameof(owner_admin), owner_admin)

// The admin holder owns this panel (tgui_game_panel); owner_admin is a plain relation back.

CAPABILITIES(/datum/game_panel)
	interface("GamePanel", title = "Game Panel", rights = R_ADMIN)
	op("change_mode", ui_act("change_mode"), then(PROC_REF(ui_act_change_mode)))
	op("force_secret", ui_act("force_secret"), then(PROC_REF(ui_act_force_secret)))
	op("spawn_panel", ui_act("spawn_panel"), then(PROC_REF(ui_act_spawn_panel)))
	op("vsc", ui_act("vsc", arg("setting", schema_text(4096))), then(PROC_REF(ui_act_vsc)))

/datum/game_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

/// /datum/game_panel's window data.
/datum/game_panel/ui_data(datum/act/eval/A)
	return list(
		"master_mode" = GLOB.master_mode,
		"secret_mode" = GLOB.master_mode == "secret",
	)

/datum/game_panel/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!owner_admin || !user?.client || !check_rights_for(user.client, R_ADMIN))
		return FALSE
	return TRUE

/datum/game_panel/proc/ui_act_change_mode(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	owner_admin.topic_internal(user, list("c_mode" = "1"))
	SStgui.update_uis(src)
	return TRUE

/datum/game_panel/proc/ui_act_force_secret(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	owner_admin.topic_internal(user, list("f_secret" = "1"))
	SStgui.update_uis(src)
	return TRUE

/datum/game_panel/proc/ui_act_spawn_panel(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	owner_admin.topic_internal(user, list("spawn_panel" = "1"))
	return TRUE

/datum/game_panel/proc/ui_act_vsc(datum/act/op/A, setting_arg)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/setting = "[setting_arg]"
	owner_admin.topic_internal(user, list("vsc" = setting))
	return TRUE

/datum/admins
	var/datum/game_panel/tgui_game_panel

/datum/admins/proc/open_game_panel(mob/user)
	if(!tgui_game_panel)
		rel_set(src, nameof(tgui_game_panel), new /datum/game_panel(src))
	tgui_game_panel.tgui_interact(user)
