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
// - wakes: a calm brain leaves the strategic loop altogether (hibernate_calm()) and waits on the mob chunks in its vision;
//   attacks, new targets and movement nearby put it back (invalidate_selection(), wake_from_chunks()).
// The brain keeps process_flags as the record of which loops it has asked for; granting and revoking the loop capabilities
// is the only thing that changes whether they run.

/// Milliseconds spent in the AI loops (strategic + tactical) since boot, for time_track (it replaced SSai.cost).
GLOBAL_VAR_INIT(ai_brain_cost_ms, 0)

/datum/capability/ai_loop
	/// DQAI_PROCESSING or DQAI_FASTPROCESSING.
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

/// Perception, threat choice and hibernation. Deferred brains (next_strategic_at in the future: calm brains use a long discovery
/// cadence) cost one compare.
CAPABILITY_TYPE(ai_strategic, CAP_AI_STRATEGIC, /datum/capability/ai_loop/strategic, key = NONE)
/datum/capability/ai_loop/strategic
	loop_flag = DQAI_PROCESSING

/datum/capability/ai_loop/strategic/entries()
	return list(every(2 SECONDS, then(CAP_PROC(strategic_tick)), when = STAT_RELEVANCE))

/datum/capability/ai_loop/strategic/proc/strategic_tick(datum/act/timer/A)
	if(!dq_ai_runlevel_ok())
		return
	var/datum/ai_brain/brain = brain_of(A.holder)
	brain?.strategic_tick()

/// One run of the strategic loop (the capability's every(), and tests driving a brain by hand).
/datum/ai_brain/proc/strategic_tick()
	if(is_busy() || !holder?.loc)
		return
	if(BEFORE(holder, next_strategic_at, CLOCK_WORLD))
		return
	var/started = TICK_USAGE
	handle_strategicals()
	GLOB.ai_brain_cost_ms += TICK_USAGE_TO_MS(started)

/// Behaviour selection and movement, only while the brain has a combat target (sync_fast_processing()).
CAPABILITY_TYPE(ai_tactical, CAP_AI_TACTICAL, /datum/capability/ai_loop/tactical, key = NONE)
/datum/capability/ai_loop/tactical
	loop_flag = DQAI_FASTPROCESSING

/datum/capability/ai_loop/tactical/entries()
	return list(every(0.25 SECONDS, then(CAP_PROC(tactical_tick)), when = STAT_RELEVANCE))

/datum/capability/ai_loop/tactical/proc/tactical_tick(datum/act/timer/A)
	if(!dq_ai_runlevel_ok())
		return
	var/datum/ai_brain/brain = brain_of(A.holder)
	brain?.tactical_tick()

/// One run of the tactical loop (the capability's every(), and tests driving a brain by hand).
/datum/ai_brain/proc/tactical_tick()
	if(is_busy())
		return
	var/started = TICK_USAGE
	handle_tactics()
	GLOB.ai_brain_cost_ms += TICK_USAGE_TO_MS(started)

/// The capability serving one DQAI_* loop flag.
/proc/dq_ai_loop_capability(flag)
	switch(flag)
		if(DQAI_PROCESSING)
			return /datum/capability/ai_loop/strategic
		if(DQAI_FASTPROCESSING)
			return /datum/capability/ai_loop/tactical

/// Starts one loop (DQAI_PROCESSING or DQAI_FASTPROCESSING). Idempotent.
/datum/ai_brain/proc/start_loop(flag)
	if(process_flags & flag)
		return
	process_flags |= flag
	if(holder && !QDELETED(holder))
		grant(holder, dq_ai_loop_capability(flag), src)

/// Stops one loop. Idempotent.
/datum/ai_brain/proc/stop_loop(flag)
	if(!(process_flags & flag))
		return
	process_flags &= ~flag
	if(holder)
		revoke(holder, dq_ai_loop_capability(flag), src)

/// TRUE while the loop is granted on the mob (it may still skip its runs by relevance or runlevel).
/datum/ai_brain/proc/loop_running(flag)
	return holder && granted(holder, dq_ai_loop_capability(flag))

// --- Navigation revision -----------------------------------------------------------------------
// Bumped when doors open, close or change access. Cached AI paths and the pathfinder's failure
// cache are keyed by it.

GLOBAL_VAR_INIT(ai_navigation_revision, 1)

/proc/publish_navigation_change()
	GLOB.ai_navigation_revision++

// --- Calm-brain hibernation on mob chunks (code/modules/mob/mob_chunks.dm) ---------------------

/// A calm brain stops strategic processing until a mob moves in a chunk within its vision
/// (CHANGE_CHUNK_ANY_MOB). FALSE if it has a threat, a behavior or a player.
/datum/ai_brain/proc/hibernate_calm()
	var/turf/T = get_turf(holder)
	if(!T || primary_threat || active_behavior_type || holder.client)
		return FALSE
	cancel_chunk_sleep()
	sleep_audit_join(src)
	react_sleep_tokens = watch_mob_chunks(src, mob_chunks_around(T, vision_range), CHANGE_CHUNK_ANY_MOB, PROC_REF(chunk_woke))
	manage_processing(0)
	return TRUE

/// Drops the chunk subscriptions without waking (Destroy, or before re-subscribing).
/datum/ai_brain/proc/cancel_chunk_sleep()
	if(react_sleep_tokens)
		react_sleep_tokens = unwatch_mob_chunks(src, react_sleep_tokens, CHANGE_CHUNK_ANY_MOB)

/// A mob moved in a chunk this calm brain watches.
/datum/ai_brain/proc/chunk_woke(datum/mob_chunk/C, bits)
	wake_from_chunks()

/// Wakes a hibernating brain now. No-op unless it sleeps on chunk keys.
/// Chunk wakes so far (diagnostics and tests).
/datum/ai_brain/var/tmp/chunk_wakes = 0

/datum/ai_brain/proc/wake_from_chunks()
	if(!react_sleep_tokens)
		return
	chunk_wakes++
	cancel_chunk_sleep()
	if(QDELETED(src))
		return
	next_strategic_at = 0
	manage_processing(DQAI_PROCESSING)

/// Asleep with a threat in hand: it should be awake.
/datum/ai_brain/sleep_violation()
	if(!react_sleep_tokens || (process_flags & DQAI_PROCESSING))
		return null
	if(primary_threat)
		return "hibernating with a primary threat"
	return null
