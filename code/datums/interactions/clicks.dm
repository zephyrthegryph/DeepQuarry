/**
 * Clicks into the op engine (doc/rewrite/interactions.md §7). The input adapters' Use and Alternate, the
 * tool_act path and the category keys come here: the op engine (code/engine/parts/resolve.dm) resolves the
 * click among the target's, the held item's and the actor's ops. What no op answers falls back to the
 * caller's legacy handlers.
 */

/**
 * Runs the op a click reaches. Returns INTERACTION_TRY_RAN when an op ran or started, INTERACTION_TRY_BLOCKED
 * when the op the click reached refused (the actor was told why), or null when no op answers: the caller then
 * falls back to the legacy handlers. `quality` limits it to ops of that tool quality (the tool_act path);
 * `no_tool` to ops needing no tool (the generic path).
 */
/proc/try_interaction(mob/actor, atom/target, obj/item/held, action, quality, no_tool = FALSE)
	if(!actor || !target)
		return null
	return try_engine(actor, target, held, action, quality, no_tool)

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

/// The gesture an input action (INPUT_ACTION_USE / INPUT_ACTION_ALTERNATE, with or without a tool quality:
/// the secondary click of a tool) stands for; null for actions that are not gestures.
/proc/gesture_of_action(action, quality)
	switch(action)
		if(INPUT_ACTION_USE)
			return GESTURE_CLICK
		if(INPUT_ACTION_ALTERNATE)
			return quality ? GESTURE_RIGHT : GESTURE_ALT
	return null

/// The tool_act path: the base *_act procs end here, so subtype overrides that call ..() reach it.
/// `secondary` (right-click tool use) resolves the quality's secondary click instead of its plain one.
/atom/proc/interaction_tool_act(mob/user, obj/item/tool, quality, secondary = FALSE)
	switch(try_interaction(user, src, tool, secondary ? INPUT_ACTION_ALTERNATE : INPUT_ACTION_USE, quality))
		if(INTERACTION_TRY_RAN)
			return ITEM_INTERACT_SUCCESS
		if(INTERACTION_TRY_BLOCKED)
			return ITEM_INTERACT_BLOCKING
	return NONE

/**
 * A category key on `target`. Ops carry no interaction category, so no op answers one: the key tells the
 * player there is nothing of that category there. Returns FALSE.
 */
/proc/try_interaction_category(mob/actor, atom/target, category)
	to_chat(actor, span_notice("There is nothing to [category] on \the [target]."))
	return FALSE

/**
 * Reach for a physical route: adjacent; or a silicon the target lets use it remotely (silicon_use).
 */
/proc/dq_interaction_reach(mob/actor, atom/target, obj/item/held)
	if(!actor || !target)
		return FALSE
	if(actor.Adjacent(target))
		return TRUE
	if(issilicon(actor) && (target.silicon_use & (SILICON_USE_HAND | ROBOT_USE_HAND)))
		return TRUE
	return FALSE

/// Requirement clause: the actor is alive, conscious and not incapacitated (the old verbs' usr checks).
/proc/dq_actor_can_act(mob/actor, atom/target, obj/item/held)
	READS_FROM(actor)
	if(!isliving(actor))
		return FALSE
	return !actor.incapacitated()

/// Called on the target after a player (or program) changed it through its window. Types whose scheduled work depends on
/// their settings wake here (a machine's step, a refinery line).
/atom/proc/interaction_ran(mob/actor)
	return

/// Where afterattack() used to be called from a click.
/proc/after_click(obj/item/holder, atom/target, mob/user, proximity_flag, click_parameters, stance = I_HURT)
	holder.afterattack(target, user, proximity_flag, click_parameters, stance)
