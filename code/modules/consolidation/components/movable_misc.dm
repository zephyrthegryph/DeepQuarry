// Sparse vars formerly on /atom/movable, now in a single shared component.
//
// Migrated:
//   belly_cycles      — vore autotransfer counter
//   orbiting, orbit_target — ghost orbiter state
//   recursive_listeners — signal recursion list (sparse, only set for atoms with recursive listeners)
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

/datum/component/movable_state
	dupe_mode = COMPONENT_DUPE_UNIQUE
	var/belly_cycles = 0
	var/datum/component/orbiter/orbiting
	var/atom/orbit_target
	var/list/recursive_listeners
	var/moved_recently = 0
	var/list/affected_dynamic_lights
	var/image/cloaked_selfimage
	var/cloaked = FALSE
	var/parachute = FALSE
	var/parachuting = FALSE
	// softfall and hovering are read-only at runtime (only mob subtypes set type-defaults),
	// so we cache the resolved value from GLOB on first access rather than store per-instance.
	// We DO support runtime override via the helpers, in case any code path sets them.
	var/softfall_set = FALSE
	var/softfall_value = FALSE
	var/hovering_set = FALSE
	var/hovering_value = FALSE

/datum/component/movable_state/Destroy(force)
	orbiting = null
	orbit_target = null
	recursive_listeners = null
	affected_dynamic_lights = null
	cloaked_selfimage = null
	return ..()

// ---- Helpers (global procs to avoid /atom/movable proc-table bloat). ----

/proc/dq_get_belly_cycles(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c) return c.belly_cycles
	return 0
/proc/dq_set_belly_cycles(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.belly_cycles = v

/proc/dq_get_orbit_target(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	return c?.orbit_target
/proc/dq_set_orbit_target(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.orbit_target = v

/proc/dq_get_orbiting(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	return c?.orbiting
/proc/dq_set_orbiting(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.orbiting = v

// recursive_listeners is read+written using LAZY* macros. Helpers below match
// LAZYOR / LAZYREMOVE semantics, auto-creating the component as needed.
/proc/dq_get_recursive_listeners(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	return c?.recursive_listeners
/proc/dq_set_recursive_listeners(atom/movable/am, list/v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.recursive_listeners = v
/// LAZYOR equivalent.
/proc/dq_recursive_listeners_or(atom/movable/am, item)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	if(!c.recursive_listeners)
		c.recursive_listeners = list()
	c.recursive_listeners |= item
/// LAZYREMOVE equivalent.
/proc/dq_recursive_listeners_remove(atom/movable/am, item)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c || !c.recursive_listeners)
		return
	c.recursive_listeners -= item
	if(!length(c.recursive_listeners))
		c.recursive_listeners = null
/// LAZYLEN equivalent.
/proc/dq_recursive_listeners_len(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c || !c.recursive_listeners)
		return 0
	return length(c.recursive_listeners)

/proc/dq_get_moved_recently(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c) return c.moved_recently
	return 0
/proc/dq_set_moved_recently(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.moved_recently = v

/proc/dq_get_affected_dynamic_lights(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	return c?.affected_dynamic_lights
/proc/dq_set_affected_dynamic_lights(atom/movable/am, list/v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.affected_dynamic_lights = v
/// LAZYSET-equivalent for affected_dynamic_lights (auto-create list if null).
/proc/dq_affected_dynamic_lights_set(atom/movable/am, key, value)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	if(!c.affected_dynamic_lights)
		c.affected_dynamic_lights = list()
	c.affected_dynamic_lights[key] = value
/// LAZYREMOVE-equivalent.
/proc/dq_affected_dynamic_lights_remove(atom/movable/am, key)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c || !c.affected_dynamic_lights)
		return
	c.affected_dynamic_lights -= key
	if(!length(c.affected_dynamic_lights))
		c.affected_dynamic_lights = null

/proc/dq_get_cloaked_selfimage(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	return c?.cloaked_selfimage
/proc/dq_set_cloaked_selfimage(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.cloaked_selfimage = v

/proc/dq_get_cloaked(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c) return c.cloaked
	return FALSE
/proc/dq_set_cloaked(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.cloaked = v

/proc/dq_get_parachute(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c) return c.parachute
	return FALSE
/proc/dq_set_parachute(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.parachute = v

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
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c && c.parachuting != FALSE) return c.parachuting
	return _dq_resolve_typed_default(am.type, GLOB.dq_parachuting_by_type, GLOB._dq_parachuting_resolved, FALSE)

/proc/dq_set_parachuting(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.parachuting = v

/proc/dq_get_softfall(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c && c.softfall_set) return c.softfall_value
	return _dq_resolve_typed_default(am.type, GLOB.dq_softfall_by_type, GLOB._dq_softfall_resolved, FALSE)

/proc/dq_set_softfall(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.softfall_set = TRUE
	c.softfall_value = v

/proc/dq_get_hovering(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c && c.hovering_set) return c.hovering_value
	return _dq_resolve_typed_default(am.type, GLOB.dq_hovering_by_type, GLOB._dq_hovering_resolved, FALSE)

/proc/dq_set_hovering(atom/movable/am, v)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(!c) c = am.AddComponent(/datum/component/movable_state)
	c.hovering_set = TRUE
	c.hovering_value = v
/// Clears the per-instance override so the type-default (GLOB lookup) re-applies.
/proc/dq_clear_hovering(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c) c.hovering_set = FALSE
/proc/dq_clear_softfall(atom/movable/am)
	var/datum/component/movable_state/c = am.GetComponent(/datum/component/movable_state)
	if(c) c.softfall_set = FALSE
