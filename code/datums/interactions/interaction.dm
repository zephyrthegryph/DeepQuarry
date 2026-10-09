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
 * Offering one: a capability builds its entries (cap_interactions()).
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
	/// attempt()'s result while its cost is paid (INTERACTION_TRY_PENDING until cost_paid() reports).
	var/tmp/attempt_result
	var/default_action
	/// The predicate spec (REQ_* clauses, code/__defines/predicates.dm). `tool` adds its clause in front.
	var/list/requires
	/// Extra clauses on top of the inherited `requires` (a subtype's lifted guards, systems.md section 6): set this
	/// instead of restating the parent's `requires`. Checked after `requires`, so reach fails first.
	var/list/also_requires
	/// Cost, tool part: the TOOL_* quality the held item needs (use_tool(), tools.dm).
	var/tool
	/// The tier of `tool` needed (dq_tool_tier()).
	var/tool_tier = 1
	/// Fuel, charge or stack units the tool uses (tool_start_check() / tool_use_resources()).
	var/tool_amount = 0
	/// Volume of the tool's usesound; 0 for silence.
	var/tool_volume = 50
	/// Cost, time part: how long it takes, scaled by the tool's speed. See duration_for().
	var/duration = 0
	/// Proc on the target, called as effect(actor, held, interaction). Returns TRUE when it did something.
	var/effect
	/// Feedback: a /datum/msg template (doc/rewrite/systems.md section 15), shown when the effect ran.
	/// Tokens %U% (actor), %T% (target), %I% (held item). Null means no message. feedback_for() may vary it by state.
	var/feedback
	/// A /datum/msg template shown when a timed interaction starts, or null. start_feedback_for() may vary it.
	var/start_feedback
	/// INTERACTION_TAG_* for filtering.
	var/list/tags
	/// INTERACTION_ENTRY_*: the legacy input proc that dispatches it (I7), or null for resolver-native ones.
	var/entry
	/// A type, or a list of types, the held item must be (subtypes count). Like `tool`, it says what the player meant.
	var/held_type
	/// Clauses that pick this interaction: when one fails the player didn't mean it, so an entry
	/// falls through to the next candidate (as a legacy `if` fell through to `..()`). Listed in the Menu as blocked.
	var/list/offered_when
	/// I_HELP, I_DISARM, I_GRAB or I_HURT: the stance this interaction answers, or null for any.
	/// The resolver offers it only when the actor's input has that stance (a selector clause),
	/// so the interaction that runs carries the intent: its effect reads `interaction.stance`.
	/// Hostile stances (harm, disarm) also tag it INTERACTION_TAG_HOSTILE (combat mode ranking).
	var/stance
	/// For entries: whether the input is used up when it runs. FALSE mirrors a legacy handler that returned
	/// nothing, after which the item's afterattack (or the alt-click loot panel) still ran.
	var/consumes_input = TRUE
	/// For hand entries: whether the type's hand_gate() (signal, unbuckling, the machinery checks) runs first.
	/// FALSE mirrors a legacy attack_hand that never called ..().
	var/behind_gate = TRUE
	/// The compiled requirement predicate, made on first use.
	var/tmp/datum/predicate/compiled
	/// The compiled selector (tool, held_type, offered_when), made on first use.
	var/tmp/datum/predicate/compiled_selector

/datum/interaction/New()
	..()
	apply_stance_tags()

/// A hostile stance makes the interaction hostile: the resolver ranks it by combat mode.
/datum/interaction/proc/apply_stance_tags()
	if(STANCE_IS_HOSTILE(stance) && !(INTERACTION_TAG_HOSTILE in tags))
		tags = (tags || list()) + INTERACTION_TAG_HOSTILE

/// The clauses that say whether the player meant this interaction: stance, tool, held type, offered_when.
/datum/interaction/proc/selector_spec()
	var/list/spec = list()
	if(stance)
		spec += list(dq_stance_clause(stance))
	if(tool)
		spec += list(REQ_TOOL_TIER(tool, tool_tier))
	if(held_type)
		var/list/types = islist(held_type) ? held_type : list(held_type)
		var/list/names = list()
		for(var/atom/path as anything in types)
			names |= dq_pred_article(initial(path.name))
		spec += list(REQ_BECAUSE(REQ_TYPE(PRED_HELD, types), "needs [english_list(names, and_text = " or ")]"))
	if(length(offered_when))
		spec += offered_when
	return spec

/// What the compiled predicates are shared by: one per type, since a type's
/// requirements are static. Types whose instances differ override it.
/datum/interaction/proc/predicate_key()
	return "[type]"

/// The full predicate spec: the selector clauses first, then `requires`.
/datum/interaction/proc/full_spec()
	var/list/spec = selector_spec()
	if(length(requires))
		spec += requires
	if(length(also_requires))
		spec += also_requires
	return spec

/// The shared compiled selector, or null when anything selects it.
/datum/interaction/proc/selector()
	if(compiled_selector)
		return compiled_selector
	var/list/spec = selector_spec()
	if(!length(spec))
		return null
	rel_set(src, nameof(compiled_selector), dq_predicate_for("interaction_selector:[predicate_key()]", spec, "interaction [id] selector")) // a shared cached predicate
	return compiled_selector

/// Whether the player meant this interaction: the right tool or item, and its offered_when clauses hold.
/datum/interaction/proc/is_meant(mob/actor, atom/target, obj/item/held)
	var/datum/predicate/pred = selector()
	return pred ? pred.check(actor, target, held) : TRUE

/// The shared compiled predicate, or null when the interaction has no requirements.
/datum/interaction/proc/predicate()
	if(compiled)
		return compiled
	var/list/spec = full_spec()
	if(!length(spec))
		return null
	rel_set(src, nameof(compiled), dq_predicate_for("interaction:[predicate_key()]", spec, "interaction [id]")) // a shared cached predicate
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

/// How long the interaction takes: `duration` scaled by the held tool's speed and the actor's skill.
/datum/interaction/proc/duration_for(mob/actor, atom/target, obj/item/held)
	return tool ? tool_delay(actor, held, duration, tool) : duration

/// The unscaled time for this target, before the tool's speed and skill: `duration` unless it depends on the target.
/datum/interaction/proc/base_duration(mob/actor, atom/target)
	return duration

/// The feedback template (a /datum/msg type), picked before the effect changes the target's state.
/datum/interaction/proc/feedback_for(mob/actor, atom/target, obj/item/held)
	return feedback

/// The template shown when a timed interaction starts, or null.
/datum/interaction/proc/start_feedback_for(mob/actor, atom/target, obj/item/held)
	return start_feedback

/// Inline start lines, list(self, others), for a timed interaction with no start_feedback template; or null.
/datum/interaction/proc/start_lines(mob/actor, atom/target, obj/item/held)
	return null

/**
 * Pays the cost through the tool pipeline (use_tool(), tools.dm): quality and
 * tier, fuel or charge, the sound, the scaled wait and the resources. Returns
 * FALSE if a check failed, TRUE if paid at once, or USE_TOOL_PENDING when the wait
 * is a timed action: the rest of the interaction then runs in cost_paid(), which an
 * override that waits must name as its on_done.
 */
/datum/interaction/proc/pay_cost(mob/actor, atom/target, obj/item/held)
	return use_tool(actor, tool ? held : null, target, src, receiver = src, job_type = /datum/task/timed/tool_job/interaction, job_params = list("held" = held))

/// An interaction's time cost paid outside the tool pipeline (a pay_cost() override that
/// waits): cost_paid() runs after it. The actor waits on itself; `acted_on` is the target.
/datum/task/timed/interaction_cost
	complete_proc = /datum/interaction/proc/cost_task_done
	var/atom/acted_on
	var/obj/item/held

/datum/interaction/proc/cost_task_done(datum/task/timed/interaction_cost/task)
	cost_paid(task.actor, task.acted_on, task.held)

/// The cost is paid: the rest of attempt() (re-check, effect, feedback).
/datum/interaction/proc/cost_paid(mob/actor, atom/target, obj/item/held)
	var/result = finish_attempt(actor, target, held)
	if(attempt_result == INTERACTION_TRY_PENDING)
		attempt_result = result

/**
 * Runs the interaction: checks the requirements, pays the cost, checks again
 * (the wait may have changed things), runs the effect and sends the feedback.
 * Returns TRUE if the effect ran.
 */
/datum/interaction/proc/perform(mob/actor, atom/target, obj/item/held)
	return attempt(actor, target, held) == INTERACTION_TRY_RAN

/**
 * perform() with the outcome spelled out: INTERACTION_TRY_RAN when the effect
 * ran (or the wait was interrupted, which still used the input),
 * INTERACTION_TRY_BLOCKED when a requirement failed (the actor is told why), or
 * null when the effect declined (it returned FALSE), so an entry moves on to
 * the next candidate as a legacy handler fell through to `..()`.
 */
/datum/interaction/proc/attempt(mob/actor, atom/target, obj/item/held)
	var/reason = why_not(actor, target, held)
	if(reason)
		tell_blocked(actor, target, reason)
		return INTERACTION_TRY_BLOCKED
	// cost_paid() reports here when the cost is paid at once; a timed cost reports later.
	var/saved = attempt_result
	attempt_result = INTERACTION_TRY_PENDING
	var/paid = pay_cost(actor, target, held)
	var/result = attempt_result
	attempt_result = saved
	if(!paid)
		return (duration > 0 || tool) ? INTERACTION_TRY_BLOCKED : null
	if(paid == USE_TOOL_PENDING)
		return INTERACTION_TRY_RAN // the input is used; the effect follows the wait
	if(result != INTERACTION_TRY_PENDING)
		return result
	// A pay_cost() override that paid without the tool pipeline.
	return finish_attempt(actor, target, held)

/// After the cost: check again (the wait may have changed things), run the effect, send
/// the feedback. The same outcomes as attempt().
/datum/interaction/proc/finish_attempt(mob/actor, atom/target, obj/item/held)
	if(QDELETED(target))
		return (duration > 0 || tool) ? INTERACTION_TRY_BLOCKED : null
	var/reason = why_not(actor, target, held)
	if(reason)
		tell_blocked(actor, target, reason)
		return INTERACTION_TRY_BLOCKED
	var/msg_type = feedback_for(actor, target, held)
	var/shown_name = display_name(actor, target)
	if(!run_effect(actor, target, held))
		return null
	if(!QDELETED(target))
		changed(target) // an interaction is a dispatched call (dx_conventions.md §1)
		target.interaction_ran(actor, src)
	log_input("Interaction: [key_name(actor)] did [id] ([shown_name]) on [target] ([target.type]).")
	act_message_t(actor, target, msg_type, held)
	return INTERACTION_TRY_RAN

/**
 * Calls `effect` and returns whether it ran (TRUE) or declined (FALSE), so an
 * entry moves on to the next candidate. Overridden by subtypes
 * for shapes that are always meant once reached (self-use, hand, alt-click):
 * their effect proc need not return TRUE itself, so a plain existing proc can
 * be pointed at directly with no wrapper.
 */
/datum/interaction/proc/run_effect(mob/actor, atom/target, obj/item/held)
	return holder_call(target, effect, list(actor, held, src))

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

/// The interactions this atom's type offers, as shared singletons. Cached per type.
/proc/interaction_candidates(atom/target)
	return CACHED_KEY(interaction_candidates, target.type, target)

DECLARE_SHARED_CACHE(interaction_candidates, GLOBAL_PROC_REF(build_interaction_candidates), SC_NEVER)

/proc/build_interaction_candidates(atom/target)
	// Capability entries, in capabilities() order (code/datums/capabilities/).
	var/list/candidates = list()
	for(var/datum/interaction/interaction as anything in cap_interactions(target))
		candidates |= interaction
	return candidates

/// Called on the target after an interaction's effect ran: a player (or program) changed it. Types
/// whose scheduled work depends on their settings wake here (a machine's step, a refinery line).
/atom/proc/interaction_ran(mob/actor, datum/interaction/interaction)
	return

// Compiled predicates are shared from the dq_predicate_for() registry.
