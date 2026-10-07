// AI brain scheduling (doc/rewrite/final_api.html section 14: the brain's loops are keyed every() entries of a capability on
// the mob's own clock). This replaces SSai (strategic, 2 s), SSaifast (tactical, 0.25 s), the init-only SSdq_combat_ai and
// the OM behaviours that ran them.
//
// Each loop is a capability the brain grants to its mob (start_loop()) and revokes (stop_loop()):
// - relevance: a low-priority mob on a z-level with no living player is at RELEVANCE_NONE (life_update_relevance()) and its
//   loops park on `when = STAT_RELEVANCE` (final_api section 3), as SSai's process_z/low_priority test used to skip it.
//   Mobs hold relevance by z-level occupancy, not by SSproximity: an AI mob changes simulation state (it attacks, walks, opens doors)
//   and a mob out of every player's sight still has to be where the round expects it (framework_gaps.md F6). They resume the
//   moment a player arrives, without catch-up.
// - clock: CLOCK_OWN, the mob's own clock: suspension pauses the loops.
// - runlevels: outside RUNLEVEL_GAME and RUNLEVEL_POSTGAME the loops skip their runs.
// - parking: a calm brain with nothing to do leaves the loop altogether (park_calm()); what its pack perceives (the pack watches the mob chunks in its
//   members' vision and perceives on activity there), an attack or a new target puts it back (invalidate_selection(), wake_loops()).
// There is one loop: the action loop. Its interval is the active tactic's; with no tactic it is DQ_ACTION_TICK while the brain has a target and
// DQ_CALM_TICK otherwise, and the slow work (re-reading what the mob holds, the backstop perception pass, idle selection) runs inside it on its own cadence.
// The brain keeps process_flags as the record of which loops it has asked for; granting and revoking the loop capabilities
// is the only thing that changes whether they run.

/// Milliseconds spent in the AI loops (strategic + tactical) since boot, for time_track (it replaced SSai.cost).
GLOBAL_VAR_INIT(ai_brain_cost_ms, 0)

/datum/capability/ai_loop
	/// DQAI_FASTPROCESSING.
	var/loop_flag

/// The mob's brain, if it is running one of these loops.
/datum/capability/ai_loop/proc/brain_of(mob/living/L)
	var/datum/ai_brain/A = L.ai_brain
	if(!A || QDELETED(A) || A.holder != L)
		return null
	return A

/// The round is on: the loops skip their runs outside RUNLEVEL_GAME and RUNLEVEL_POSTGAME.
/proc/dq_ai_runlevel_ok()
	return !!((RUNLEVEL_GAME | RUNLEVEL_POSTGAME) & (1 << (Kernel.current_runlevel - 1)))

/// The loops run while the mob is relevant (a player on its z-level, or a high-priority mob) and the round is on. The relevance half is the loops'
/// own `when = STAT_RELEVANCE`; this is the whole answer for tests and diagnostics.
/proc/dq_ai_loops_may_run(mob/living/L)
	if(stat_value(L, STAT_RELEVANCE) < RELEVANCE_NEAR)
		return FALSE
	return dq_ai_runlevel_ok()

/// The brain's one loop: housekeeping on its own cadence, then behaviour selection and movement. Granted while the brain is awake (not parked).
CAPABILITY_TYPE(ai_tactical, CAP_AI_TACTICAL, /datum/capability/ai_loop/tactical, key = NONE)
/datum/capability/ai_loop/tactical
	loop_flag = DQAI_FASTPROCESSING

/datum/capability/ai_loop/tactical/entries()
	return list(every(TYPE_PROC_REF(/mob/living, ai_action_interval), then(CAP_PROC(tactical_tick)), when = STAT_RELEVANCE))

/datum/capability/ai_loop/tactical/proc/tactical_tick(datum/act/timer/A)
	if(!dq_ai_runlevel_ok())
		return
	var/datum/ai_brain/brain = brain_of(A.holder)
	brain?.tactical_tick()

/// The action loop's cadence, asked before every run (every() with an interval proc): the active behaviour's own interval.
/mob/living/proc/ai_action_interval(datum/act/timer/A)
	return ai_brain?.action_interval() || DQ_ACTION_TICK

/// Deciseconds to the loop's next run: the active behaviour's interval_for(), else the combat rate with a target (it is re-selecting) and the calm rate without.
/datum/ai_brain/proc/action_interval()
	var/interval = primary_threat ? DQ_ACTION_TICK : DQ_CALM_TICK
	if(active_behavior_type)
		var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
		interval = B.interval_for(src)
	armed_interval = interval
	return interval

/// An event (damage, a new target, a finished behaviour) wants the loop to run now rather than at its armed interval: a loop armed
/// longer than the combat rate (a stretched idle behaviour) is re-armed, which runs it at the combat rate again.
/datum/ai_brain/proc/poke_action_loop()
	if(armed_interval > DQ_ACTION_TICK && (process_flags & DQAI_FASTPROCESSING) && (primary_threat || active_behavior_type || armed_interval > DQ_CALM_TICK))
		trace("action loop poked (armed at [armed_interval] ds)")
		stop_loop(DQAI_FASTPROCESSING)
		start_loop(DQAI_FASTPROCESSING)

/// One run of the tactical loop (the capability's every(), and tests driving a brain by hand).
/datum/ai_brain/proc/tactical_tick()
	if(waiting_op && !isnull(waiting_op.outcome))
		op_wait_ended()
	if(is_busy())
		return
	var/started = TICK_USAGE
	strategic_tick() // the slow work, gated by its own cadence (next_strategic_at)
	handle_tactics()
	GLOB.ai_brain_cost_ms += TICK_USAGE_TO_MS(started)

/// The capability serving the loop flag (the action loop; DQAI_PROCESSING is only the "awake" bit and has none).
/proc/dq_ai_loop_capability(flag)
	if(flag == DQAI_FASTPROCESSING)
		return /datum/capability/ai_loop/tactical

/// Sets a loop bit: DQAI_PROCESSING says the brain is awake (the action loop runs while it is), DQAI_FASTPROCESSING is the loop itself. Idempotent.
/datum/ai_brain/proc/start_loop(flag)
	if(process_flags & flag)
		return
	process_flags |= flag
	var/cap = dq_ai_loop_capability(flag)
	if(cap && holder && !QDELETED(holder))
		grant(holder, cap, src)
	if(flag == DQAI_PROCESSING)
		sync_fast_processing()

/// Clears a loop bit. Idempotent.
/datum/ai_brain/proc/stop_loop(flag)
	if(!(process_flags & flag))
		return
	process_flags &= ~flag
	var/cap = dq_ai_loop_capability(flag)
	if(cap && holder)
		revoke(holder, cap, src)
	if(flag == DQAI_PROCESSING)
		sync_fast_processing()

/// TRUE while the loop is granted on the mob (it may still skip its runs by relevance or runlevel); the awake bit for DQAI_PROCESSING.
/datum/ai_brain/proc/loop_running(flag)
	if(flag == DQAI_PROCESSING)
		return !!(process_flags & DQAI_PROCESSING)
	return holder && granted(holder, dq_ai_loop_capability(flag))

// --- Navigation revision -----------------------------------------------------------------------
// Bumped when doors open, close or change access. Cached AI paths and the pathfinder's failure
// cache are keyed by it.

GLOBAL_VAR_INIT(ai_navigation_revision, 1)

/proc/publish_navigation_change()
	GLOB.ai_navigation_revision++

// --- Calm-brain parking ----------------------------------------------------------------------

/// A calm brain with nothing to do leaves the loop until something wakes it (wake_loops()). FALSE if it has a threat, a behavior or a player.
/datum/ai_brain/proc/park_calm()
	if(!holder || primary_threat || active_behavior_type || holder.client)
		return FALSE
	parked = TRUE
	sleep_audit_join(src)
	trace("parked: calm, nothing to do")
	manage_processing(0)
	return TRUE

/// Times a parked brain was woken (diagnostics and tests).
/datum/ai_brain/var/tmp/wakes = 0
/// TRUE while the brain sleeps in park_calm().
/datum/ai_brain/var/tmp/parked = FALSE

/// Wakes a parked brain now: its pack perceived something, it was hit, it was given a target. No-op unless it is parked.
/datum/ai_brain/proc/wake_loops()
	if(!parked)
		return
	parked = FALSE
	wakes++
	trace("woken")
	next_strategic_at = 0
	manage_processing(DQAI_PROCESSING)

/// Asleep with a threat in hand: it should be awake.
/datum/ai_brain/sleep_violation()
	if(!parked || (process_flags & DQAI_PROCESSING))
		return null
	if(primary_threat)
		return "parked with a primary threat"
	return null

/// One run of the slow work (the action loop's, gated by its own cadence next_strategic_at; tests driving a brain by hand call it too).
/datum/ai_brain/proc/strategic_tick()
	if(is_busy() || !holder?.loc)
		return
	if(BEFORE(holder, next_strategic_at, CLOCK_WORLD))
		return
	var/started = TICK_USAGE
	handle_strategicals()
	GLOB.ai_brain_cost_ms += TICK_USAGE_TO_MS(started)
