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
//   softfall           — type-default for mobs that survive falls (6 mob types; see GLOB lookup)
//   hovering           — type-default for hovering mobs (~25 mob types; GLOB lookup)
//
// For softfall and hovering, type-defaults are kept in GLOBs so removing the
// var from /atom/movable doesn't lose per-type behavior.

GLOBAL_LIST_INIT(dq_softfall_by_type, list(
	/mob/living/simple_mob/humanoid/astral_collective = TRUE,
	/mob/living/simple_mob/vore/squirrel = TRUE,
	/mob/living/simple_mob/animal/passive/bird = TRUE,
	/mob/living/simple_mob/construct = TRUE,
	/mob/living/silicon/pai = TRUE,
	/mob/living/silicon/robot/drone/swarm = TRUE,
))

GLOBAL_LIST_INIT(dq_hovering_by_type, list(
	/mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege = TRUE,
	/mob/living/simple_mob/animal/tyr/rainbow_fly = TRUE,
	/mob/living/simple_mob/vore/spacecritter = TRUE,
	/mob/living/simple_mob/vore/spacecritter/solarray/galaxyray = TRUE,
	/mob/living/simple_mob/vore/smokestar = TRUE,
	/mob/living/simple_mob/blob/spore = TRUE,
	/mob/living/simple_mob/mechanical/cyber_horror = TRUE,
	/mob/living/simple_mob/mechanical/cyber_horror/ling_cyber_horror = TRUE,
	/mob/living/simple_mob/mechanical/viscerator = TRUE,
	/mob/living/simple_mob/mechanical/corrupt_maint_drone = FALSE,
	/mob/living/simple_mob/mechanical/mining_drone = TRUE,
	/mob/living/simple_mob/mechanical/combat_drone = TRUE,
	/mob/living/simple_mob/mechanical/mecha/hoverpod = TRUE,
	/mob/living/simple_mob/mechanical/ward = TRUE,
	/mob/living/simple_mob/animal/space/gnat = TRUE,
	/mob/living/simple_mob/animal/space/shark = TRUE,
	/mob/living/simple_mob/animal/space/ray = TRUE,
	/mob/living/simple_mob/animal/space/carp = TRUE,
	/mob/living/simple_mob/animal/space/space_worm/head = TRUE,
	/mob/living/simple_mob/animal/passive/bird = TRUE,
	/mob/living/simple_mob/animal/sif/tymisian = TRUE,
	/mob/living/simple_mob/animal/sif/glitterfly = TRUE,
	/mob/living/simple_mob/vore/alienanimals/space_ghost = TRUE,
	/mob/living/simple_mob/vore/alienanimals/spooky_ghost = TRUE,
	/mob/living/simple_mob/vore/alienanimals/space_jellyfish = TRUE,
	/mob/living/simple_mob/construct = TRUE,
))

GLOBAL_LIST_INIT(dq_parachuting_by_type, list(
	/mob/living/simple_mob/animal/passive/bird = TRUE,
	/mob/living/simple_mob/construct = TRUE,
))

/atom/movable
	var/tmp/belly_cycle_count = 0
	var/tmp/list/recursive_listener_list
	var/tmp/moved_recently_at = 0
	var/tmp/list/dynamic_lights_affecting
	var/tmp/image/cloak_selfimage
	var/tmp/cloak_active = FALSE
	var/tmp/parachute_deployed = FALSE
	/// Per-instance parachuting flag; FALSE/null falls back to the type default.
	var/tmp/parachuting_override = FALSE
	// softfall and hovering are read-only at runtime (only mob subtypes set type-defaults);
	// the resolved value comes from the GLOB lookup unless a per-instance override is set.
	var/tmp/softfall_is_set = FALSE
	var/tmp/softfall_value = FALSE
	var/tmp/hovering_is_set = FALSE
	var/tmp/hovering_value = FALSE

DECLARE_REF(/atom/movable, "cloak_selfimage", OWNED, null)
// Lights affecting this movable, keyed by the light; dropped with the movable (the light side may be dying too).
DECLARE_REF(/atom/movable, "dynamic_lights_affecting", BACK, null)

// ---- Helpers (global procs to avoid /atom/movable proc-table bloat). ----

/proc/dq_get_belly_cycles(atom/movable/am)
	return am.belly_cycle_count
/proc/dq_set_belly_cycles(atom/movable/am, v)
	if(isnull(v) && !am.belly_cycle_count)
		return
	am.belly_cycle_count = v

// recursive_listeners is read+written using LAZY* semantics.
/proc/dq_get_recursive_listeners(atom/movable/am)
	return am.recursive_listener_list
/proc/dq_set_recursive_listeners(atom/movable/am, list/v)
	am.recursive_listener_list = v
/// LAZYOR equivalent.
/proc/dq_recursive_listeners_or(atom/movable/am, item)
	if(!am.recursive_listener_list)
		am.recursive_listener_list = list()
	am.recursive_listener_list |= item
/// LAZYREMOVE equivalent.
/proc/dq_recursive_listeners_remove(atom/movable/am, item)
	if(!am.recursive_listener_list)
		return
	am.recursive_listener_list -= item
	if(!length(am.recursive_listener_list))
		am.recursive_listener_list = null
/// LAZYLEN equivalent.
/proc/dq_recursive_listeners_len(atom/movable/am)
	return length(am.recursive_listener_list)

/proc/dq_get_moved_recently(atom/movable/am)
	return am.moved_recently_at
/proc/dq_set_moved_recently(atom/movable/am, v)
	if(isnull(v) && !am.moved_recently_at)
		return
	am.moved_recently_at = v

/proc/dq_get_affected_dynamic_lights(atom/movable/am)
	return am.dynamic_lights_affecting
/proc/dq_set_affected_dynamic_lights(atom/movable/am, list/v)
	am.dynamic_lights_affecting = v
/// LAZYSET-equivalent for affected_dynamic_lights (auto-create list if null).
/proc/dq_affected_dynamic_lights_set(atom/movable/am, key, value)
	if(!am.dynamic_lights_affecting)
		am.dynamic_lights_affecting = list()
	am.dynamic_lights_affecting[key] = value
/// LAZYREMOVE-equivalent.
/proc/dq_affected_dynamic_lights_remove(atom/movable/am, key)
	if(!am.dynamic_lights_affecting)
		return
	am.dynamic_lights_affecting -= key
	if(!length(am.dynamic_lights_affecting))
		am.dynamic_lights_affecting = null

/proc/dq_get_cloaked_selfimage(atom/movable/am)
	return am.cloak_selfimage
/proc/dq_set_cloaked_selfimage(atom/movable/am, v)
	am.cloak_selfimage = v

/proc/dq_get_cloaked(atom/movable/am)
	return am.cloak_active
/proc/dq_set_cloaked(atom/movable/am, v)
	if(isnull(v) && !am.cloak_active)
		return
	am.cloak_active = v

/proc/dq_get_parachute(atom/movable/am)
	return am.parachute_deployed
/proc/dq_set_parachute(atom/movable/am, v)
	if(isnull(v) && !am.parachute_deployed)
		return
	am.parachute_deployed = v

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

GLOBAL_LIST_EMPTY(_dq_parachuting_resolved)
GLOBAL_LIST_EMPTY(_dq_softfall_resolved)
GLOBAL_LIST_EMPTY(_dq_hovering_resolved)

/proc/dq_get_parachuting(atom/movable/am)
	if(am.parachuting_override != FALSE)
		return am.parachuting_override
	return _dq_resolve_typed_default(am.type, GLOB.dq_parachuting_by_type, GLOB._dq_parachuting_resolved, FALSE)

/proc/dq_set_parachuting(atom/movable/am, v)
	if(isnull(v) && !am.parachuting_override)
		return
	am.parachuting_override = v

/proc/dq_get_softfall(atom/movable/am)
	if(am.softfall_is_set)
		return am.softfall_value
	return _dq_resolve_typed_default(am.type, GLOB.dq_softfall_by_type, GLOB._dq_softfall_resolved, FALSE)

/proc/dq_set_softfall(atom/movable/am, v)
	if(isnull(v) && !am.softfall_is_set)
		return
	am.softfall_is_set = TRUE
	am.softfall_value = v

/proc/dq_get_hovering(atom/movable/am)
	if(am.hovering_is_set)
		return am.hovering_value
	return _dq_resolve_typed_default(am.type, GLOB.dq_hovering_by_type, GLOB._dq_hovering_resolved, FALSE)

/proc/dq_set_hovering(atom/movable/am, v)
	if(isnull(v) && !am.hovering_is_set)
		return
	am.hovering_is_set = TRUE
	am.hovering_value = v
/// Clears the per-instance override so the type-default (GLOB lookup) re-applies.
/proc/dq_clear_hovering(atom/movable/am)
	am.hovering_is_set = FALSE
/proc/dq_clear_softfall(atom/movable/am)
	am.softfall_is_set = FALSE

/// TRUE while any of this movable's sparse runtime state differs from its default.
/proc/dq_movable_state_set(atom/movable/am)
	return am.belly_cycle_count || am.recursive_listener_list || am.moved_recently_at || am.dynamic_lights_affecting 		|| am.cloak_selfimage || am.cloak_active || am.parachute_deployed || am.parachuting_override 		|| am.softfall_is_set || am.hovering_is_set
