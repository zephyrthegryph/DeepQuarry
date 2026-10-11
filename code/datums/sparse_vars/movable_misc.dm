// Sparse per-movable state: lazy tmp vars on /atom/movable (an unset var costs an
// instance nothing). Formerly one shared component; accessed only through the helpers below.
// A movable with any of it set refuses serialization (/atom/movable/state_refusal()).
//
// Migrated:
//   belly_cycles      — vore autotransfer counter
//   recursive_listeners — observer recursion list (sparse, only set for atoms with recursive listeners)
//   moved_recently     — movement timestamp (only set for atoms tracked by an electropack)
//   affected_dynamic_lights — light cone list (only set when a light affects this atom)
//   cloaked_selfimage  — antag cloaking self-image (only mobs that ever cloak)
//   cloaked            — antag cloaking flag (set only on cloak/uncloak events)
//   parachute          — multi-Z parachute-deployed flag (rare)
//   parachuting        — multi-Z falling-with-parachute flag (rare)
//   softfall           — per-instance override of the mob_movement() trait's softfall
//   hovering           — per-instance override of the mob_movement() trait's hovering
//
// The per-type defaults of softfall, hovering and parachuting are the mob_movement() trait (configure(mob_movement(...)) on the type).




// The per-instance state is sparse slots (code/engine/declare/sparse_slots.dm): nothing on /atom/movable until a slot is set.
sparse(/atom/movable, belly_cycles, type = num)
sparse(/atom/movable, recursive_listeners, type = list)
sparse(/atom/movable, moved_recently, type = num)
sparse(/atom/movable, dynamic_lights, type = list)
sparse(/atom/movable, cloak_selfimage, type = /image)
sparse(/atom/movable, cloaked, type = bool)
sparse(/atom/movable, parachute, type = bool)
sparse(/atom/movable, parachuting, type = bool)
sparse(/atom/movable, softfall, type = bool)
sparse(/atom/movable, hovering, type = bool)

// Lights affecting this movable, keyed by the light; dropped with the movable (the light side may be dying too).

// ---- Helpers (global procs to avoid /atom/movable proc-table bloat). ----

/proc/dq_get_belly_cycles(atom/movable/am)
	return sparse_get_or(am, belly_cycles, 0)
/proc/dq_set_belly_cycles(atom/movable/am, v)
	sparse_set_or(am, belly_cycles, v, 0)

// recursive_listeners is read+written using LAZY* semantics.
/proc/dq_get_recursive_listeners(atom/movable/am)
	return sparse_get(am, recursive_listeners)
/proc/dq_set_recursive_listeners(atom/movable/am, list/v)
	sparse_set(am, recursive_listeners, v)
/// LAZYOR equivalent.
/proc/dq_recursive_listeners_or(atom/movable/am, item)
	var/list/L = sparse_get(am, recursive_listeners)
	if(!L)
		L = sparse_set(am, recursive_listeners, list())
	L |= item
/// LAZYREMOVE equivalent.
/proc/dq_recursive_listeners_remove(atom/movable/am, item)
	var/list/L = sparse_get(am, recursive_listeners)
	if(!L)
		return
	L -= item
	if(!length(L))
		sparse_set(am, recursive_listeners, null)
/// LAZYLEN equivalent.
/proc/dq_recursive_listeners_len(atom/movable/am)
	return length(sparse_get(am, recursive_listeners))

/proc/dq_get_moved_recently(atom/movable/am)
	return sparse_get_or(am, moved_recently, 0)
/proc/dq_set_moved_recently(atom/movable/am, v)
	sparse_set_or(am, moved_recently, v, 0)

/proc/dq_get_affected_dynamic_lights(atom/movable/am)
	return sparse_get(am, dynamic_lights)
/proc/dq_set_affected_dynamic_lights(atom/movable/am, list/v)
	sparse_set(am, dynamic_lights, v)
/// LAZYSET-equivalent for affected_dynamic_lights (auto-create list if null).
/proc/dq_affected_dynamic_lights_set(atom/movable/am, key, value)
	var/list/L = sparse_get(am, dynamic_lights)
	if(!L)
		L = sparse_set(am, dynamic_lights, list())
	L[key] = value
/// LAZYREMOVE-equivalent.
/proc/dq_affected_dynamic_lights_remove(atom/movable/am, key)
	var/list/L = sparse_get(am, dynamic_lights)
	if(!L)
		return
	L -= key
	if(!length(L))
		sparse_set(am, dynamic_lights, null)

/proc/dq_get_cloaked_selfimage(atom/movable/am)
	return sparse_get(am, cloak_selfimage)
/proc/dq_set_cloaked_selfimage(atom/movable/am, v)
	sparse_set(am, cloak_selfimage, v)

/proc/dq_get_cloaked(atom/movable/am)
	return sparse_get_or(am, cloaked, FALSE)
/proc/dq_set_cloaked(atom/movable/am, v)
	sparse_set_or(am, cloaked, v, FALSE)

/proc/dq_get_parachute(atom/movable/am)
	return sparse_get_or(am, parachute, FALSE)
/proc/dq_set_parachute(atom/movable/am, v)
	sparse_set_or(am, parachute, v, FALSE)

// Per-type-default resolver: walk the type hierarchy once per concrete
// type encountered, cache the result. Per-call type2parent walks are
// otherwise hot — these helpers run on every step / falling / hovering
// check. The cache is sized by concrete-type-count, not per-instance.
/proc/_dq_resolve_typed_default(t, list/by_type, list/resolved_cache, default_value)
	if(!t)
		return default_value
	if(t in resolved_cache)
		return resolved_cache[t]
	var/probe = t
	while(probe)
		if(probe in by_type)
			resolved_cache[t] = by_type[probe]
			return by_type[probe]
		probe = type2parent(probe)
	resolved_cache[t] = default_value
	return default_value


/proc/dq_get_parachuting(atom/movable/am)
	if(sparse_has(am, parachuting))
		return sparse_get(am, parachuting)
	return ismob(am) ? movement_of(am).parachuting : FALSE // the type's mob_movement() trait

/proc/dq_set_parachuting(atom/movable/am, v)
	sparse_set_or(am, parachuting, v, FALSE)

/proc/dq_get_softfall(atom/movable/am)
	if(sparse_has(am, softfall))
		return sparse_get(am, softfall)
	return ismob(am) ? movement_of(am).softfall : FALSE // the type's mob_movement() trait

/proc/dq_set_softfall(atom/movable/am, v)
	if(isnull(v) && !sparse_has(am, softfall))
		return
	sparse_set(am, softfall, v ? TRUE : FALSE)

/proc/dq_get_hovering(atom/movable/am)
	if(sparse_has(am, hovering))
		return sparse_get(am, hovering)
	return ismob(am) ? movement_of(am).hovering : FALSE // the type's mob_movement() trait

/proc/dq_set_hovering(atom/movable/am, v)
	if(isnull(v) && !sparse_has(am, hovering))
		return
	sparse_set(am, hovering, v ? TRUE : FALSE)
/// Clears the per-instance override so the type default (the mob_movement() trait) re-applies.
/proc/dq_clear_hovering(atom/movable/am)
	sparse_set(am, hovering, null)
/proc/dq_clear_softfall(atom/movable/am)
	sparse_set(am, softfall, null)

/// TRUE while any of this movable's sparse runtime state differs from its default.
/proc/dq_movable_state_set(atom/movable/am)
	var/list/S = am.sparse_slots
	if(!S)
		return FALSE
	for(var/key in GLOB.dq_movable_runtime_slots)
		if(!isnull(S[key]))
			return TRUE
	return FALSE

/// The sparse slots above: runtime state a saved movable cannot carry.
GLOBAL_LIST_INIT(dq_movable_runtime_slots, list("belly_cycles", "recursive_listeners", "moved_recently", "dynamic_lights", "cloak_selfimage", "cloaked", "parachute", "parachuting", "softfall", "hovering"))
