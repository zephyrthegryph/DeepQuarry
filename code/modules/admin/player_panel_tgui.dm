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
	rel_set(src, nameof(owner_admin), owner_admin)

// The admin holder owns this panel (tgui_player_panel); owner_admin is a plain relation back.

CAPABILITIES(/datum/player_panel)
	interface("PlayerPanel", title = "Player Panel", rights = R_HOLDER)
	op("admin_opts", ui_act("admin_opts", arg("ref", schema_ref(/mob))), then(PROC_REF(ui_act_admin_opts)))
	op("private_message", ui_act("private_message", arg("ref", schema_ref(/mob))), then(PROC_REF(ui_act_private_message)))
	op("traitor", ui_act("traitor", arg("ref", schema_ref(/mob))), then(PROC_REF(ui_act_traitor)))
	op("check_antagonists", ui_act("check_antagonists", arg("ref", schema_ref(/mob))), then(PROC_REF(ui_act_check_antagonists)))
	op("refresh", ui_act("refresh", arg("ref", schema_ref(/mob))), then(PROC_REF(ui_act_refresh)))

/datum/player_panel/ui_opening(mob/user, datum/tgui/ui)
	snapshot_players()

/datum/player_panel/tgui_close(mob/user)
	SStgui.close_uis(src)
	spent(src, user)

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

/// /datum/player_panel's window data.
/datum/player_panel/ui_data(datum/act/eval/A)
	return list("players" = shown_players || list())

/datum/player_panel/proc/ui_gate(datum/act/op/A)
	if(!owner_admin)
		return FALSE
	return TRUE

/datum/player_panel/proc/ui_act_admin_opts(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/mob/target = ref
	if(!ismob(target))
		return FALSE
	if(user?.client)
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, target)
	return TRUE

/datum/player_panel/proc/ui_act_private_message(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/mob/target = ref
	if(!ismob(target))
		return FALSE
	if(user?.client)
		user.client.cmd_admin_pm(target)
	return TRUE

/datum/player_panel/proc/ui_act_traitor(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/mob/target = ref
	if(!ismob(target))
		return FALSE
	if(!SSticker || !ticker_mode())
		tgui_alert_async(user, "The game hasn't started yet!")
		return TRUE
	if(user?.client)
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_traitor_panel, target)
	SStgui.update_uis(src)
	return TRUE

/datum/player_panel/proc/ui_act_check_antagonists(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/mob/target = ref
	if(!ismob(target))
		return FALSE
	owner_admin.open_round_status_panel(user)
	return TRUE

/datum/player_panel/proc/ui_act_refresh(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/mob/target = ref
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
		rel_set(src, nameof(tgui_player_panel), new /datum/player_panel(src))
	tgui_player_panel.tgui_interact(user.mob)
