// Mob Life as a kernel sequence (doc/rewrite/life_sequences.md).
//
// S0 defines the sequence Life moves onto; no mob runs it yet. The Life stages move in waves: S1 dissolves the
// machine pipeline, S2 turned life_derive / life_present / life_vision into on_change reactions on /mob/living (at_most =,
// living_systems.dm), S3
// turns the main stages into procs on /mob/living and its subtypes, declared in life_steps() with the edges
// life_sequence_edges() derives from today's `order` numbers, and S4 deletes the pipeline runner.

/// One Life frame per LIFE_CYCLE of the mob's biological time (fixed step, catch-up bounded). Parked while every
/// step sleeps, and out of the sweep below RELEVANCE_NEAR (a low-priority mob on a z-level without a living player,
/// life_update_relevance()).
/datum/sequence/life
	name = "life"
	interval = LIFE_CYCLE
	step = LIFE_CYCLE_SECONDS
	max_catchup = LIFE_MAX_CATCHUP
	// Stasis (EFFECT_CLOCK_BIO_INHIBIT) stretches the frames: at rate 0.1 a frame comes every ten cycles, at 0 none.
	clock = CLOCK_BIO
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	park_after = LIFE_PARK_AFTER
	min_relevance = RELEVANCE_NEAR
	wake_all = LIFE_WAKE_ALL
	table_proc = TYPE_PROC_REF(/mob/living, life_steps)
	frame_type = /datum/seq_frame/life
	profile_stride = LIFE_PROFILE_STRIDE

/// The bands of the old Life() sequence, in order.
/datum/sequence/life/anchors()
	return list(
		seq_anchor(LIFE_INPUT),
		seq_anchor(LIFE_BODY, after = LIFE_INPUT),
		seq_anchor(LIFE_MIND, after = LIFE_BODY),
		seq_anchor(LIFE_OUTPUT, after = LIFE_MIND),
		seq_anchor(LIFE_TAIL, after = LIFE_OUTPUT),
	)

/// The old gates (the pipeline's facts). "placed" and "in_stasis" have no reads: nothing announces a transform or
/// a stasis tick, so a step they block stays awake, as before.
/datum/sequence/life/conditions()
	return list(
		seq_condition("placed", TYPE_PROC_REF(/datum/seq_frame/life, placed)),
		seq_condition("alive", TYPE_PROC_REF(/datum/seq_frame/life, alive), CHANGE_MOB_STAT),
		seq_condition("status_ok", TYPE_PROC_REF(/datum/seq_frame/life, status_passed), CHANGE_MOB_STAT),
		seq_condition("in_stasis", TYPE_PROC_REF(/datum/seq_frame/life, in_stasis)),
	)

/// The Life steps of this mob type: seq_step()s (S3 moves the stages here). Built once per type and body plan.
/mob/living/proc/life_steps()
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

/// Life tables read the body plan (physiology), which set_species() can swap: seq_replan() after a swap.
/mob/living/seq_plan_key()
	return body_type

/// A Life frame. Typed fields replace the facts: environment() is the air the mob sits in (read once per frame),
/// status_ok is what the status step's update_status() returned (a frame field it sets; unset reads as alive).
/datum/seq_frame/life
	/// Stasis applies (the bio clock runs slow). The clock already stretches the frames; steps that care whether a
	/// mob is in stasis at all read this.
	var/stasis = FALSE
	/// Set by the status step for the steps after it (the "status_ok" condition). Null: not set this frame.
	var/status_ok
	// Pooled frame cache, filled once per frame, cleared by begin() and reset()
	var/datum/gas_mixture/env
	var/env_known = FALSE

/datum/seq_frame/life/begin()
	var/mob/living/L = entity
	stasis = L.om_rec?.contribs ? om_clock_rate_of(L, CLOCK_BIO) < 1 : FALSE
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

// ---------------------------------------------------------------- deriving Life's edges (S3's migration aid)
// These read the Life pipeline (code/datums/om/pipeline.dm) and go with it in S4.

/// A Life stage family's step key: its path under /datum/om/stage/life, with "_" for "/" (breathing,
/// trait_diabetic). The derived edges assume the step keys are these (the tie-break sorts keys).
/proc/life_sequence_key(family)
	return replacetext(copytext("[family]", length("/datum/om/stage/life/") + 1), "/", "_")

/// The anchor of a Life stage family, from its root's `order`.
/proc/life_sequence_band(family)
	var/datum/om/stage/root = om_registry().stage_by_type[family]
	var/order = root?.order || 0
	if(order >= LIFE_PHASE_TAIL)
		return LIFE_TAIL
	if(order >= LIFE_PHASE_OUTPUT)
		return LIFE_OUTPUT
	if(order >= LIFE_PHASE_MIND)
		return LIFE_MIND
	if(order >= LIFE_PHASE_BODY)
		return LIFE_BODY
	return LIFE_INPUT

/// The Life pipeline's plan `plan` as step keys, in today's run order.
/proc/life_sequence_plan_keys(datum/om/plan/plan)
	. = list()
	for(var/datum/om/stage/T as anything in plan.stages)
		. += life_sequence_key(T.family)

/// The Life pipeline's plans as step keys, for seq_derive_edges(): every plan built so far, and for each of
/// `entities` its plan alone, with each of `extra_types` (trait stages), and with all of them. Returns
/// list(plans, band_of), band_of mapping every key to its anchor.
/proc/life_sequence_plans(list/entities, list/extra_types)
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/life)
	var/list/extra_sets = list(null)
	for(var/path in extra_types)
		extra_sets += list(list(path))
	if(length(extra_types) > 1)
		extra_sets += list(extra_types.Copy())
	for(var/datum/E as anything in entities)
		for(var/extras in extra_sets)
			P.plan_for(E, extras)
	var/list/plans = list()
	var/list/band_of = list()
	for(var/key in P.plans)
		var/datum/om/plan/plan = P.plans[key]
		plans += list(life_sequence_plan_keys(plan))
		for(var/datum/om/stage/T as anything in plan.stages)
			band_of[life_sequence_key(T.family)] = life_sequence_band(T.family)
	return list(plans, band_of)

/// Life's step edges, derived from today's plans (life_sequence_plans()). Returns list(edges, plans); problems go
/// to `errors_out`. S3 writes each step's edges into life_steps() and keeps the order test green.
/proc/life_sequence_edges(list/entities, list/extra_types, list/errors_out)
	var/list/result = life_sequence_plans(entities, extra_types)
	var/list/plans = result[1]
	var/list/anchors = list(LIFE_INPUT, LIFE_BODY, LIFE_MIND, LIFE_OUTPUT, LIFE_TAIL)
	return list(seq_derive_edges(plans, result[2], anchors, errors_out), plans)

/// The derived edges as text, one step per line (`key: after = list(...)`), to paste from.
/proc/life_sequence_edge_report(list/edges)
	var/list/lines = list()
	for(var/key in edges)
		var/list/after = edges[key]
		var/list/quoted = list()
		for(var/target in after)
			quoted += (target in list(LIFE_INPUT, LIFE_BODY, LIFE_MIND, LIFE_OUTPUT, LIFE_TAIL)) ? target : "\"[target]\""
		lines += "[key]: after = list([jointext(quoted, ", ")])"
	return jointext(lines, "\n")
