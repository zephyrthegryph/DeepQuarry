// Structured TGUI player panel — replaces the legacy
// /datum/admins/proc/player_panel_new() HTML+JS table. Each player
// row ships as structured data; React renders a filterable list with
// per-player action buttons (Edit / PM / Traitor?). No JS-driven
// in-browser filter; React handles the filter natively.

/datum/player_panel
	var/datum/admins/owner_admin
	var/list/shown_players

/datum/player_panel/New(datum/admins/owner_admin)
	..()
	src.owner_admin = owner_admin

DECLARE_REF(/datum/player_panel, "owner_admin", PAIR, "tgui_player_panel")
DECLARE_REF(/datum/admins, "tgui_player_panel", PAIR, "owner_admin")

/datum/player_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_HOLDER)

DECLARE_UI(/datum/player_panel, "PlayerPanel", UI_TITLE("Player Panel"))

/datum/player_panel/ui_opening(mob/user, datum/tgui/ui)
	snapshot_players()

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
	shown_players = players

/datum/player_panel/tgui_data(mob/user)
	return list("players" = shown_players || list())

/datum/player_panel/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!owner_admin)
		return FALSE
	return TRUE

UI_ACT(/datum/player_panel, "admin_opts", ui_act_admin_opts, UI_ARG_REF("ref", null, /mob))
UI_ACT_PROC(/datum/player_panel, ui_act_admin_opts)
	var/mob/target = params["ref"]
	if(!ismob(target))
		return FALSE
	if(ui.user?.client)
		SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/show_player_panel, target)
	return TRUE

UI_ACT(/datum/player_panel, "private_message", ui_act_private_message, UI_ARG_REF("ref", null, /mob))
UI_ACT_PROC(/datum/player_panel, ui_act_private_message)
	var/mob/target = params["ref"]
	if(!ismob(target))
		return FALSE
	if(ui.user?.client)
		ui.user.client.cmd_admin_pm(target)
	return TRUE

UI_ACT(/datum/player_panel, "traitor", ui_act_traitor, UI_ARG_REF("ref", null, /mob))
UI_ACT_PROC(/datum/player_panel, ui_act_traitor)
	var/mob/target = params["ref"]
	if(!ismob(target))
		return FALSE
	if(!SSticker || !SSticker.mode)
		tgui_alert_async(ui.user, "The game hasn't started yet!")
		return TRUE
	if(ui.user?.client)
		SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/show_traitor_panel, target)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/player_panel, "check_antagonists", ui_act_check_antagonists, UI_ARG_REF("ref", null, /mob))
UI_ACT_PROC(/datum/player_panel, ui_act_check_antagonists)
	var/mob/target = params["ref"]
	if(!ismob(target))
		return FALSE
	owner_admin.open_round_status_panel(ui.user)
	return TRUE

UI_ACT(/datum/player_panel, "refresh", ui_act_refresh, UI_ARG_REF("ref", null, /mob))
UI_ACT_PROC(/datum/player_panel, ui_act_refresh)
	var/mob/target = params["ref"]
	if(!ismob(target))
		return FALSE
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
