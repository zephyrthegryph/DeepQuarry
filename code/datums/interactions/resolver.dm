/**
 * The resolver (doc/rewrite/interactions.md §7).
 *
 * interactions_for(actor, target, held, modifiers) lists what the actor can do
 * to the target now, best first, and what they can't do, each with the reason
 * from its first failing clause. Use, Alternate, the Menu, category keys,
 * examine and screentips all read this one list.
 */
/datum/interaction_resolution
	var/mob/actor
	var/atom/target
	var/obj/item/held
	/// Available interactions, highest priority first.
	var/list/available = list()
	/// Blocked interactions -> reason, highest priority first.
	var/list/blocked = list()

/datum/interaction_resolution/New(mob/actor, atom/target, obj/item/held)
	src.actor = actor
	src.target = target
	src.held = held

/datum/interaction_resolution/Destroy()
	actor = null
	target = null
	held = null
	return ..()

/// The available interactions that answer `action` at the best priority. Several means a tie.
/datum/interaction_resolution/proc/best_for_action(action)
	return best_of(available, action, null)

/// The available interactions of a category at the best priority.
/datum/interaction_resolution/proc/best_in_category(category)
	return best_of(available, null, category)

/// Picks the top-priority entries matching an action and/or category. Input lists are already sorted.
/datum/interaction_resolution/proc/best_of(list/interactions, action, category)
	. = list()
	var/best_priority
	for(var/datum/interaction/interaction as anything in interactions)
		if(action && interaction.default_action != action)
			continue
		if(category && interaction.category != category)
			continue
		if(isnull(best_priority))
			best_priority = interaction.priority
		else if(interaction.priority < best_priority)
			break
		. += interaction

/// The first blocked interaction answering `action` whose tool the held item has: what the player meant.
/datum/interaction_resolution/proc/intended_blocked(action, quality)
	for(var/datum/interaction/interaction as anything in blocked)
		if(action && interaction.default_action != action)
			continue
		if(quality && interaction.tool != quality)
			continue
		if(!interaction.tool || !held?.has_tool_quality(interaction.tool))
			continue
		return interaction
	return null

/**
 * Everything `actor` could do to `target` holding `held`, sorted by priority.
 * The actor's capability adapter drops what that kind of actor can never do.
 * `modifiers` is the click's modifier list; nothing reads it yet (combat mode, I6).
 * `adapter` overrides the actor's own, e.g. telekinesis acting for a human.
 */
/proc/interactions_for(mob/actor, atom/target, obj/item/held, list/modifiers, datum/input_adapter/adapter)
	var/datum/interaction_resolution/resolution = new(actor, target, held)
	if(!actor || !target)
		return resolution
	adapter ||= actor.input_adapter()
	var/list/available = list()
	var/list/blocked = list()
	for(var/datum/interaction/interaction as anything in interaction_candidates(target))
		if(!interaction.applies_to(target) || !adapter.allows_interaction(actor, target, interaction))
			continue
		var/reason = interaction.why_not(actor, target, held)
		if(reason)
			blocked[interaction] = reason
		else
			available += interaction
	resolution.available = sort_interactions(available)
	var/list/sorted_blocked = list()
	for(var/datum/interaction/interaction as anything in sort_interactions(blocked))
		sorted_blocked[interaction] = blocked[interaction]
	resolution.blocked = sorted_blocked
	return resolution

/// Stable sort by priority, highest first. Lists are short: insertion sort.
/proc/sort_interactions(list/interactions)
	var/list/sorted = list()
	for(var/datum/interaction/interaction as anything in interactions)
		var/position = length(sorted) + 1
		for(var/i in 1 to length(sorted))
			var/datum/interaction/other = sorted[i]
			if(interaction.priority > other.priority)
				position = i
				break
		sorted.Insert(position, interaction)
	return sorted

/**
 * Runs the best interaction for an action. Returns INTERACTION_TRY_RAN,
 * INTERACTION_TRY_MENU when several tie (the Menu opens), INTERACTION_TRY_BLOCKED
 * when the one the player meant is blocked (they are told why), or null when
 * nothing answers: the caller then falls back to the legacy handlers.
 *
 * `quality` limits it to interactions needing that tool quality (the tool_act
 * path); `no_tool` limits it to interactions needing no tool (the generic path).
 * `adapter` overrides the actor's own capability adapter (telekinesis).
 */
/proc/try_interaction(mob/actor, atom/target, obj/item/held, action, quality, no_tool = FALSE, datum/input_adapter/adapter)
	if(!actor || !target)
		return null
	var/datum/interaction_resolution/resolution = interactions_for(actor, target, held, null, adapter)
	var/list/best = list()
	for(var/datum/interaction/interaction as anything in resolution.best_for_action(action))
		if(quality && interaction.tool != quality)
			continue
		if(no_tool && interaction.tool)
			continue
		best += interaction
	if(!length(best) && quality)
		// The best for the action may have used another quality; look again among this quality's.
		var/datum/interaction/first
		for(var/datum/interaction/interaction as anything in resolution.available)
			if(interaction.default_action != action || interaction.tool != quality)
				continue
			if(first && interaction.priority < first.priority)
				break
			first ||= interaction
			best += interaction
	if(length(best) > 1)
		open_interaction_menu(actor, target)
		return INTERACTION_TRY_MENU
	if(length(best) == 1)
		var/datum/interaction/interaction = best[1]
		interaction.perform(actor, target, held)
		return INTERACTION_TRY_RAN
	if(quality)
		var/datum/interaction/meant = resolution.intended_blocked(action, quality)
		if(meant)
			meant.tell_blocked(actor, target, resolution.blocked[meant])
			return INTERACTION_TRY_BLOCKED
	return null

/// The tool_act path: the base *_act procs end here, so subtype overrides that call ..() reach it.
/atom/proc/interaction_tool_act(mob/user, obj/item/tool, quality)
	switch(try_interaction(user, src, tool, INPUT_ACTION_USE, quality))
		if(INTERACTION_TRY_RAN)
			return ITEM_INTERACT_SUCCESS
		if(INTERACTION_TRY_MENU, INTERACTION_TRY_BLOCKED)
			return ITEM_INTERACT_BLOCKING
	return NONE

/**
 * A category key: the best interaction of `category` on `target`. A turf
 * target (the tile in front) also offers what is on it; the best across them wins.
 * Returns TRUE if something ran or the Menu opened.
 */
/proc/try_interaction_category(mob/actor, atom/target, category)
	var/obj/item/held = actor.get_active_hand()
	var/list/targets = list(target)
	if(isturf(target))
		for(var/atom/movable/thing in target)
			if(thing != actor && thing.mouse_opacity && !thing.invisibility)
				targets += thing
	var/list/best = list()
	var/list/best_targets = list()
	var/best_priority
	var/datum/interaction/first_blocked
	var/atom/first_blocked_target
	var/first_blocked_reason
	for(var/atom/candidate as anything in targets)
		var/datum/interaction_resolution/resolution = interactions_for(actor, candidate, held)
		for(var/datum/interaction/interaction as anything in resolution.best_in_category(category))
			if(isnull(best_priority) || interaction.priority > best_priority)
				best_priority = interaction.priority
				best = list()
				best_targets = list()
			else if(interaction.priority < best_priority)
				continue
			best += interaction
			best_targets += candidate
		if(!first_blocked)
			for(var/datum/interaction/interaction as anything in resolution.blocked)
				if(interaction.category == category)
					first_blocked = interaction
					first_blocked_target = candidate
					first_blocked_reason = resolution.blocked[interaction]
					break
	if(length(best) > 1)
		open_interaction_menu(actor, best_targets[1])
		return TRUE
	if(length(best) == 1)
		var/datum/interaction/interaction = best[1]
		interaction.perform(actor, best_targets[1], held)
		return TRUE
	if(first_blocked)
		first_blocked.tell_blocked(actor, first_blocked_target, first_blocked_reason)
		return FALSE
	to_chat(actor, span_notice("There is nothing to [category] on \the [target]."))
	return FALSE

/// Runs one interaction by id, as chosen in the Menu. Returns TRUE if it ran.
/proc/run_chosen_interaction(mob/actor, atom/target, id)
	var/datum/interaction/interaction = INTERACTION_BY_ID(id)
	if(!interaction || !actor || !target)
		return FALSE
	var/obj/item/held = actor.get_active_hand()
	var/datum/interaction_resolution/resolution = interactions_for(actor, target, held)
	if(!(interaction in resolution.available))
		var/reason = resolution.blocked[interaction]
		if(reason)
			interaction.tell_blocked(actor, target, reason)
		return FALSE
	return interaction.perform(actor, target, held)
