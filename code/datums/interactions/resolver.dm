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
	var/list/available = list() // ALLOW(instance_list): interaction area (I3/I4/I6): resolver result lists; listed in memory_lists_audit.md, not edited here
	/// Blocked interactions -> reason, highest priority first.
	var/list/blocked = list() // ALLOW(instance_list): interaction area (I3/I4/I6): resolver result lists; listed in memory_lists_audit.md, not edited here
	/// Interaction -> its priority for this actor (combat mode shifts hostile ones).
	var/list/priorities = list() // ALLOW(instance_list): interaction area (I3/I4/I6): resolver result lists; not edited here

/datum/interaction_resolution/New(mob/actor, atom/target, obj/item/held)
	rel_set(src, "actor", actor)
	rel_set(src, "target", target)
	rel_set(src, "held", held)

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
	var/list/entries_seen
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
		// Converted legacy handlers never tie with each other: the first of an entry answers, as the override chain did.
		if(interaction.entry)
			if(LAZYFIND(entries_seen, interaction.entry))
				continue
			LAZYADD(entries_seen, interaction.entry)
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
	for(var/datum/interaction/interaction as anything in interaction_candidates(target) + cap_extra_interactions(target) + construction_edges_for(target))
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
	// Narrowed before any why_not(): only this action (and quality) is resolved, converted legacy
	// handlers (I7, run from their own entry procs, run_interaction_entry()) are skipped, and
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

// ---------------------------------------------------------------------------
// Legacy entries (I7)

/// Actor -> how many legacy entries are dispatching for them right now. The entry proc decided reach itself.
GLOBAL_LIST_EMPTY(interaction_entry_actors)
/// Actors whose running entry interaction answered INTERACTION_HANDLED_PASS (set by generic run_effect()).
GLOBAL_LIST_EMPTY(interaction_entry_pass)

/// A type's interactions for one entry, in dispatch order: priority, then declaration order. Cached per type.
/proc/interaction_entry_candidates(atom/target, entry)
	return CACHED_KEY(interaction_entry_candidates, "[target.type]|[entry]", target, entry)

DECLARE_SHARED_CACHE(interaction_entry_candidates, GLOBAL_PROC_REF(build_interaction_entry_candidates), SC_NEVER)

/proc/build_interaction_entry_candidates(atom/target, entry)
	var/list/candidates = list()
	for(var/datum/interaction/interaction as anything in interaction_candidates(target))
		if(interaction.entry == entry)
			candidates += interaction
	return sort_interactions(candidates)

/**
 * Runs the interactions a converted legacy handler became, from that handler's
 * old entry proc (attackby, attack_hand, attack_self, click_alt, MouseDrop_T).
 * Every caller of the proc still reaches them, in the override chain's order:
 * types declare their own interactions before calling ..(), so the most
 * specific type's come first, in the order its old handler tested them.
 *
 * The first interaction the actor meant (is_meant(): the right item, and its
 * offered_when clauses) answers. If its requirements fail, the actor is told
 * why and the input stops there, as an old handler returned early with a
 * message. If its effect declines (returns FALSE), the next one is tried, as an
 * old handler fell through to ..().
 *
 * The actor's adapter doesn't filter: the entry's callers already decided who
 * reaches it (the AI through silicon_use, telekinesis at range, grippers).
 * With `gate` (hand entries), target.hand_gate() runs once, before the first
 * interaction that is `behind_gate`, or at the end if none was meant.
 * Returns the interaction that answered, INTERACTION_GATE_STOPPED when the gate
 * stopped it, or null when nothing was meant.
 * `result` (a list) gets the outcome, INTERACTION_TRY_RAN or INTERACTION_TRY_BLOCKED, plus
 * INTERACTION_TRY_PASS when the effect answered INTERACTION_HANDLED_PASS (input not used up).
 */
/proc/run_interaction_entry(mob/actor, atom/target, obj/item/held, entry, list/result, gate)
	if(!actor || !target)
		return null
	var/list/candidates = interaction_entry_candidates(target, entry)
	var/gate_ran = !gate
	if(!length(candidates))
		if(!gate_ran && target.hand_gate(actor))
			result?.Add(INTERACTION_TRY_BLOCKED)
			return INTERACTION_GATE_STOPPED
		return null
	GLOB.interaction_entry_actors[actor] = (GLOB.interaction_entry_actors[actor] || 0) + 1
	// A nested entry (an effect that touches something else) keeps the outer one's pass flag.
	var/saved_pass = GLOB.interaction_entry_pass[actor]
	GLOB.interaction_entry_pass -= actor
	. = null
	try
		for(var/datum/interaction/interaction as anything in candidates)
			if(!interaction.applies_to(target) || !interaction.is_meant(actor, target, held))
				continue
			// The gate sits below the first handler that went on to ..(), as in the override chain.
			if(!gate_ran && interaction.behind_gate)
				gate_ran = TRUE
				if(target.hand_gate(actor))
					result?.Add(INTERACTION_TRY_BLOCKED)
					. = INTERACTION_GATE_STOPPED
					break
			var/outcome = interaction.attempt(actor, target, held)
			if(outcome)
				result?.Add(outcome)
				if(GLOB.interaction_entry_pass[actor])
					result?.Add(INTERACTION_TRY_PASS)
				. = interaction
				break
			if(QDELETED(target))
				break
	catch(var/exception/error)
		interaction_entry_restore_pass(actor, saved_pass)
		interaction_entry_done(actor)
		throw error
	interaction_entry_restore_pass(actor, saved_pass)
	interaction_entry_done(actor)
	// Nothing meant: the touch still reaches the gate, as the base proc did.
	if(!. && !gate_ran && !QDELETED(target) && target.hand_gate(actor))
		result?.Add(INTERACTION_TRY_BLOCKED)
		return INTERACTION_GATE_STOPPED

/// Click parameters of the item/drag entry each actor is inside (attackby's click_parameters,
/// MouseDrop_T's params), so an effect can place precisely: dq_interaction_click_params().
GLOBAL_LIST_EMPTY(interaction_entry_click_params)

/// Sets `actor`'s entry click parameters (null clears them); returns the previous value to restore.
/proc/dq_interaction_set_click_params(mob/actor, params)
	if(!actor)
		return null
	. = GLOB.interaction_entry_click_params[actor]
	if(params)
		GLOB.interaction_entry_click_params[actor] = params
	else
		GLOB.interaction_entry_click_params -= actor

/// The click parameters of the entry `actor` is running an interaction from, or null.
/proc/dq_interaction_click_params(mob/actor)
	return actor ? GLOB.interaction_entry_click_params[actor] : null

/proc/interaction_entry_restore_pass(mob/actor, saved_pass)
	if(saved_pass)
		GLOB.interaction_entry_pass[actor] = saved_pass
	else
		GLOB.interaction_entry_pass -= actor

/proc/interaction_entry_done(mob/actor)
	var/count = GLOB.interaction_entry_actors[actor] - 1
	if(count > 0)
		GLOB.interaction_entry_actors[actor] = count
	else
		GLOB.interaction_entry_actors -= actor

/**
 * Requirement clause REQ_INTERACTION_REACH: adjacent; or a silicon the target
 * lets use it remotely (silicon_use); or inside a legacy entry, whose callers
 * decided reach themselves (telekinesis, the AI's attack_ai, grippers).
 */
/proc/dq_interaction_reach(mob/actor, atom/target, obj/item/held)
	if(!actor || !target)
		return FALSE
	if(GLOB.interaction_entry_actors[actor])
		return TRUE
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

/// Requirement clause REQ_SELF_USE_REACH: the item is in one of the actor's hands, or attack_self()
/// already dispatched it (its callers decided that themselves: action buttons, anchored items).
/proc/dq_interaction_self_reach(mob/actor, atom/target, obj/item/held)
	if(!actor || !target)
		return FALSE
	if(GLOB.interaction_entry_actors[actor])
		return TRUE
	return actor.get_active_hand() == target || actor.get_inactive_hand() == target

/// Requirement clause REQ_IN_INVENTORY: the target is somewhere on the actor.
/proc/dq_interaction_in_inventory(mob/actor, atom/target, obj/item/held)
	if(!actor || !target)
		return FALSE
	return get(target, /mob) == actor
