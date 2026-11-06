// The ghost panel: every ghost command in one TGUI window (console theme). It replaces the Ghost.Game, Ghost.Join, Ghost.Message
// and Ghost.Settings verbs, which are plain procs of the observer now; the panel's buttons call them, so what a command does,
// and what it refuses, is the proc's own business and is the same from the panel, the ghost HUD and the double click.

#define GHOST_ACT_REENTER "reenter_corpse"
#define GHOST_ACT_TELEPORT "dead_tele"
#define GHOST_ACT_FOLLOW "follow"
#define GHOST_ACT_JUMP "jumptomob"
#define GHOST_ACT_AIR "analyze_air"
#define GHOST_ACT_MANIFEST "view_manifest"
#define GHOST_ACT_DOODLE "bloody_doodle"
#define GHOST_ACT_RESPAWN "respawn"
#define GHOST_ACT_BACKUP_PING "backup_ping"
#define GHOST_ACT_BACKUP_DELAY "backup_delay"
#define GHOST_ACT_SPAWN_MENU "ghost_spawn"
#define GHOST_ACT_RESLEEVER "find_resleever"
#define GHOST_ACT_TEXT_COMM "text_communicator"
#define GHOST_ACT_CALL_COMM "call_communicator"
#define GHOST_ACT_PAI_ALERT "pai_alert"
#define GHOST_ACT_SPRITE "choose_sprite"
#define GHOST_SET_INQUISITIVE "toggle_inquisition"
#define GHOST_SET_MEDHUD "toggle_medhud"
#define GHOST_SET_SECHUD "toggle_sechud"
#define GHOST_SET_ANTAGHUD "toggle_antaghud"
#define GHOST_SET_INTERACTIONS "toggle_interactions"
#define GHOST_SET_VISIBILITY "toggle_visibility"
#define GHOST_SET_ANONSAY "toggle_anonsay"
#define GHOST_SET_GHOSTSEE "toggle_ghostsee"
#define GHOST_SET_DARKNESS "toggle_darkness"

/// Open panels: ghost key -> the panel's handle_of (a deleted panel stops resolving).
GLOBAL_ALIST_EMPTY(dq_ghost_panels)

/datum/ghost_panel
	var/mob/observer/dead/ghost

/datum/ghost_panel/New(mob/observer/dead/ghost_mob)
	rel_set(src, nameof(ghost), ghost_mob)

/// Phase 2: leaves the per-ghost panel index.
/datum/ghost_panel/lifecycle_dematerialize()
	. = ..()
	if(ghost)
		GLOB.dq_ghost_panels -= handle_of(ghost)

CAPABILITIES(/datum/ghost_panel)
	ref_one(nameof(ghost), /mob/observer/dead)
	interface("GhostPanel", title = "Ghost Panel", state = nameof(GLOB.tgui_always_state))
	op("ghost_do", ui_act("ghost_do", arg("action", schema_text(32))), then(PROC_REF(ui_act_ghost_do)))

/datum/ghost_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!ghost || user != ghost)
		return FALSE
	return TRUE

/// The buttons of the panel, by group: id, label and what it does. A ghost command is one more row here and one more case in run_action().
GLOBAL_LIST_INIT(ghost_panel_actions, list(
	list("Game", list(
		list(GHOST_ACT_REENTER, "Re-enter Corpse", "Go back into your body, if you still have one."),
		list(GHOST_ACT_TELEPORT, "Teleport", "Teleport to an area."),
		list(GHOST_ACT_FOLLOW, "Follow", "Follow and haunt a mob."),
		list(GHOST_ACT_JUMP, "Jump to Mob", "Teleport to a mob."),
		list(GHOST_ACT_AIR, "Analyze Air", "Read the air where you float."),
		list(GHOST_ACT_MANIFEST, "Show Crew Manifest", "See who is on the crew."),
		list(GHOST_ACT_SPRITE, "Choose Sprite", "Pick how your ghost looks."),
		list(GHOST_ACT_DOODLE, "Write in Blood", "If the round is sufficiently spooky, write a short message in blood on the floor or a wall. Remember, no IC in OOC or OOC in IC."),
	)),
	list("Join", list(
		list(GHOST_ACT_RESPAWN, "Respawn", "Leave this ghost and return to the lobby."),
		list(GHOST_ACT_SPAWN_MENU, "Ghost Spawn", "Open the ghost spawn menu."),
		list(GHOST_ACT_RESLEEVER, "Find Auto Resleever", "Find an auto resleever and go to it."),
		list(GHOST_ACT_BACKUP_PING, "Notify Transcore", "If your past-due backup notification was missed or ignored, send a new one."),
		list(GHOST_ACT_BACKUP_DELAY, "Cancel Transcore Notification", "Avoid the automatic backup notification. Manual notification can still be used."),
	)),
	list("Message", list(
		list(GHOST_ACT_TEXT_COMM, "Text Communicator", "If there is a communicator available, send a text message to it."),
		list(GHOST_ACT_CALL_COMM, "Call Communicator", "If there is a communicator available, send a request to speak through it. This resets your respawn timer if someone picks up."),
		list(GHOST_ACT_PAI_ALERT, "Blank pAI Alert", "Flash an indicator light on available blank pAI devices for a smidgen of hope."),
	)),
))

/datum/ghost_panel/proc/action_groups()
	return GLOB.ghost_panel_actions

/// One toggle of the panel as the window reads it.
/datum/ghost_panel/proc/toggle_row(id, label, desc, value, can = TRUE, why = null, text = null)
	return list("id" = id, "label" = label, "desc" = desc, "value" = value, "can" = can, "why" = why, "text" = text)

/// /datum/ghost_panel's window data.
/datum/ghost_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["groups"] = list()
	data["toggles"] = list()
	data["notice"] = null
	if(!ghost)
		return data
	var/list/groups = list()
	for(var/list/group as anything in action_groups())
		var/list/rows = list()
		for(var/list/entry as anything in group[2])
			var/enabled = TRUE
			var/why = null
			if(entry[1] == GHOST_ACT_REENTER && !(ghost.mind && ghost.mind.current && ghost.can_reenter_corpse))
				enabled = FALSE
				why = "You have no body to go back to."
			rows += list(list("id" = entry[1], "label" = entry[2], "desc" = entry[3], "enabled" = enabled, "why" = why))
		groups += list(list("title" = group[1], "actions" = rows))
	data["groups"] = groups

	var/antag_hud_open = CONFIG_GET(flag/antag_hud_allowed) || check_rights_for(ghost.client, R_HOLDER)
	var/list/toggles = list()
	toggles += list(toggle_row(GHOST_SET_MEDHUD, "Medical HUD", "See how everyone is doing.", ghost.medHUD))
	toggles += list(toggle_row(GHOST_SET_SECHUD, "Security HUD", "See people's displayed ID, job, wanted status and so on.", ghost.secHUD))
	toggles += list(toggle_row(GHOST_SET_ANTAGHUD, "AntagHUD", "See who the antagonists are.", ghost.antagHUD, antag_hud_open, "Admins have disabled this for this round."))
	toggles += list(toggle_row(GHOST_SET_INTERACTIONS, "Interactions", "Allow the corporeal world to interact with you.", ghost.interact_with_world, !ghost.is_manifest, "You are manifested into the world and cannot toggle this."))
	toggles += list(toggle_row(GHOST_SET_VISIBILITY, "Visibility", "Turn (in)visible, almost at will.", ghost.plane == PLANE_WORLD, ghost.is_manifest, "You are not strong enough to pierce the veil."))
	toggles += list(toggle_row(GHOST_SET_ANONSAY, "Anonymous Chat", "Hide your key in dead chat.", ghost.anonsay))
	toggles += list(toggle_row(GHOST_SET_GHOSTSEE, "Ghost Vision", "See things only ghosts can see, like other ghosts.", ghost.ghostvision))
	toggles += list(toggle_row(GHOST_SET_DARKNESS, "Darkness", "Cycle how much of the lighting darkness you see through.", ghost.lighting_alpha != 255, TRUE, null, ghost.darkness_label()))
	toggles += list(toggle_row(GHOST_SET_INQUISITIVE, "Inquisitiveness", "Examine everything you click on by default.", ghost.client?.inquisitive_ghost))
	data["toggles"] = toggles
	return data

/// The darkness level the toggle shows.
/mob/observer/dead/proc/darkness_label()
	switch(lighting_alpha)
		if(178)
			return "30% removed"
		if(76)
			return "70% removed"
		if(0)
			return "None"
	return "Normal"

/datum/ghost_panel/proc/ui_act_ghost_do(datum/act/op/A, action)
	return run_action(A.actor, action)

/// Runs one panel action for the ghost that pressed it; FALSE when it is not this panel's ghost or the action is unknown.
/datum/ghost_panel/proc/run_action(mob/user, action)
	if(!ghost || user != ghost)
		return FALSE
	switch(action)
		if(GHOST_ACT_REENTER)
			ghost.reenter_corpse()
		if(GHOST_ACT_TELEPORT)
			ghost.dead_tele()
		if(GHOST_ACT_FOLLOW)
			ghost.follow()
		if(GHOST_ACT_JUMP)
			ghost.jumptomob()
		if(GHOST_ACT_AIR)
			ghost.analyze_air()
		if(GHOST_ACT_MANIFEST)
			ghost.view_manfiest()
		if(GHOST_ACT_DOODLE)
			ghost.bloody_doodle()
		if(GHOST_ACT_RESPAWN)
			ghost.respawn()
		if(GHOST_ACT_BACKUP_PING)
			ghost.backup_ping()
		if(GHOST_ACT_BACKUP_DELAY)
			ghost.backup_delay()
		if(GHOST_ACT_SPAWN_MENU)
			ghost.findghostpod()
		if(GHOST_ACT_RESLEEVER)
			ghost.findautoresleever()
		if(GHOST_ACT_TEXT_COMM)
			ghost.text_communicator()
		if(GHOST_ACT_CALL_COMM)
			ghost.join_as_voice()
		if(GHOST_ACT_PAI_ALERT)
			ghost.paialert()
		if(GHOST_ACT_SPRITE)
			ghost.choose_ghost_sprite()
		if(GHOST_SET_INQUISITIVE)
			ghost.toggle_inquisition()
		if(GHOST_SET_MEDHUD)
			ghost.toggle_medHUD()
		if(GHOST_SET_SECHUD)
			ghost.toggle_secHUD()
		if(GHOST_SET_ANTAGHUD)
			ghost.toggle_antagHUD()
		if(GHOST_SET_INTERACTIONS)
			ghost.toggle_interactions()
		if(GHOST_SET_VISIBILITY)
			ghost.toggle_visibility()
		if(GHOST_SET_ANONSAY)
			ghost.toggle_anonsay()
		if(GHOST_SET_GHOSTSEE)
			ghost.toggle_ghostsee()
		if(GHOST_SET_DARKNESS)
			ghost.toggle_darkness()
		else
			return FALSE
	SStgui.update_uis(src)
	return TRUE

/// The one ghost verb: opens the ghost panel.
/mob/observer/dead/verb/ghost_panel()
	set name = "Ghost Panel"
	set desc = "Every ghost command in one window: teleport, follow, respawn, the HUDs and the settings."
	set category = VERB_CAT_GHOST_GAME

	open_ghost_panel()

/mob/observer/dead/proc/open_ghost_panel()
	var/key = handle_of(src)
	var/datum/ghost_panel/panel = handle_get(ALAZYACCESS(GLOB.dq_ghost_panels, key))
	if(!panel)
		panel = new(src)
		GLOB.dq_ghost_panels[key] = handle_of(panel)
	panel.tgui_interact(src)
