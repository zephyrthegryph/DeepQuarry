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
	src.owner_admin = owner_admin

/datum/game_panel/Destroy()
	if(owner_admin?.tgui_game_panel == src)
		owner_admin.tgui_game_panel = null
	owner_admin = null
	return ..()

/datum/game_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

/datum/game_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GamePanel", "Game Panel")
		ui.open()

/datum/game_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/game_panel/tgui_data(mob/user)
	return list(
		"master_mode" = GLOB.master_mode,
		"secret_mode" = GLOB.master_mode == "secret",
	)

/datum/game_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!owner_admin || !check_rights(R_ADMIN))
		return

	switch(action)
		if("change_mode")
			owner_admin.Topic("c_mode=1", list("c_mode" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("force_secret")
			owner_admin.Topic("f_secret=1", list("f_secret" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("spawn_panel")
			owner_admin.Topic("spawn_panel=1", list("spawn_panel" = "1"))
			return TRUE
		if("vsc")
			var/setting = "[params["setting"]]"
			owner_admin.Topic("vsc=[setting]", list("vsc" = setting))
			return TRUE


/datum/admins
	var/datum/game_panel/tgui_game_panel

/datum/admins/proc/open_game_panel(mob/user)
	if(!tgui_game_panel)
		tgui_game_panel = new(src)
	tgui_game_panel.tgui_interact(user)
