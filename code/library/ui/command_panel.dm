// The command panel: one console-themed window that lists the commands of a mob (an AI's camera and station commands, a cyborg's
// subsystems, a malfunctioning AI's hacks, ...) in groups, and runs the one the player presses. It replaces the verb tabs those
// commands used to fill. A command is a proc of the mob (a TYPE_PROC_REF the panel calls with no arguments; a command that needs
// an answer asks for it itself, with a typed prompt), so it behaves the same from the panel, from a HUD button and from code.
//
// The commands of a mob type are a GLOBAL_LIST_INIT of panel_command() rows. Opening is command_panel_open(); a mob type gives the
// player one verb or one HUD button for it.

/// One row of a mob type's command list: the id the window sends back, the button label, its hover text, the group it sits under and
/// the proc of the owner it calls.
/// `shown` is an optional proc of the owner called with the command id: the command is listed only while it returns true.
/proc/panel_command(id, label, desc, group, command_proc, shown = null)
	return list("id" = id, "label" = label, "desc" = desc, "group" = group, "proc" = command_proc, "shown" = shown)

/// Open panels: "<owner handle>/<key>" -> the panel's handle_of (a deleted panel stops resolving).
GLOBAL_ALIST_EMPTY(command_panels)

/datum/command_panel
	/// The mob the commands belong to; only they can press the buttons.
	var/mob/owner
	/// The window title.
	var/title
	/// The panel_command() rows.
	var/list/commands
	/// The key under which the owner's panel of this kind is remembered.
	var/panel_key
	/// A proc of the owner returning null while the commands may be used, else the reason they cannot (a dead AI), or null for no gate.
	var/gate_proc

/datum/command_panel/New(mob/owner_mob, panel_key_text, panel_title, list/panel_commands, gate)
	rel_set(src, nameof(owner), owner_mob)
	panel_key = panel_key_text
	title = panel_title
	commands = panel_commands
	gate_proc = gate

/// Phase 2: leaves the panel index.
/datum/command_panel/lifecycle_dematerialize()
	. = ..()
	if(owner)
		GLOB.command_panels -= "[handle_text(handle_of(owner))]/[panel_key]"

CAPABILITIES(/datum/command_panel)
	ref_one(nameof(owner), /mob)
	interface("CommandPanel", title = "Commands", state = nameof(GLOB.tgui_always_state))
	op("run_command", ui_act("run_command", arg("id", schema_text(64))), then(PROC_REF(ui_act_run_command)))

/datum/command_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!owner || user != owner)
		return FALSE
	return TRUE

/// Why the commands cannot be used now, or null.
/datum/command_panel/proc/blocked_reason()
	if(!owner || !gate_proc)
		return null
	return call(owner, gate_proc)()

/// /datum/command_panel's window data.
/datum/command_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["title"] = title
	data["blocked"] = blocked_reason()
	var/list/groups = list()
	var/list/by_group = list()
	for(var/list/entry as anything in commands)
		if(!entry_shown(entry))
			continue
		var/list/group = by_group[entry["group"]]
		if(!group)
			group = list("title" = entry["group"], "commands" = list())
			by_group[entry["group"]] = group
			groups += list(group)
		group["commands"] += list(list("id" = entry["id"], "label" = entry["label"], "desc" = entry["desc"]))
	data["groups"] = groups
	return data

/// Is this command listed for the owner now?
/datum/command_panel/proc/entry_shown(list/entry)
	if(!entry["shown"])
		return TRUE
	return call(owner, entry["shown"])(entry["id"])

/datum/command_panel/proc/ui_act_run_command(datum/act/op/A, id)
	return run_command(A.actor, id)

/// Runs the command with this id for the owner; FALSE when the presser is not the owner, the commands are blocked or there is no such command.
/datum/command_panel/proc/run_command(mob/user, id)
	if(!owner || user != owner || blocked_reason())
		return FALSE
	for(var/list/entry as anything in commands)
		if(entry["id"] == id && entry_shown(entry))
			call(owner, entry["proc"])()
			SStgui.update_uis(src)
			return TRUE
	return FALSE

/// Opens (making it on the first call) the panel of `user` kept under `key`: `commands` are its panel_command() rows and `gate` the
/// optional proc of the user that says why they cannot be used.
/proc/command_panel_open(mob/user, key, title, list/commands, gate = null)
	if(!istype(user))
		return
	var/index = "[handle_text(handle_of(user))]/[key]"
	var/datum/command_panel/panel = handle_get(ALAZYACCESS(GLOB.command_panels, index))
	if(!panel)
		panel = new(user, key, title, commands, gate)
		GLOB.command_panels[index] = handle_of(panel)
	panel.tgui_interact(user)
