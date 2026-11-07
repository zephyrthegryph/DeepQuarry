// The command panel: one console-themed window that lists the commands of a mob (an AI's camera and station commands, a cyborg's
// subsystems, a malfunctioning AI's hacks, ...) in groups, and runs the one the player presses. It replaces the verb tabs those
// commands used to fill. A command is a proc of the mob (a TYPE_PROC_REF the panel calls with no arguments; a command that needs
// an answer asks for it itself, with a typed prompt), so it behaves the same from the panel, from a HUD button and from code.
//
// The commands of a mob type are a GLOBAL_LIST_INIT of panel_command() rows. Opening is command_panel_open(); a mob type gives the
// player one verb or one HUD button for it.

/// A `shown` value: the command is listed while its proc is among the owner's verbs, that is while the owner has been granted it (a proc with no
/// `set category` is no tab entry, so what a species, trait or mob type grants appears here and not in the verb panel).
#define PANEL_IF_GRANTED "granted"

/// One row of a mob type's command list: the id the window sends back, the button label, its hover text, the group it sits under and
/// the proc of the owner it calls.
/// `shown` is an optional proc of the owner called with the command id: the command is listed only while it returns true.
/// `targets` is an optional proc of the owner returning the list of things the command can be used on (the old `M as mob in oview()` argument): pressing
/// the command asks the owner to pick one and calls the command's proc with it.
/proc/panel_command(id, label, desc, group, command_proc, shown = null, targets = null)
	return list("id" = id, "label" = label, "desc" = desc, "group" = group, "proc" = command_proc, "shown" = shown, "targets" = targets)

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
	op("run_command", ui_act("run_command", arg("id", schema_text(160))), then(PROC_REF(ui_act_run_command)))

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
	if(entry["shown"] == PANEL_IF_GRANTED)
		return granted_command_listed(entry)
	return call(owner, entry["shown"])(entry["id"])

/// A PANEL_IF_GRANTED command has no proc reference: its id is the proc's path with dots for slashes ("mob.living.carbon.human.proc.hatch").
/// It is listed while that proc is among the owner's verbs.
/datum/command_panel/proc/granted_command_listed(list/entry)
	var/wanted = "/[replacetext(entry["id"], ".", "/")]"
	for(var/granted_verb in owner.verbs)
		if("[granted_verb]" == wanted)
			return TRUE
	return FALSE

/// The name of the proc a PANEL_IF_GRANTED command calls: the last part of its id.
/datum/command_panel/proc/granted_command_proc_name(list/entry)
	var/list/parts = splittext(entry["id"], ".")
	return parts[length(parts)]

/datum/command_panel/proc/ui_act_run_command(datum/act/op/A, id)
	return run_command(A.actor, id)

/// Runs the command with this id for the owner; FALSE when the presser is not the owner, the commands are blocked or there is no such command.
/datum/command_panel/proc/run_command(mob/user, id)
	if(!owner || user != owner || blocked_reason())
		return FALSE
	for(var/list/entry as anything in commands)
		if(entry["id"] == id && entry_shown(entry))
			if(entry["targets"])
				ask_target(entry)
			else
				invoke_command(entry)
			SStgui.update_uis(src)
			return TRUE
	return FALSE

/// Calls the command's proc on the owner, with the target a picker chose (none for a command without a picker).
/datum/command_panel/proc/invoke_command(list/entry, atom/target = null)
	var/proc_ref = entry["shown"] == PANEL_IF_GRANTED ? granted_command_proc_name(entry) : entry["proc"]
	if(target)
		call(owner, proc_ref)(target)
	else
		call(owner, proc_ref)()

/// The things the command can be used on, by the names the picker lists them under (a second one of the same name gets a number).
/datum/command_panel/proc/target_choices(list/entry)
	var/list/choices = list()
	for(var/atom/candidate as anything in call(owner, entry["targets"])())
		if(QDELETED(candidate))
			continue
		var/name = "[candidate]"
		var/number = 1
		while(choices[name])
			number++
			name = "[candidate] ([number])"
		choices[name] = candidate
	return choices

/// Asks the owner what to use the command on.
/datum/command_panel/proc/ask_target(list/entry)
	var/list/choices = target_choices(entry)
	if(!length(choices))
		to_chat(owner, span_warning("There is nothing in reach to use that on."))
		return
	open_request(src, /datum/prompt/choice/panel_target, PROC_REF(target_chosen), answerer = owner, title = entry["label"], question = entry["desc"], choices = assoc_to_keys(choices), command_id = entry["id"])

/// The picker's answer: the command runs on the thing picked, if it is still there.
/datum/command_panel/proc/target_chosen(datum/act/request/A)
	if(!A.answer || !owner || blocked_reason())
		return
	var/datum/prompt/choice/panel_target/ask = A.request
	for(var/list/entry as anything in commands)
		if(entry["id"] != ask.command_id || !entry_shown(entry))
			continue
		var/atom/target = target_choices(entry)[A.answer.value]
		if(!target)
			to_chat(owner, span_warning("That is no longer in reach."))
			return
		invoke_command(entry, target)
		SStgui.update_uis(src)
		return

/// Which thing to use a panel command on; carries the command it was asked for.
/datum/prompt/choice/panel_target
	timeout = 0
	var/command_id

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
