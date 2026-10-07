// How a brain acts and what it records. A tactic acts through the same ops a player's click or a machine's input reaches (perform_op), with the
// mob as the actor, so the AI meets the same requirements, cooldowns and refusals; and every decision it makes can be traced.

/// Set to log every traced brain decision (all brains); a single brain is traced with its `traced` var.
GLOBAL_VAR_INIT(ai_trace_all, FALSE)

/datum/ai_brain
	/// TRUE: this brain writes its decisions to the game log (picks, starts, stops, refused ops).
	var/traced = FALSE

/// Writes one debug line for this brain when it (or every brain, GLOB.ai_trace_all) is traced.
/datum/ai_brain/proc/trace(text)
	if(!traced && !GLOB.ai_trace_all)
		return
	log_game("AI [holder ? "[holder] ([holder.type])" : "(no holder)"]: [text]")

/// Runs the op `key` (mob as actor, AI origin) on `target`. TRUE when it committed; a refusal is traced with its reason.
/// `held` is the item the op uses (a gun, a grenade); `stance` the stance it is made in (set for the op, then put back).
/datum/ai_brain/proc/perform_attack_op(mob/living/actor, atom/target, key, obj/item/held = null, stance = null)
	var/old_stance
	if(stance)
		old_stance = actor.input_stance()
		actor.set_use_stance(stance)
	var/datum/op_result/result = perform_op(actor, target, key, held, ORIGIN_AI, AUTH_AI)
	if(stance)
		actor.set_use_stance(old_stance)
	if(result?.outcome == ACT_COMMITTED)
		trace("op [key] on [target] committed")
		return TRUE
	trace("op [key] on [target] refused: [result ? reason_text(result.reason) : "no result"]")
	return FALSE

/// One step to `where` (a turf or atom) through the "mob_attacks.step" op. TRUE when the mob ended up somewhere else.
/datum/ai_brain/proc/act_step(atom/where)
	if(!holder || !where)
		return FALSE
	var/turf/was = get_turf(holder)
	perform_attack_op(holder, where, "mob_attacks.step")
	return get_turf(holder) != was

/// One step away from `threat`, up to `distance` tiles of room (what step_away() did), through the step op.
/datum/ai_brain/proc/act_step_away(atom/threat, distance = 0)
	if(!holder || !threat)
		return FALSE
	var/turf/away = get_step_away(holder, threat, distance)
	if(!away || away.density)
		return FALSE
	return act_step(away)

// ---------------------------------------------------------------------------
// The accessor seam. A tactic reads the world and issues acts only through these; it never reads brain.model or the brain's
// vars, so a pack can answer them (known_hostiles() from the pack's knowledge, primary_target() from the pack's assignment)
// without a tactic knowing which one does.
// ---------------------------------------------------------------------------

/// TRUE once the brain has a perception model (a brain made with no owner never does).
/datum/ai_brain/proc/perceives()
	return !!model

/// The mobs this brain currently treats as hostile and knows of (a list; empty, never null).
/datum/ai_brain/proc/known_hostiles()
	return model?.visible_hostiles || list()

/// The mobs this brain currently treats as friendly and knows of (a list; empty, never null).
/datum/ai_brain/proc/known_friendlies()
	return model?.visible_friendlies || list()

/// Whoever struck this mob last, or null.
/datum/ai_brain/proc/last_attacker()
	return model?.get_last_attacker()

/// The mob this brain is fighting now, or null.
/datum/ai_brain/proc/primary_target()
	RETURN_TYPE(/mob/living)
	return primary_threat

/// The first step of a path to `goal` (a turf or atom), asking the path system for one when none is cached; null when there is none yet.
/datum/ai_brain/proc/path_to(atom/goal, get_to = 1)
	if(!goal || !holder)
		return null
	if(!smart_step_toward(goal, get_to) && !length(planned_path))
		return null
	return length(planned_path) ? planned_path[1] : null

/// Runs the op `key` on `target` as this mob. TRUE when it committed.
/datum/ai_brain/proc/act(key, atom/target, obj/item/held = null, stance = null)
	if(!holder)
		return FALSE
	return perform_attack_op(holder, target, key, held, stance)

/// Starts the op `key` and returns its /datum/op_result: a null outcome means the op still waits (its later steps run on timers), and
/// the same record is filled in when it ends. The tactic resumes on that outcome.
/datum/ai_brain/proc/act_waiting(key, atom/target, obj/item/held = null)
	if(!holder)
		return null
	var/datum/op_result/result = perform_op(holder, target, key, held, ORIGIN_AI, AUTH_AI)
	trace("op [key] on [target] started: [isnull(result?.outcome) ? "waiting" : "outcome [result?.outcome]"]")
	return result

/// Assigns the mob this brain fights (a tactic that retargets, such as a retaliation, goes through this).
/datum/ai_brain/proc/set_primary_target(mob/living/M)
	rel_set(src, nameof(primary_threat), M)
