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
