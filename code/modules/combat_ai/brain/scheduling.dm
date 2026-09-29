// AI brain scheduling on the object model (doc/rewrite/object_model_core.md §4, completion plan
// §3.6 wave F2). This replaces SSai (strategic, 2 s), SSaifast (tactical, 0.25 s) and the
// init-only SSdq_combat_ai.
//
// Both loops are behaviours on the brain's mob, so the mob's entity state schedules them:
// - relevance: a low-priority mob on a z-level with no living player is at RELEVANCE_NONE
//   (life_update_relevance()) and both loops park, exactly as SSai's process_z/low_priority
//   test used to skip it. They resume the moment a player arrives, without catch-up.
// - clock: CLOCK_BIO. A mob whose biology is stopped (stasis) takes its brain off the ring.
// - wakes: a calm brain leaves the strategic ring altogether (hibernate_calm()) and waits on
//   the mob chunks in its vision; attacks, new targets and movement nearby put it back
//   (invalidate_selection(), wake_from_chunks()).
// The brain keeps process_flags as the record of which loops it has asked for; attaching and
// detaching the behaviours is the only thing that changes whether they run.

/datum/om/behaviour/ai_brain
	abstract_type = /datum/om/behaviour/ai_brain
	lane = LANE_SIMULATION
	clock = CLOCK_BIO
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	relevance = list(OM_PARK, null, null, null)

/// The mob's brain, if it is running one of these loops.
/datum/om/behaviour/ai_brain/proc/brain_of(mob/living/L)
	var/datum/ai_brain/A = L.ai_brain
	if(!A || QDELETED(A) || A.holder != L)
		return null
	return A

/// Perception, threat choice and hibernation. Deferred brains (next_strategic_at in the future:
/// calm brains use a long discovery cadence) cost one compare.
/datum/om/behaviour/ai_brain/strategic
	name = "AI brain: strategic"
	every = 2 SECONDS

/datum/om/behaviour/ai_brain/strategic/tick(mob/living/L, dt)
	var/datum/ai_brain/A = brain_of(L)
	if(!A || A.is_busy() || !L.loc)
		return
	// ALLOW(sys_deadline_poll): backoff gate on a behaviour that already ticks every 2 s; the brain moves next_strategic_at itself
	if(A.next_strategic_at > world.time)
		return
	A.handle_strategicals()

/// Behaviour selection and movement, only while the brain has a combat target
/// (sync_fast_processing()).
/datum/om/behaviour/ai_brain/tactical
	name = "AI brain: tactical"
	every = 0.25 SECONDS
	order_after = list(/datum/om/behaviour/ai_brain/strategic)

/datum/om/behaviour/ai_brain/tactical/tick(mob/living/L, dt)
	var/datum/ai_brain/A = brain_of(L)
	if(!A || A.is_busy())
		return
	A.handle_tactics()

/// The behaviour type serving one DQAI_* loop flag.
/proc/dq_ai_loop_behaviour(flag)
	switch(flag)
		if(DQAI_PROCESSING)
			return /datum/om/behaviour/ai_brain/strategic
		if(DQAI_FASTPROCESSING)
			return /datum/om/behaviour/ai_brain/tactical

/// Starts one loop (DQAI_PROCESSING or DQAI_FASTPROCESSING). Idempotent.
/datum/ai_brain/proc/start_loop(flag)
	if(process_flags & flag)
		return
	process_flags |= flag
	if(holder && !QDELETED(holder))
		om_attach(holder, dq_ai_loop_behaviour(flag))

/// Stops one loop. Idempotent.
/datum/ai_brain/proc/stop_loop(flag)
	if(!(process_flags & flag))
		return
	process_flags &= ~flag
	if(holder)
		om_detach(holder, dq_ai_loop_behaviour(flag))

/// TRUE while the loop is scheduled on the mob (it may still be parked by relevance or clock).
/datum/ai_brain/proc/loop_running(flag)
	return holder && om_attached(holder, dq_ai_loop_behaviour(flag))

// --- Navigation revision -----------------------------------------------------------------------
// Bumped when doors open, close or change access. Cached AI paths and the pathfinder's failure
// cache are keyed by it.

GLOBAL_VAR_INIT(ai_navigation_revision, 1)

/proc/publish_navigation_change()
	GLOB.ai_navigation_revision++

// --- Calm-brain hibernation on mob chunks (code/modules/mob/mob_chunks.dm) ---------------------

/// A mob moved in a chunk a calm brain watches.
/datum/om/behaviour/sleeper/ai_brain
	name = "calm AI brain"

/datum/om/behaviour/sleeper/ai_brain/on_wake(datum/ai_brain/B, changes)
	B.wake_from_chunks()

/// A calm brain stops strategic processing until a mob moves in a chunk within its vision
/// (CHANGE_CHUNK_ANY_MOB). FALSE if it has a threat, a behavior or a player.
/datum/ai_brain/proc/hibernate_calm()
	var/turf/T = get_turf(holder)
	if(!T || primary_threat || active_behavior_type || holder.client)
		return FALSE
	cancel_chunk_sleep()
	om_attach(src, /datum/om/behaviour/sleeper/ai_brain)
	react_sleep_tokens = watch_mob_chunks(src, mob_chunks_around(T, vision_range), CHANGE_CHUNK_ANY_MOB, /datum/om/behaviour/sleeper/ai_brain)
	manage_processing(0)
	return TRUE

/// Drops the chunk subscriptions without waking (Destroy, or before re-subscribing).
/datum/ai_brain/proc/cancel_chunk_sleep()
	if(react_sleep_tokens)
		react_sleep_tokens = unwatch_mob_chunks(src, react_sleep_tokens, CHANGE_CHUNK_ANY_MOB, /datum/om/behaviour/sleeper/ai_brain)

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
/datum/ai_brain/om_sleep_violation()
	if(!react_sleep_tokens || (process_flags & DQAI_PROCESSING))
		return null
	if(primary_threat)
		return "hibernating with a primary threat"
	return null

/// Milliseconds the live scheduler has spent in the AI loops (strategic + tactical), for
/// time_track (it replaced SSai.cost).
/proc/om_ai_brain_cost()
	var/datum/om/scheduler/sched = GLOB.om_live_sched || om_scheduler()
	var/datum/om/registry/reg = om_registry()
	. = 0
	for(var/path in list(/datum/om/behaviour/ai_brain/strategic, /datum/om/behaviour/ai_brain/tactical))
		var/datum/om/behaviour/B = reg.behaviour(path)
		if(B && B.id <= length(sched.stats))
			var/list/S = sched.stats[B.id]
			if(S)
				. += S[OM_STAT_MS]
	. = round(., 0.01)
