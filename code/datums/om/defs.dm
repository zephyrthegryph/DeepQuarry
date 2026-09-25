// Object-model core: DEF types (doc/rewrite/object_model_core.md).
//
// Every DEF is a singleton built once by the registry (registry.dm). Its
// declaration vars are read-only after boot; the registry writes the
// compiled_* / id vars once, during build. Nothing per entity lives on a DEF:
// per-entity state is on the entity's /datum/om/rec, per-scheduler state on
// the scheduler. That is what makes "shared mutable per-type config"
// impossible by construction.
//
// Paths live under /datum/om/ because /datum/event and /datum/effect already
// exist in this codebase (xenoarch and random events).

/datum/om
	/// A type whose abstract_type is its own path is not instantiated.
	abstract_type = /datum/om
	/// Only built by registries that name it explicitly (unit tests that
	/// need deliberately broken declarations).
	var/registry_skip = FALSE

// ===================================================================== behaviours

/datum/om/behaviour
	abstract_type = /datum/om/behaviour
	var/name
	/// Target interval between tick() calls, deciseconds. 0: no cadence.
	var/every = 0
	/// Hard staleness bound, deciseconds. 0: 4 * every. Rings close to it borrow budget.
	var/max_interval = 0
	/// Seconds. A tick with a larger dt is split into equal substeps.
	var/max_dt = 0
	/// Seconds. Fixed-step discrete work: on_step(E) runs once per step elapsed.
	var/step_interval = 0
	/// Max on_step() calls per tick; the rest is dropped and counted as a breach.
	var/max_catchup = 5
	/// CLOCK_* domain id. dt is scaled by the entity's rate in that domain.
	var/clock
	/// LANE_*.
	var/lane = LANE_SIMULATION
	/// Behaviour types this one runs after (topological, compiled at boot).
	var/list/order_after
	/// Interval per relevance level: list(NONE, NEAR, VISIBLE, WATCHED), each
	/// deciseconds, OM_SLEEP, or null for `every`. Null list: `every` always.
	var/list/relevance
	/// Channels on the entity that wake this behaviour (on_wake).
	var/wake_on = 0
	/// relation type (or list of relation types, a path) -> channel mask on the
	/// related entity. CHANGE_RELATION_ADDED/REMOVED here mean edges of that
	/// relation being added to or removed from this entity.
	var/list/wake_on_related
	/// Native (Rust-owned) watch bits; see native.dm.
	var/wake_on_native = 0
	/// Check spec: on_wake runs only when it passes.
	var/wake_if
	/// Check specs gating roster membership (re-checked only when their
	/// depends_on channels change).
	var/list/requires
	/// Event types handled (subtypes included).
	var/list/handles
	/// Output channel. Behaviours waking on it are ordered after this one.
	var/produces = 0
	/// Set if hooks call om_hold(): holds not repeated on the next call are released.
	var/holds = FALSE

	// ---- compiled by the registry ----
	var/id = 0
	/// Fixed-step behaviours: this behaviour's index in rec.steps (the step accumulators).
	var/step_idx = 0
	var/clock_idx = 0
	var/datum/om/check/compiled_wake_if
	var/list/compiled_requires
	var/requires_mask = 0
	/// list of list(list(relation ids path), mask)
	var/list/compiled_related
	var/related_added_mask = 0
	/// Resolved intervals per relevance level (4 numbers, 0 = no cadence).
	var/list/compiled_intervals
	var/compiled_max_interval = 0
	/// wake_on | requires_mask, the channels this behaviour contributes to listen masks.
	var/interest = 0

/datum/om/behaviour/proc/tick(datum/E, dt)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/om/behaviour/proc/on_wake(datum/E, changes)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/om/behaviour/proc/on_deadline(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/om/behaviour/proc/on_step(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/om/behaviour/proc/on_start(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/om/behaviour/proc/on_stop(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// Fallback for events whose type defines no typed handler.
/datum/om/behaviour/proc/on_event(datum/E, datum/om/event/event)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// Rust-owned watch delivery (native.dm).
/datum/om/behaviour/proc/on_native(datum/E, native_bits)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// A behaviour synthesised from a decl's reacts/ticks/events row: calls a
/// proc on the entity itself (src is the entity, typed).
/datum/om/behaviour/inline
	abstract_type = /datum/om/behaviour/inline
	var/call_path
	var/mode

/datum/om/behaviour/inline/tick(datum/E, dt)
	call(E, call_path)(dt)

/datum/om/behaviour/inline/on_wake(datum/E, changes)
	call(E, call_path)(changes)

/datum/om/behaviour/inline/on_deadline(datum/E)
	call(E, call_path)()

/datum/om/behaviour/inline/on_event(datum/E, datum/om/event/event)
	call(E, call_path)(event)

// ===================================================================== events

/datum/om/event
	abstract_type = /datum/om/event
	/// before_* events are synchronous and may return EVENT_VETO.
	var/before = FALSE
	/// Re-entrant emits of the same type to the same entity keep only the latest.
	var/coalesce = TRUE
	/// Dropped inside bulk_begin()/bulk_end().
	var/skip_in_bulk = FALSE
	/// Set by om_emit().
	var/datum/entity

/// Double dispatch: typed events override this to call their own
/// /datum/om/behaviour/proc/on_<event>(E, event), declared next to the event.
/datum/om/event/proc/dispatch(datum/om/behaviour/B, datum/E)
	return B.on_event(E, src)

/datum/om/event/before
	abstract_type = /datum/om/event/before
	before = TRUE
	coalesce = FALSE

// ===================================================================== relations

/datum/om/relation
	abstract_type = /datum/om/relation
	var/name
	/// A source has at most one edge of this relation.
	var/source_single = FALSE
	/// A target has at most one edge of this relation.
	var/target_single = FALSE
	/// OM_REL_REPLACE or OM_REL_REFUSE when a single end is already taken.
	var/conflict = OM_REL_REPLACE
	/// OM_END_UNLINK or OM_END_DELETE_OTHER when that end is deleted.
	var/on_source_delete = OM_END_UNLINK
	var/on_target_delete = OM_END_UNLINK
	/// effect id -> value (number or FROM_VAR("x") read from the source) held on the target.
	var/list/contributes
	/// effect id -> value (number or FROM_VAR("x") read from the target) held on the source (the occupant).
	var/list/source_contributes
	/// grant kind -> id (or list of ids) held on the target.
	var/list/grants_target
	/// grant kind -> id (or list of ids) held on the source (the occupant).
	var/list/grants_occupant
	/// Check spec (actor = source, target = target); contributions apply only while it passes.
	var/active_if
	/// Bundles whose relation fields (contributes, grants_*) are merged in.
	var/list/include

	var/id = 0
	var/datum/om/check/compiled_active_if

/// Hooks get both ends, never null: an end being deleted is QDELETED but not null.
/datum/om/relation/proc/on_link(datum/source, datum/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/om/relation/proc/on_unlink(datum/source, datum/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// One edge, held by both ends' recs.
/datum/om/edge
	var/datum/om/relation/rel
	var/datum/source
	var/datum/target
	/// Aggregate contributions cached on the edge: stride 2 (derived idx, value).
	var/list/cache
	/// Contributions currently applied (active_if passed).
	var/active = FALSE

// ===================================================================== checks

/datum/om/check
	abstract_type = /datum/om/check
	/// Channels whose change can flip the answer (on the actor unless noted).
	var/depends_on = 0
	/// Parameter (resolved against the actor if it is FROM_VAR(...)).
	var/arg
	/// Cache key (set by om_check_get()).
	var/key

/// Returns null when the check passes, else a short reason.
/datum/om/check/proc/why_not(datum/actor, datum/target)
	SHOULD_NOT_SLEEP(TRUE)
	return null

// ===================================================================== derived

/datum/om/derived
	abstract_type = /datum/om/derived
	/// Name used by om_derived(E, name); defaults to the type path.
	var/name
	/// Channels on the entity that make the value dirty.
	var/inputs = 0
	/// Other derived names used as inputs (ordered before this one).
	var/list/derived_inputs
	/// relation type (or path list) -> mask on related entities.
	var/list/related_inputs
	/// Output channel raised when the value changes (0: lazy only, no channel).
	var/channel = 0
	/// Deciseconds: recompute on read if older (engine-owned inputs).
	var/max_age = 0
	/// AGG_* over `over`.
	var/aggregate = AGG_NONE
	/// Relation type (members are the sources of edges whose target is the entity), or OVER_SLOT(id).
	var/over
	/// FROM_VAR/FROM_DERIVED/FROM_EFFECT reader for a member's contribution.
	var/reader
	/// Channels on members that change their contribution.
	var/member_inputs = 0
	/// Check spec for DERIVE() rows.
	var/expr

	var/idx = 0
	var/order = 0
	var/over_rel_id = 0
	var/over_slot
	var/datum/om/check/compiled_expr
	/// list of list(list(relation ids path), mask)
	var/list/compiled_related

/// Plain derived values compute from the entity.
/datum/om/derived/proc/compute(datum/E)
	SHOULD_NOT_SLEEP(TRUE)
	if(compiled_expr)
		return isnull(compiled_expr.why_not(E, null))
	return null

/// Aggregate member contribution.
/datum/om/derived/proc/contribution(datum/member)
	SHOULD_NOT_SLEEP(TRUE)
	return om_read(member, reader)

/// AGG_CUSTOM hooks: return the new aggregate value.
/datum/om/derived/proc/on_member_added(datum/E, datum/member, old_value, contribution)
	return old_value

/datum/om/derived/proc/on_member_removed(datum/E, datum/member, old_value, contribution)
	return old_value

/datum/om/derived/proc/on_member_changed(datum/E, datum/member, old_value, old_contribution, new_contribution)
	return old_value

// ===================================================================== effects and clocks

/// One generic effect type configured by a table row; subclass only for custom logic.
/datum/om/effect
	abstract_type = /datum/om/effect
	var/id
	var/idx = 0
	var/combine = COMBINE_ANY
	var/stacking = STACKING_REPLACE
	var/channel = 0
	/// Value when nothing contributes.
	var/default_value
	/// Composite: an expression over other effect ids (ALL_OF/ANY_OF/NOT_OF/SUM_OF). No contributions of its own.
	var/list/expr
	var/kind = OM_EFFECT_PLAIN
	var/clock_idx = 0
	/// Composite effects that read this one (idx list).
	var/list/dependents

/// Called after the value on `E` changed. Subclasses add custom logic.
/datum/om/effect/proc/on_changed(datum/E, old_value, new_value)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/om/clock_def
	abstract_type = /datum/om/clock_def
	var/id
	var/idx = 0
	var/min_rate = 0
	var/max_rate = 10
	var/datum/om/effect/mult
	var/datum/om/effect/inhibit

// ===================================================================== services

/// Global observers: wake_on_any = list(type = mask). on_changes(E, bits)
/// runs once per tick per entity with the union of bits.
/datum/om/service
	abstract_type = /datum/om/service
	var/list/wake_on_any
	var/id = 0

/datum/om/service/proc/on_changes(datum/E, bits)
	SHOULD_NOT_SLEEP(TRUE)
	return
