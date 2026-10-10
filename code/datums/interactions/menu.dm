/**
 * The Menu action (doc/rewrite/interactions.md §7): a tgui context panel
 * listing the target's ops: what the player can do, and what they can't and why. It replaces BYOND's native right-click verb popup, so
 * it also lists the target's legacy verbs and the basic mob actions the popup
 * used to offer (examine, pull, point).
 */
/datum/interaction_menu
	/// The client using the menu: a one-sided back view (the client owns the menu).
	var/client/owner
	/// What the menu lists interactions for: a relation view.
	var/atom/target

/datum/interaction_menu/New(client/owner)
	rel_set(src, nameof(owner), owner)

/client/var/tmp/datum/interaction_menu/interaction_menu

/// Opens the Menu for `target`. Returns TRUE if it opened.
/proc/open_interaction_menu(mob/user, atom/target)
	if(!user?.client || !target)
		return FALSE
	var/client/player = user.client
	if(!player.interaction_menu)
		rel_set(player, nameof(/client::interaction_menu), new /datum/interaction_menu(player))
	rel_set(player.interaction_menu, nameof(/datum/accessory_stat_modifier::target), target)
	log_input("Input: [key_name(user)] opened the interaction menu on [target] ([target.type]).")
	player.interaction_menu.tgui_interact(user)
	return TRUE

/datum/interaction_menu/proc/target()
	return QDELETED(target) ? null : target

CAPABILITIES(/datum/interaction_menu)
	interface("InteractionMenu", state = nameof(GLOB.tgui_always_state))
	op("run", ui_act("run", arg("id", schema_text(4096))), then(PROC_REF(ui_act_run)))
	op("action", ui_act("action", arg("id", schema_text(4096))), then(PROC_REF(ui_act_action)))
	op("verb", ui_act("verb", arg("name", schema_text(4096))), then(PROC_REF(ui_act_verb)))

/// /datum/interaction_menu's window data.
/datum/interaction_menu/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/atom/target = target()
	if(!target)
		return list("target" = null)
	return interaction_menu_data(user, target)

/// The Menu's contents for `user` looking at `target`: the target's ops (op_menu(): enabled ones as available, the rest
/// as blocked with the reason), its legacy verbs and the basic mob actions. Split out so tests can read it.
/proc/interaction_menu_data(mob/user, atom/target)
	var/obj/item/held = user.get_active_hand()
	var/list/available = list()
	var/list/blocked = list()
	for(var/list/row as anything in op_menu(user, target, held))
		if(row["enabled"])
			available += list(list(
				"id" = row["key"],
				"name" = row["label"],
				"category" = null,
				"keys" = list(),
			))
		else
			blocked += list(list(
				"id" = row["key"],
				"name" = row["label"],
				"category" = null,
				"reason" = row["reason"],
			))
	var/list/verb_names = list()
	for(var/procpath/target_verb as anything in target.verbs)
		if(!target_verb || target_verb.hidden || !istext(target_verb.name) || copytext(target_verb.name, 1, 2) == ".")
			continue
		verb_names += target_verb.name
	sortTim(verb_names, GLOBAL_PROC_REF(cmp_text_asc))
	return list(
		"target" = capitalize(target.name),
		"available" = available,
		"blocked" = blocked,
		"actions" = interaction_menu_actions(user, target),
		"verbs" = verb_names,
	)

/// The mob actions the native popup offered for any target, as list(id, name).
/proc/interaction_menu_actions(mob/user, atom/target)
	. = list(list("id" = INPUT_ACTION_INSPECT, "name" = "Examine"))
	if(ismovable(target) && target != user && isliving(user))
		. += list(list("id" = INPUT_ACTION_PULL, "name" = "Pull"))
	if(target != user && isliving(user))
		. += list(list("id" = INPUT_ACTION_POINT, "name" = "Point at"))

/datum/interaction_menu/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/target = target()
	if(!user || !target)
		return FALSE
	return TRUE

/datum/interaction_menu/proc/ui_act_run(datum/act/op/A, id)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	if(!ui_gate(A))
		return FALSE
	var/atom/target = target()
	ui.close()
	run_chosen_op(user, target, id)
	return TRUE

/datum/interaction_menu/proc/ui_act_action(datum/act/op/A, id)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	if(!ui_gate(A))
		return FALSE
	var/atom/target = target()
	var/action_id = id
	var/valid = FALSE
	for(var/list/entry as anything in interaction_menu_actions(user, target))
		if(entry["id"] == action_id)
			valid = TRUE
			break
	if(!valid)
		return
	ui.close()
	var/datum/input_adapter/adapter = user.input_adapter()
	var/handler = adapter.handler_for(action_id)
	if(handler)
		call(user, handler)(target, "")
	return TRUE

/datum/interaction_menu/proc/ui_act_verb(datum/act/op/A, name)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	if(!ui_gate(A))
		return FALSE
	var/atom/target = target()
	var/verb_name = name
	if(!interaction_menu_can_reach(user, target))
		to_chat(user, span_warning("You are too far from \the [target]."))
		return
	for(var/procpath/target_verb as anything in target.verbs)
		if(target_verb?.name != verb_name || target_verb.hidden)
			continue
		ui.close()
		log_input("Input: [key_name(user)] used the verb [verb_name] on [target] ([target.type]) from the interaction menu.")
		call(target, target_verb)()
		return TRUE

/// Runs the op `key` of `target` chosen in the Menu (ORIGIN_MENU), with what the user holds. TRUE when it ran or started.
/proc/run_chosen_op(mob/user, atom/target, key)
	if(!user || !target || !istext(key))
		return FALSE
	var/datum/op_result/result = perform_op(user, target, key, user.get_active_hand(), ORIGIN_MENU)
	return result && result.outcome != ACT_REFUSED

/// Whether a legacy verb on `target` can be run from the Menu: the popup offered verbs on things in reach.
/proc/interaction_menu_can_reach(mob/user, atom/target)
	if(target == user || get(target, /mob) == user)
		return TRUE
	return user.Adjacent(target)

/// The Menu key: opens the Menu on the hovered atom, or the tile in front of the player.
/client/verb/input_menu()
	set name = ".input-menu"
	set hidden = TRUE
	set instant = FALSE

	if(!mob)
		return
	var/atom/target = hovered_atom() || get_step(mob, mob.dir)
	if(target)
		open_interaction_menu(mob, target)

/// The client using the menu.
/datum/interaction_menu/proc/owner() as /client
	return owner

