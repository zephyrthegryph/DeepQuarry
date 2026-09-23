/**
 * The Menu action (doc/rewrite/interactions.md §7): a tgui context panel
 * listing what the player can do to a target, what they can't and why, and the
 * keys that reach each. It replaces BYOND's native right-click verb popup, so
 * it also lists the target's legacy verbs and the basic mob actions the popup
 * used to offer (examine, pull, point).
 */
/datum/interaction_menu
	var/client/owner
	var/datum/weakref/target_ref

/datum/interaction_menu/New(client/owner)
	src.owner = owner

/datum/interaction_menu/Destroy()
	if(owner?.interaction_menu == src)
		owner.interaction_menu = null
	owner = null
	target_ref = null
	return ..()

/client/var/tmp/datum/interaction_menu/interaction_menu

/// Opens the Menu for `target`. Returns TRUE if it opened.
/proc/open_interaction_menu(mob/user, atom/target)
	if(!user?.client || !target)
		return FALSE
	var/client/player = user.client
	if(!player.interaction_menu)
		player.interaction_menu = new(player)
	player.interaction_menu.target_ref = WEAKREF(target)
	log_input("Input: [key_name(user)] opened the interaction menu on [target] ([target.type]).")
	player.interaction_menu.tgui_interact(user)
	return TRUE

/datum/interaction_menu/proc/target()
	var/atom/target = target_ref?.resolve()
	return QDELETED(target) ? null : target

/datum/interaction_menu/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/interaction_menu/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "InteractionMenu")
		ui.open()

/datum/interaction_menu/tgui_data(mob/user)
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

/datum/interaction_menu/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = ui.user
	var/atom/target = target()
	if(!user || !target)
		return
	switch(action)
		if("run")
			ui.close()
			run_chosen_interaction(user, target, params["id"])
			return TRUE
		if("action")
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
		if("verb")
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
