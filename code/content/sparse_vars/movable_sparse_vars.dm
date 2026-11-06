// Per-movable lazy state (the movable_misc, movement_log, cloak and airborne rows of the storage contract, doc/rewrite/storage_contract.md): nothing on /atom/movable
// until a field is set. Formerly one shared component; accessed only through the helpers below.
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




// Toggle for autotransfer mechanics (default TRUE; the slot is set only when FALSE).

// Lights affecting this movable, keyed by the light; dropped with the movable (the light side may be dying too).

// ---- Helpers (global procs to avoid /atom/movable proc-table bloat). ----

/proc/dq_get_belly_cycles(atom/movable/am)
	return STATE_PEEK(am, movable_misc, belly_cycles)
/proc/dq_set_belly_cycles(atom/movable/am, v)
	STATE_SET(am, movable_misc, belly_cycles, v)

// recursive_listeners is read+written using LAZY* semantics.
/proc/dq_get_recursive_listeners(atom/movable/am)
	return STATE_PEEK(am, movable_misc, recursive_listeners)
/// LAZYOR equivalent.
/proc/dq_recursive_listeners_or(atom/movable/am, item)
	var/list/L = STATE_PEEK(am, movable_misc, recursive_listeners)
	if(!L)
		L = list()
		STATE_SET(am, movable_misc, recursive_listeners, L)
	L |= item
/// LAZYREMOVE equivalent.
/proc/dq_recursive_listeners_remove(atom/movable/am, item)
	var/list/L = STATE_PEEK(am, movable_misc, recursive_listeners)
	if(!L)
		return
	L -= item
	if(!length(L))
		STATE_SET(am, movable_misc, recursive_listeners, null)
/// LAZYLEN equivalent.
/proc/dq_recursive_listeners_len(atom/movable/am)
	return length(STATE_PEEK(am, movable_misc, recursive_listeners))

/proc/dq_get_moved_recently(atom/movable/am)
	return STATE_PEEK(am, movement_log, moved_recently)
/proc/dq_set_moved_recently(atom/movable/am, v)
	STATE_SET(am, movement_log, moved_recently, v)

/proc/dq_get_affected_dynamic_lights(atom/movable/am)
	return STATE_PEEK(am, movable_misc, dynamic_lights)
/// LAZYSET-equivalent for affected_dynamic_lights (auto-create list if null).
/proc/dq_affected_dynamic_lights_set(atom/movable/am, key, value)
	var/list/L = STATE_PEEK(am, movable_misc, dynamic_lights)
	if(!L)
		L = list()
		STATE_SET(am, movable_misc, dynamic_lights, L)
	L[key] = value
/// LAZYREMOVE-equivalent.
/proc/dq_affected_dynamic_lights_remove(atom/movable/am, key)
	var/list/L = STATE_PEEK(am, movable_misc, dynamic_lights)
	if(!L)
		return
	L -= key
	if(!length(L))
		STATE_SET(am, movable_misc, dynamic_lights, null)

/proc/dq_get_cloaked_selfimage(atom/movable/am)
	return STATE_PEEK(am, cloak, cloak_selfimage)
/proc/dq_set_cloaked_selfimage(atom/movable/am, v)
	STATE_SET(am, cloak, cloak_selfimage, v)

/proc/dq_get_cloaked(atom/movable/am)
	return STATE_PEEK(am, cloak, cloaked)
/proc/dq_set_cloaked(atom/movable/am, v)
	STATE_SET(am, cloak, cloaked, v)

/proc/dq_get_parachute(atom/movable/am)
	return STATE_PEEK(am, airborne, parachute)
/proc/dq_set_parachute(atom/movable/am, v)
	STATE_SET(am, airborne, parachute, v)

// Per-type-default resolver: walk the type hierarchy once per concrete
// type encountered, cache the result. Per-call type2parent walks are
// otherwise hot — these helpers run on every step / falling / hovering
// check. The cache is sized by concrete-type-count, not per-instance.
/proc/_dq_resolve_typed_default(t, list/by_type, list/resolved_cache, default_value)
	READS_FROM()
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
	if((!isnull(STATE_PEEK(am, airborne, parachuting))))
		return STATE_PEEK(am, airborne, parachuting)
	return ismob(am) ? movement_of(am).parachuting : FALSE // the type's mob_movement() trait

/proc/dq_get_softfall(atom/movable/am)
	if((!isnull(STATE_PEEK(am, airborne, softfall))))
		return STATE_PEEK(am, airborne, softfall)
	return ismob(am) ? movement_of(am).softfall : FALSE // the type's mob_movement() trait

/proc/dq_get_hovering(atom/movable/am)
	if((!isnull(STATE_PEEK(am, airborne, hovering))))
		return STATE_PEEK(am, airborne, hovering)
	return ismob(am) ? movement_of(am).hovering : FALSE // the type's mob_movement() trait

/proc/dq_set_hovering(atom/movable/am, v)
	if(isnull(v) && !(!isnull(STATE_PEEK(am, airborne, hovering))))
		return
	STATE_SET(am, airborne, hovering, v ? TRUE : FALSE)
/// Clears the per-instance override so the type default (the mob_movement() trait) re-applies.
/proc/dq_clear_hovering(atom/movable/am)
	STATE_SET(am, airborne, hovering, null)
/// TRUE while any of this movable's lazy runtime state differs from its default.
/proc/dq_movable_state_set(atom/movable/am)
	for(var/feature in GLOB.dq_movable_runtime_fields)
		var/datum/lazy_state/S = lazy_state_peek(am, feature)
		if(!S)
			continue
		for(var/field in GLOB.dq_movable_runtime_fields[feature])
			var/value = S.vars[field]
			var/default = initial(S.vars[field])
			if(value != default || isnull(value) != isnull(default))
				return TRUE
	return FALSE

/// The lazy fields above: runtime state a saved movable cannot carry (feature -> its fields).
GLOBAL_LIST_INIT(dq_movable_runtime_fields, list(
	"movable_misc" = list("belly_cycles", "recursive_listeners", "dynamic_lights"),
	"movement_log" = list("moved_recently"),
	"cloak" = list("cloak_selfimage", "cloaked"),
	"airborne" = list("parachute", "parachuting", "softfall", "hovering"),
))

// /atom/movable


// base_vars wave 3
