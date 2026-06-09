// Structured TGUI player panel — replaces the legacy
// /datum/admins/proc/player_panel_new() HTML+JS table. Each player
// row ships as structured data; React renders a filterable list with
// per-player action buttons (Edit / PM / Traitor?). No JS-driven
// in-browser filter; React handles the filter natively.

/datum/player_panel
	var/datum/admins/owner_admin
	var/list/cached_players

/datum/player_panel/New(datum/admins/owner_admin)
	..()
	src.owner_admin = owner_admin

/datum/player_panel/Destroy()
	if(owner_admin?.tgui_player_panel == src)
		owner_admin.tgui_player_panel = null
	owner_admin = null
	cached_players = null
	return ..()

/datum/player_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_HOLDER)

/datum/player_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		snapshot_players()
		ui = new(user, src, "PlayerPanel", "Player Panel")
		ui.open()

/datum/player_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	qdel(src)

/datum/player_panel/proc/snapshot_players()
	var/list/players = list()
	for(var/mob/M in sort_mobs())
		if(!M.ckey)
			continue
		var/job = "Unknown"
		if(isliving(M))
			if(iscarbon(M))
				if(ishuman(M))
					job = M.job
				else if(isslime(M))
					job = JOB_SLIME
				else if(issmall(M))
					job = JOB_MONKEY
				else if(isalien(M))
					job = JOB_ALIEN
				else
					job = JOB_CARBON_BASED
			else if(issilicon(M))
				if(isAI(M))
					job = JOB_AI
				else if(ispAI(M))
					job = JOB_PAI
				else if(isrobot(M))
					job = JOB_CYBORG
				else
					job = JOB_SILICON_BASED
			else if(isanimal(M))
				if(iscorgi(M))
					job = JOB_CORGI
				else
					job = JOB_ANIMAL
			else
				job = JOB_LIVING
		else if(isnewplayer(M))
			job = JOB_NEW_PLAYER
		else if(isobserver(M))
			job = JOB_GHOST
		players += list(list(
			"name" = M.name,
			"real_name" = M.real_name,
			"key" = M.key,
			"connected" = !!M.client,
			"job" = job,
			"is_antagonist" = is_special_character(M),
			"ref" = "\ref[M]",
			"ip" = M.lastKnownIP,
		))
	cached_players = players

/datum/player_panel/tgui_data(mob/user)
	return list("players" = cached_players || list())

/datum/player_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!owner_admin)
		return
	var/mob/target = locate(params["ref"])
	if(!ismob(target))
		return
	switch(action)
		if("admin_opts")
			if(ui.user?.client)
				SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/show_player_panel, target)
			return TRUE
		if("private_message")
			if(ui.user?.client)
				ui.user.client.cmd_admin_pm(target)
			return TRUE
		if("traitor")
			if(!SSticker || !SSticker.mode)
				tgui_alert_async(ui.user, "The game hasn't started yet!")
				return TRUE
			if(ui.user?.client)
				SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/show_traitor_panel, target)
			SStgui.update_uis(src)
			return TRUE
		if("check_antagonists")
			owner_admin.open_round_status_panel(ui.user)
			return TRUE
		if("refresh")
			snapshot_players()
			SStgui.update_uis(src)
			return TRUE


/datum/admins
	var/datum/player_panel/tgui_player_panel

/datum/admins/proc/open_player_panel_tgui(client/user)
	if(!check_rights_for(user, R_HOLDER))
		return
	if(!tgui_player_panel)
		tgui_player_panel = new(src)
	tgui_player_panel.tgui_interact(user.mob)
