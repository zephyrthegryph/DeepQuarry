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
	var/list/available = list() // ALLOW(instance_list): the resolver's result list: built and edited in place on every resolution, always in use
	/// Blocked interactions -> reason, highest priority first.
	var/list/blocked = list() // ALLOW(instance_list): the resolver's result list: built and edited in place on every resolution, always in use
	/// Interaction -> its priority for this actor (combat mode shifts hostile ones).
	var/list/priorities = list() // ALLOW(instance_list): the resolver's priority table: built and edited in place on every resolution, always in use

/datum/interaction_resolution/New(mob/actor, atom/target, obj/item/held)
	rel_set(src, nameof(actor), actor)
	rel_set(src, nameof(target), target)
	rel_set(src, nameof(held), held)

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
		var/priority = priority_of(interaction)
		if(isnull(best_priority))
			best_priority = priority
		else if(priority < best_priority)
			break
		. += interaction

/// The interaction's priority for this actor.
/datum/interaction_resolution/proc/priority_of(datum/interaction/interaction)
	var/priority = priorities[interaction]
	return isnull(priority) ? interaction.priority : priority

/// The available interactions that run from a legacy entry proc (I7).
/datum/interaction_resolution/proc/entry_interactions()
	. = list()
	for(var/datum/interaction/interaction as anything in available)
		if(interaction.entry)
			. += interaction

/// The first blocked interaction answering `action` whose tool the held item has: what the player meant.
/datum/interaction_resolution/proc/intended_blocked(action, quality)
	for(var/datum/interaction/interaction as anything in blocked)
		if(interaction.entry)
			continue
		if(action && interaction.default_action != action)
			continue
		if(quality && interaction.tool != quality)
			continue
		if(!interaction.tool || !held()?.has_tool_quality(interaction.tool))
			continue
		// One declared for another stance (a pry offered outside combat mode) is not what was meant:
		// the tool falls through to the target's next use, as a legacy entry skipped it.
		if(!interaction.is_meant(actor(), target(), held()))
			continue
		return interaction
	return null

/**
 * Everything `actor()` could do to `target()` holding `held()`, sorted by priority.
 * The actor()'s capability adapter drops what that kind of actor can never do.
 * Combat mode (I6) orders the list: with it on, hostile interactions come
 * before the rest; with it off, after. `modifiers` is the click's modifier
 * list; the router has already turned modifiers into the action, so the
 * resolver itself needs none of them.
 * `adapter` overrides the actor()'s own, e.g. telekinesis acting for a human.
 *
 * Narrowing (a click that already knows what it wants): `action` / `quality` keep only
 * interactions answering that action / needing that tool quality, `skip_entries` drops
 * converted legacy handlers, all before any why_not() runs. `collect_blocked` FALSE
 * skips building the blocked list (and its sort) entirely.
 */
/proc/interactions_for(mob/actor, atom/target, obj/item/held, list/modifiers, datum/input_adapter/adapter, action = null, quality = null, skip_entries = FALSE, collect_blocked = TRUE)
	var/datum/interaction_resolution/resolution = new(actor, target, held)
	if(!actor || !target)
		return resolution
	adapter ||= actor.input_adapter()
	var/list/available = list()
	var/list/blocked = list()
	var/list/priorities = resolution.priorities
	// The type's interactions, then the construction edges leaving its current state (construction.dm).
	for(var/datum/interaction/interaction as anything in interaction_candidates(target) + cap_extra_interactions(target))
		if(action && interaction.default_action != action)
			continue
		if(quality && interaction.tool != quality)
			continue
		if(skip_entries && interaction.entry)
			continue
		if(!interaction.applies_to(target) || !adapter.allows_interaction(actor, target, interaction))
			continue
		priorities[interaction] = interaction_priority_for(actor, interaction)
		var/reason = interaction.why_not(actor, target, held)
		if(reason)
			if(collect_blocked)
				blocked[interaction] = reason
		else
			available += interaction
	resolution.available = sort_interactions(available, priorities)
	if(!length(blocked))
		return resolution
	var/list/sorted_blocked = list()
	for(var/datum/interaction/interaction as anything in sort_interactions(blocked, priorities))
		sorted_blocked[interaction] = blocked[interaction]
	resolution.blocked = sorted_blocked
	return resolution

/**
 * An interaction's priority for an actor. Combat mode (I6) moves hostile
 * interactions above everything else when on, and below when off, so Use
 * picks an attack only in combat mode.
 */
/proc/interaction_priority_for(mob/actor, datum/interaction/interaction)
	. = interaction.priority
	if(!(INTERACTION_TAG_HOSTILE in interaction.tags))
		return
	return . + (actor?.combat_mode ? COMBAT_MODE_PRIORITY_SHIFT : -COMBAT_MODE_PRIORITY_SHIFT)

/// Stable sort by priority (from `priorities` when given), highest first. Lists are short: insertion sort.
/proc/sort_interactions(list/interactions, list/priorities)
	var/list/sorted = list()
	for(var/datum/interaction/interaction as anything in interactions)
		var/priority = (priorities && !isnull(priorities[interaction])) ? priorities[interaction] : interaction.priority
		var/position = length(sorted) + 1
		for(var/i in 1 to length(sorted))
			var/datum/interaction/other = sorted[i]
			var/other_priority = (priorities && !isnull(priorities[other])) ? priorities[other] : other.priority
			if(priority > other_priority)
				position = i
				break
		sorted.Insert(position, interaction)
	return sorted

/**
 * Runs the best interaction for an action: the router's op first (try_gesture()), then the resolver's own
 * entries. Returns INTERACTION_TRY_RAN,
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
	// The router first: gesture -> actions -> op (operations/actions.dm). Only what no op answers is resolved
	// below, from the interaction entries that were never migrated to ops.
	var/routed = try_gesture(actor, target, held, action, quality, no_tool, adapter)
	if(!isnull(routed))
		return routed
	// What the action table does not reach: the op engine's own resolution, for a call that did not come from a player's click (a tool's own act, an item
	// used by code). A click the inbox resolved already (GLOB.op_click_resolved) must not run its ops a second time.
	var/datum/op_result/engine = try_engine(actor, target, held, action, quality, no_tool)
	if(engine)
		return engine
	// Narrowed before any why_not(): only this action (and quality) is resolved, converted legacy
	// handlers (I7, which have an entry) are skipped, and
	// the blocked list is only built below when nothing is available.
	// With `quality`, the best of that quality's interactions for the action is what the old
	// full pass found (best for the action filtered to the quality, else the quality's best).
	var/datum/interaction_resolution/resolution = interactions_for(actor, target, held, null, adapter, action, quality, TRUE, FALSE)
	var/list/best = list()
	for(var/datum/interaction/interaction as anything in resolution.best_of(resolution.available, action, null))
		if(no_tool && interaction.tool)
			continue
		best += interaction
	if(length(best) > 1)
		open_interaction_menu(actor, target)
		return INTERACTION_TRY_MENU
	if(length(best) == 1)
		var/datum/interaction/interaction = best[1]
		// An effect that declined (returned FALSE) leaves the input to the actor's default.
		return interaction.attempt(actor, target, held)
	if(quality && !length(resolution.available))
		// Nothing of this quality is available: now build the blocked list to say why.
		resolution = interactions_for(actor, target, held, null, adapter, action, quality, TRUE, TRUE)
		var/datum/interaction/meant = resolution.intended_blocked(action, quality)
		if(meant)
			meant.tell_blocked(actor, target, resolution.blocked[meant])
			return INTERACTION_TRY_BLOCKED
	return null

/// A call's click through the op engine (op_resolve_click()): INTERACTION_TRY_RAN when an op ran or started, INTERACTION_TRY_BLOCKED when the winner refused,
/// null when no op took it (or the inbox resolved this click already).
/proc/try_engine(mob/actor, atom/target, obj/item/held, action, quality, no_tool)
	if(GLOB.op_click_resolved[actor])
		return null
	var/gesture = gesture_of_action(action, quality)
	if(isnull(gesture) || !(op_has_ops(target) || op_has_ops(held) || op_has_click_ops(actor)))
		return null
	var/datum/op_result/result = op_resolve_click(actor, target, held, gesture, ORIGIN_CLICK, FALSE, TRUE, quality, no_tool)
	if(!result)
		return null
	return result.outcome == ACT_REFUSED ? INTERACTION_TRY_BLOCKED : INTERACTION_TRY_RAN

/// The tool_act path: the base *_act procs end here, so subtype overrides that call ..() reach it.
/// `secondary` (right-click tool use) runs the quality's Alternate interactions instead of Use.
/atom/proc/interaction_tool_act(mob/user, obj/item/tool, quality, secondary = FALSE)
	switch(try_interaction(user, src, tool, secondary ? INPUT_ACTION_ALTERNATE : INPUT_ACTION_USE, quality))
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
			var/priority = resolution.priority_of(interaction)
			if(isnull(best_priority) || priority > best_priority)
				best_priority = priority
				best = list()
				best_targets = list()
			else if(priority < best_priority)
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
	if(!actor || !target)
		return FALSE
	var/obj/item/held = actor.get_active_hand()
	var/datum/interaction_resolution/resolution = interactions_for(actor, target, held)
	// Ids are unique within one target, not globally (capability entries of different types share
	// ids): resolve the choice among this target's own interactions first.
	var/datum/interaction/interaction
	for(var/datum/interaction/candidate as anything in resolution.available + resolution.blocked)
		if(candidate.id == id)
			interaction = candidate
			break
	interaction ||= INTERACTION_BY_ID(id)
	if(!interaction)
		return FALSE
	if(!(interaction in resolution.available))
		var/reason = resolution.blocked[interaction]
		if(reason)
			interaction.tell_blocked(actor, target, reason)
		return FALSE
	return interaction.perform(actor, target, held)

/**
 * Requirement clause REQ_INTERACTION_REACH: adjacent; or a silicon the target lets use it remotely (silicon_use).
 */
/proc/dq_interaction_reach(mob/actor, atom/target, obj/item/held)
	if(!actor || !target)
		return FALSE
	if(actor.Adjacent(target))
		return TRUE
	if(issilicon(actor) && (target.silicon_use & (SILICON_USE_HAND | ROBOT_USE_HAND)))
		return TRUE
	return FALSE

/// The mob acting (a relation view).
/datum/interaction_resolution/proc/actor() as /mob
	return actor

/// The atom acted on (a relation view).
/datum/interaction_resolution/proc/target() as /atom
	return target

/// The item in hand (a relation view).
/datum/interaction_resolution/proc/held() as /obj/item
	return held

/// Requirement clause REQ_SELF_USE_REACH: the item is in one of the actor's hands.
/proc/dq_interaction_self_reach(mob/actor, atom/target, obj/item/held)
	if(!actor || !target)
		return FALSE
	return actor.get_active_hand() == target || actor.get_inactive_hand() == target

/// Requirement clause REQ_IN_INVENTORY: the target is somewhere on the actor.
/proc/dq_interaction_in_inventory(mob/actor, atom/target, obj/item/held)
	if(!actor || !target)
		return FALSE
	return get(target, /mob) == actor
