/**
 * The Menu action (doc/rewrite/interactions.md §7): a tgui context panel
 * listing what the player can do to a target, what they can't and why, and the
 * keys that reach each. It replaces BYOND's native right-click verb popup, so
 * it also lists the target's legacy verbs and the basic mob actions the popup
 * used to offer (examine, pull, point).
 */
/datum/interaction_menu
	var/owner_handle
	var/target_ref

/datum/interaction_menu/New(client/owner)
	src.owner_handle = om_handle(owner)

// clears the client's back-reference (clients aren't datums).
DECLARE_REF(/datum/interaction_menu, "owner_handle", BACK_HANDLE, "interaction_menu")

/client/var/tmp/datum/interaction_menu/interaction_menu

/// Opens the Menu for `target`. Returns TRUE if it opened.
/proc/open_interaction_menu(mob/user, atom/target)
	if(!user?.client || !target)
		return FALSE
	var/client/player = user.client
	if(!player.interaction_menu)
		player.interaction_menu = new(player)
	player.interaction_menu.target_ref = om_handle(target)
	log_input("Input: [key_name(user)] opened the interaction menu on [target] ([target.type]).")
	player.interaction_menu.tgui_interact(user)
	return TRUE

/datum/interaction_menu/proc/target()
	var/atom/target = om_resolve(target_ref)
	return QDELETED(target) ? null : target

DECLARE_UI_STATE(/datum/interaction_menu, GLOB.tgui_always_state)

DECLARE_UI(/datum/interaction_menu, "InteractionMenu")

UI_DATA_REPLACE(/datum/interaction_menu, "merge:ui_data_datum_interaction_menu{}")

/// The computed part of /datum/interaction_menu's window data (declared on its UI_DATA row).
/datum/interaction_menu/proc/ui_data_datum_interaction_menu(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/atom/target = target()
	if(!target)
		return list("target" = null)
	return interaction_menu_data(user, target)

/// The Menu's contents for `user` looking at `target`. Split out so tests can read it.
/proc/interaction_menu_data(mob/user, atom/target)
	var/datum/interaction_resolution/resolution = interactions_for(user, target, user.get_active_hand())
	var/list/available = list()
	for(var/datum/interaction/interaction as anything in resolution.available)
		available += list(list(
			"id" = interaction.id,
			"name" = interaction.display_name(user, target),
			"category" = interaction.category,
			"keys" = interaction_keys(user.client, resolution, interaction),
		))
	var/list/blocked = list()
	for(var/datum/interaction/interaction as anything in resolution.blocked)
		blocked += list(list(
			"id" = interaction.id,
			"name" = interaction.display_name(user, target),
			"category" = interaction.category,
			"reason" = resolution.blocked[interaction],
		))
	var/list/verbs = list()
	for(var/procpath/target_verb as anything in target.verbs)
		if(!target_verb || target_verb.hidden || !istext(target_verb.name) || copytext(target_verb.name, 1, 2) == ".")
			continue
		verbs += target_verb.name
	sortTim(verbs, GLOBAL_PROC_REF(cmp_text_asc))
	return list(
		"target" = capitalize(target.name),
		"available" = available,
		"blocked" = blocked,
		"actions" = interaction_menu_actions(user, target),
		"verbs" = verbs,
	)

/// The mob actions the native popup offered for any target, as list(id, name).
/proc/interaction_menu_actions(mob/user, atom/target)
	. = list(list("id" = INPUT_ACTION_INSPECT, "name" = "Examine"))
	if(ismovable(target) && target != user && isliving(user))
		. += list(list("id" = INPUT_ACTION_PULL, "name" = "Pull"))
	if(target != user && isliving(user))
		. += list(list("id" = INPUT_ACTION_POINT, "name" = "Point at"))

/datum/interaction_menu/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/atom/target = target()
	if(!user || !target)
		return FALSE
	return TRUE

UI_ACT(/datum/interaction_menu, "run", ui_act_run, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/interaction_menu, ui_act_run)
	var/atom/target = target()
	ui.close()
	run_chosen_interaction(user, target, params["id"])
	return TRUE

UI_ACT(/datum/interaction_menu, "action", ui_act_action, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/interaction_menu, ui_act_action)
	var/atom/target = target()
	var/action_id = params["id"]
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

UI_ACT(/datum/interaction_menu, "verb", ui_act_verb, UI_ARG_TEXT("name"))
UI_ACT_PROC(/datum/interaction_menu, ui_act_verb)
	var/atom/target = target()
	var/verb_name = params["name"]
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

/// LC-refs: the client using the menu -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/interaction_menu/proc/owner() as /client
	return om_resolve(owner_handle)

DECLARE_REF(/client, "interaction_menu", OWNED, null)
