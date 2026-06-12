// /datum/ai_behavior — the unit of AI action.
//
// Behaviors are FLYWEIGHTS. One instance per type ever, fetched via
// dq_get_behavior(typepath). Per-mob runtime state (cooldowns, charges) lives
// on the brain or on the source item, NOT on the behavior. Behavior procs are
// pure functions over (brain, target, source).
//
// Lifecycle: evaluate -> start -> tick* -> stop.
//
//   evaluate(brain, source) returns null (ineligible) or DQAI_RESULT(score, target).
//   start(brain, target, source) runs once when the brain picks this behavior.
//   tick(brain, target, source) runs every fast tick while active; returns
//     DQ_BEHAVIOR_CONTINUE / DONE / INTERRUPTED / FAILED.
//   stop(brain, target, source, reason) cleanup.
//
// All initial(var) values are immutable defaults — DO NOT assign to src.* in
// behavior code unless you're prepared for every mob in the round to share
// that change. State lives on brain.behavior_state[type] (cooldowns) or on
// the source.
//
// INTENT CONVENTION: Most behaviors call simple_mob.attack_target() / shoot_target()
// directly, which bypass the click pipeline and don't consult a_intent. If a
// behavior instead routes through the click pipeline — e.g. IAttack() on a
// humanoid mob, which becomes ClickOn(), which dispatches by a_intent — the
// behavior MUST set owner.a_intent before calling, and restore it in stop().
// HURT for kill behaviors, GRAB for vore-style restraint behaviors, DISARM for
// shoves. HELP is for medical / friendly behaviors. The `valid_intents` field
// on this datum is used by player verbs to gate which intents can trigger the
// move; AI ignores it.

GLOBAL_LIST_EMPTY(dq_behaviors)

/proc/dq_get_behavior(type)
	. = GLOB.dq_behaviors[type]
	if(!.)
		. = new type()
		GLOB.dq_behaviors[type] = .

/datum/ai_behavior
	/// Human-readable; used in radial menus + logs.
	var/name = "abstract behavior"
	var/desc = ""
	var/icon_state = null         // optional radial icon

	/// Bitmask of DQ_INTENT_* flags the behavior is valid under. Used only by
	/// player-controlled mobs; AI ignores. Default: hurt-only.
	var/valid_intents = DQ_INTENT_HURT_FLAG

	/// Class for the priority-class comparator. INTERRUPT > OVERRIDE > NORMAL > IDLE.
	var/priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL

	/// Cooldown after a successful execution, in deciseconds. 0 = no cooldown.
	/// Applied to brain.behavior_state[type] for innate behaviors only —
	/// item-granted behaviors (requires_held_source = TRUE) MUST gate via the
	/// source's own state (e.g. gun.next_fire_time, grenade.active). The
	/// dq_combat_ai_item_granted_behaviors_have_no_brain_cooldown unit test
	/// enforces this.
	var/cooldown = 0

	/// Charges available across uses. null = unlimited.
	var/default_charges = null

	/// Bitmask description of what evaluate()'s target field will be.
	var/target_kind = DQ_TARGET_MOB

	/// Range constraints. Optional; behaviors can compute their own.
	var/min_range = 0
	var/max_range = INFINITY

	/// Signal types the brain should subscribe this behavior's owner to so the
	/// brain re-evaluates only when something relevant changes. Empty = re-eval
	/// every slow tick.
	var/list/eval_triggers = null

	/// If TRUE, the brain marks itself busy() during start/tick, blocking new
	/// behavior selection. For long windup attacks like charge_slam.
	var/blocks_reselection = FALSE

	/// Signal types that flinch-cancel this behavior even while it's busy
	/// (blocks_reselection). null = fully committed once started. Lets an elite
	/// telegraph be interrupted by an incoming attack so it can dodge/brace,
	/// while trash mobs stay committed and exploitable. See dispatch_behavior_signal.
	var/list/interruptible_by = null

	/// If TRUE, the behavior should be considered even if the brain has no
	/// primary_threat (e.g. wander, idle_speak).
	var/no_threat_required = FALSE

	/// If TRUE, the behavior's source must be in the mob's hands (granted from
	/// a held item).
	var/requires_held_source = FALSE

// ---------------------------------------------------------------------------
// Lifecycle hooks. Override in subtypes.
// ---------------------------------------------------------------------------

/// Score this behavior's current desirability.
/// Returns null/0 if ineligible, or DQAI_RESULT(score, target) where score is
/// a positive number and target is the atom the behavior wants to act on.
/datum/ai_behavior/proc/evaluate(datum/ai_brain/brain, atom/source)
	return null

/// Called once when the brain commits to running this behavior.
/// Default sets click cooldown if applicable and faces the target.
/datum/ai_behavior/proc/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return DQ_BEHAVIOR_FAILED
	if(ismob(target) || isobj(target) || isturf(target))
		owner.face_atom(target)
	if(blocks_reselection)
		brain.busy = TRUE
	return DQ_BEHAVIOR_CONTINUE

/// Called every fast tick while this behavior is active. Default returns DONE
/// — a behavior with no tick body runs once on start() and finishes.
/datum/ai_behavior/proc/tick(datum/ai_brain/brain, atom/target, atom/source)
	return DQ_BEHAVIOR_DONE

/// Called when the behavior ends (DONE/INTERRUPTED/FAILED/QDEL). Subtypes
/// should clean up timers, overlays, telegraphs etc here. Always call ..()
/// — the base clears the busy flag.
/datum/ai_behavior/proc/stop(datum/ai_brain/brain, atom/target, atom/source, reason)
	if(blocks_reselection)
		brain.busy = FALSE
	if(reason == DQ_BEHAVIOR_STOP_COMPLETED && cooldown)
		brain.set_cooldown(type, source, cooldown)
	else if(reason == DQ_BEHAVIOR_STOP_FAILED)
		brain.set_cooldown(type, source, DQ_BEHAVIOR_FAIL_COOLDOWN)
	return

/// Called when one of the behavior's eval_triggers fires. Default re-runs
/// brain.invalidate_selection() so the active behavior gets re-considered.
/// Additional positional args appear in the implicit `args` list.
/datum/ai_behavior/proc/on_signal(datum/ai_brain/brain, sig_type)
	brain.invalidate_selection()
	return

// ---------------------------------------------------------------------------
// Helpers usable by subtypes.
// ---------------------------------------------------------------------------

/// True if the behavior's cooldown (per-source if item-granted) has expired.
/datum/ai_behavior/proc/is_off_cooldown(datum/ai_brain/brain, atom/source)
	return brain.cooldown_until(type, source) <= world.time

/// Override to limit a behavior to a specific mob shape. Cheaper than checking
/// in evaluate() because the brain caches eligibility once per slow tick.
/datum/ai_behavior/proc/applicable_to(mob/living/owner)
	return TRUE
