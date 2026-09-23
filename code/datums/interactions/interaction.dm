/**
 * Interaction definitions (doc/rewrite/interactions.md §5).
 *
 * An interaction is a definition, not a proc override: one shared singleton per
 * type, listed or inherited by the atom types that offer it. Nothing is stored
 * per instance. Because it is data, every interaction can be listed in the
 * Menu, explain why it is unavailable, show up in examine and screentips, and
 * be reached by a category key.
 *
 *	/datum/interaction/machine_panel
 *		id = "machine_panel"
 *		name = "Open maintenance panel"
 *		category = INTERACTION_CAT_MAINTAIN
 *		priority = 10
 *		default_action = INPUT_ACTION_USE
 *		tool = TOOL_SCREWDRIVER
 *		requires = list(REQ_REACH_ADJACENT)
 *		effect = /obj/machinery/proc/toggle_maintenance_panel
 *
 * Offering one: atom types add interaction paths in declare_interactions().
 * applies_to() then filters per target (a behaviour flag, for example); an
 * interaction that doesn't apply is never shown. One that applies but whose
 * `requires` fails is shown as blocked, with the reason.
 */
/datum/interaction
	/// Stable id: snapshots, logs and the Menu use it.
	var/id
	/// Shown in the Menu, examine and screentips. display_name() may vary it by state.
	var/name
	/// INTERACTION_CAT_*: which category key reaches it.
	var/category
	/// Higher wins when several interactions answer the same action.
	var/priority = 0
	/// INPUT_ACTION_USE or INPUT_ACTION_ALTERNATE when it answers that action, else null (Menu and category keys only).
	var/default_action
	/// The predicate spec (REQ_* clauses, code/__defines/predicates.dm). `tool` adds its clause in front.
	var/list/requires
	/// Cost, tool part: the TOOL_* quality the held item needs. The tool pipeline (I4) takes this over.
	var/tool
	/// Cost, time part: how long it takes, scaled by the tool's speed. See duration_for().
	var/duration = 0
	/// Proc on the target, called as effect(actor, held, interaction). Returns TRUE when it did something.
	var/effect
	/// Feedback. Tokens: %ACTOR%, %TARGET%. Null means no message. messages() may vary them by state.
	var/message_self
	var/message_others
	/// INTERACTION_TAG_* for filtering.
	var/list/tags
	/// The compiled requirement predicate, made on first use.
	var/tmp/datum/predicate/compiled

/// The full predicate spec: the tool clause first, then `requires`.
/datum/interaction/proc/full_spec()
	var/list/spec = list()
	if(tool)
		spec += list(REQ_TOOL(tool))
	if(length(requires))
		spec += requires
	return spec

/// The shared compiled predicate, or null when the interaction has no requirements.
/datum/interaction/proc/predicate()
	if(compiled)
		return compiled
	var/list/spec = full_spec()
	if(!length(spec))
		return null
	compiled = dq_predicate_for("interaction:[type]", spec, "interaction [id]")
	return compiled

/// Whether this interaction is offered on this target at all. Cheap: no reasons, no actor.
/datum/interaction/proc/applies_to(atom/target)
	return TRUE

/// null when the actor can do it now, else why not.
/datum/interaction/proc/why_not(mob/actor, atom/target, obj/item/held)
	var/datum/predicate/pred = predicate()
	return pred ? pred.why_not(actor, target, held) : null

/// The name for this target's current state ("Open panel" or "Close panel").
/datum/interaction/proc/display_name(mob/actor, atom/target)
	return name

/// How long the interaction takes: `duration` scaled by the held tool's speed.
/datum/interaction/proc/duration_for(mob/actor, atom/target, obj/item/held)
	return duration * ((tool && held) ? held.toolspeed : 1)

/// Messages as list(self, others), worked out before the effect changes the target's state.
/datum/interaction/proc/messages(mob/actor, atom/target, obj/item/held)
	return list(message_self, message_others)

/// Messages shown when a timed interaction starts, as list(self, others), or null.
/datum/interaction/proc/start_messages(mob/actor, atom/target, obj/item/held)
	return null

/// Replaces %ACTOR% and %TARGET% in a message template.
/datum/interaction/proc/fill_message(template, mob/actor, atom/target)
	if(!template)
		return null
	var/text = replacetext(template, "%ACTOR%", "\The [actor]")
	return replacetext(text, "%TARGET%", "\the [target]")

/**
 * Pays the cost. This is the stub of the tool pipeline (§9, I4): the tool's
 * sound and a do_after scaled by the tool's speed. Returns FALSE if interrupted.
 */
/datum/interaction/proc/pay_cost(mob/actor, atom/target, obj/item/held)
	if(tool && held?.usesound)
		playsound(target, held.usesound, 50, TRUE)
	var/time = duration_for(actor, target, held)
	if(time <= 0)
		return TRUE
	var/list/start = start_messages(actor, target, held)
	if(start)
		var/others_text = fill_message(start[2], actor, target)
		var/self_text = fill_message(start[1], actor, target)
		actor.visible_message(others_text ? span_notice(others_text) : null, self_text ? span_notice(self_text) : null)
	return do_after(actor, time, target = target)

/**
 * Runs the interaction: checks the requirements, pays the cost, checks again
 * (the wait may have changed things), runs the effect and sends the feedback.
 * Returns TRUE if the effect ran.
 */
/datum/interaction/proc/perform(mob/actor, atom/target, obj/item/held)
	var/reason = why_not(actor, target, held)
	if(reason)
		tell_blocked(actor, target, reason)
		return FALSE
	if(!pay_cost(actor, target, held) || QDELETED(target))
		return FALSE
	reason = why_not(actor, target, held)
	if(reason)
		tell_blocked(actor, target, reason)
		return FALSE
	var/list/feedback = messages(actor, target, held)
	var/shown_name = display_name(actor, target)
	if(!call(target, effect)(actor, held, src))
		return FALSE
	log_input("Interaction: [key_name(actor)] did [id] ([shown_name]) on [target] ([target.type]).")
	var/self_text = fill_message(feedback[1], actor, target)
	var/others_text = fill_message(feedback[2], actor, target)
	if(others_text)
		actor.visible_message(span_notice(others_text), span_notice(self_text))
	else if(self_text)
		to_chat(actor, span_notice(self_text))
	return TRUE

/// Tells the actor why they can't do this right now.
/datum/interaction/proc/tell_blocked(mob/actor, atom/target, reason)
	to_chat(actor, span_warning("[display_name(actor, target)]: [reason]."))

// ---------------------------------------------------------------------------
// Registry

/// Interaction type -> shared singleton. Abstract types (no id) are skipped.
GLOBAL_LIST_INIT(interactions_by_type, init_interactions_by_type())
/proc/init_interactions_by_type()
	var/list/by_type = list()
	for(var/datum/interaction/path as anything in subtypesof(/datum/interaction))
		if(!initial(path.id))
			continue
		by_type[path] = new path
	return by_type

/// The shared singleton with this id, or null. Built on first use from GLOB.interactions_by_type.
/proc/interaction_by_id(id)
	var/static/list/by_id
	if(!by_id)
		by_id = list()
		for(var/path in GLOB.interactions_by_type)
			var/datum/interaction/interaction = GLOB.interactions_by_type[path]
			if(by_id[interaction.id])
				stack_trace("Duplicate interaction id [interaction.id] ([path])")
				continue
			by_id[interaction.id] = interaction
	return by_id[id]

/**
 * Adds the interaction types this atom offers to `into`. Types add theirs and
 * call ..() to inherit. Called once per type (the result is cached), so it
 * must not depend on instance state: use applies_to() for that.
 */
/atom/proc/declare_interactions(list/into)
	return

/// The interactions this atom's type offers, as shared singletons. Cached per type.
/proc/interaction_candidates(atom/target)
	var/static/list/cache = list()
	var/list/candidates = cache[target.type]
	if(candidates)
		return candidates
	var/list/paths = list()
	target.declare_interactions(paths)
	candidates = list()
	for(var/path in paths)
		var/datum/interaction/interaction = GLOB.interactions_by_type[path]
		if(!interaction)
			stack_trace("[target.type] declares [path], which is not a registered interaction")
			continue
		candidates |= interaction
	cache[target.type] = candidates
	return candidates
