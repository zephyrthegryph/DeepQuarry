// Mob Life as a kernel sequence (doc/rewrite/life_sequences.md, doc/rewrite/om_retirement.md L1).
//
// Every living mob runs this sequence while it is in the world (life_om.dm). Its steps are procs on the mob types,
// declared in life_steps() (life_steps.dm) with the edges that keep the old stage order; canmove, HUD and sight are
// on_change() reactions (living_systems.dm), not steps.

/// One Life frame per LIFE_CYCLE of world time (fixed step, catch-up bounded). Parked while every step sleeps, and out
/// of the sweep below RELEVANCE_NEAR (a low-priority mob on a z-level without a living player, life_update_relevance()).
///
/// Stasis slows biology, not the frame: begin() advances the body's stasis counter once per frame and the biology steps
/// skip a paused frame (`when = "!in_stasis"`), so AFK marking, ambience and grabs keep their pace in a stasis bed.
/datum/sequence/life
	name = "life"
	interval = LIFE_CYCLE
	step = LIFE_CYCLE_SECONDS
	max_catchup = LIFE_MAX_CATCHUP
	clock = CLOCK_WORLD
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	park_after = LIFE_PARK_AFTER
	min_relevance = RELEVANCE_NEAR
	wake_all = LIFE_WAKE_ALL
	table_proc = TYPE_PROC_REF(/mob/living, life_steps)
	frame_type = /datum/seq_frame/life
	profile_stride = LIFE_PROFILE_STRIDE
	admit_guard = TRUE
	// Steps are called through the generated switch in life_dispatch.dm, not by name.
	typed_dispatch = TRUE

/// A suspended mob (absorbed prey, a body kept for reforming) runs no frame until it is resumed.
/datum/sequence/life/admit(mob/living/L)
	return !L.rx?.stats || !stat_value(L, STAT_SUSPENDED)

/// The bands of the old Life() sequence, in order.
/datum/sequence/life/anchors()
	return list(
		seq_anchor(LIFE_INPUT),
		seq_anchor(LIFE_BODY, after = LIFE_INPUT),
		seq_anchor(LIFE_MIND, after = LIFE_BODY),
		seq_anchor(LIFE_OUTPUT, after = LIFE_MIND),
		seq_anchor(LIFE_TAIL, after = LIFE_OUTPUT),
	)

/// The frame conditions steps name in `when =`. "placed" and "in_stasis" have no reads: nothing announces a transform
/// or a stasis tick, so a step they block stays awake.
/datum/sequence/life/conditions()
	return list(
		seq_condition("placed", TYPE_PROC_REF(/datum/seq_frame/life, placed)),
		seq_condition("alive", TYPE_PROC_REF(/datum/seq_frame/life, alive), CHANGE_MOB_STAT),
		seq_condition("status_ok", TYPE_PROC_REF(/datum/seq_frame/life, status_passed), CHANGE_MOB_STAT),
		seq_condition("in_stasis", TYPE_PROC_REF(/datum/seq_frame/life, in_stasis)),
	)

/// The Life steps of this mob type: seq_step()s (life_steps.dm). Built once per type, body plan and contributors.
/mob/living/proc/life_steps()
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

/// Life tables read the body plan (physiology), which set_species() can swap: recompose_life() after a swap.
/mob/living/seq_plan_key()
	return body_type

/// Rebuilds this mob's Life table after something seq_plan_key() covers changed (a body plan swap).
/mob/living/proc/recompose_life()
	seq_replan(src, /datum/sequence/life)

/// A Life frame. Typed fields replace the facts: environment() is the air the mob sits in (read once per frame),
/// status_ok is what the status step's update_status() returned (a frame field it sets; unset reads as alive).
/datum/seq_frame/life
	/// This frame is paused by stasis (the body's counter, advanced once per frame): biology steps skip it.
	var/stasis = FALSE
	/// Set by the status step for the steps after it (the "status_ok" condition). Null: not set this frame.
	var/status_ok
	// Pooled frame cache, filled once per frame, cleared by begin() and reset()
	var/datum/gas_mixture/env
	var/env_known = FALSE

/datum/seq_frame/life/begin()
	var/mob/living/L = entity
	stasis = L.body ? L.body.advance_stasis() : FALSE
	status_ok = null
	// ALLOW(ownership): pooled frame cache, filled once per frame, cleared by begin() and reset()
	env = null
	env_known = FALSE

/datum/seq_frame/life/reset()
	. = ..()
	stasis = FALSE
	status_ok = null
	// ALLOW(ownership): pooled frame cache, filled once per frame, cleared by begin() and reset()
	env = null
	env_known = FALSE

/// The air the mob sits in: its turf's, its belly's, or null. Read once per frame.
/datum/seq_frame/life/proc/environment()
	if(env_known)
		return env
	env_known = TRUE
	var/mob/living/L = entity
	if(!L.loc)
		return null
	// ALLOW(ownership): pooled frame cache, filled once per frame, cleared by begin() and reset()
	env = isbelly(L.loc) ? L.loc.return_air_for_internal_lifeform(L) : L.loc.return_air()
	return env

/// Not transforming and somewhere: the old `if(transforming) return` / `if(!loc) return`.
/datum/seq_frame/life/proc/placed()
	var/mob/living/L = entity
	return L.loc && !L.transforming

/datum/seq_frame/life/proc/alive()
	var/mob/living/L = entity
	return L.stat != DEAD

/datum/seq_frame/life/proc/status_passed()
	return isnull(status_ok) ? alive() : status_ok

/datum/seq_frame/life/proc/in_stasis()
	return stasis
