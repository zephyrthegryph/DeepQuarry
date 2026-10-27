// How loud a mob walks: the footstep_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(footstep_rules(footstep_volume = ...))), read with footstep_of(A).footstep_volume, written at run time with set_<old var>().
//
//   footstep_volume / footstep_e_range   volume and extra range of its footsteps

STATIC_ENTRY(footstep_rules)

/proc/footstep_rules(footstep_volume = null, footstep_e_range = null, footstep_type = null, custom_footstep = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_FOOTSTEP_RULES, null, list("footstep_volume" = footstep_volume, "footstep_e_range" = footstep_e_range, "footstep_type" = footstep_type, "custom_footstep" = custom_footstep))

/datum/type_trait/footstep_rules
	var/footstep_volume = 0.1
	var/footstep_e_range = -8
	var/footstep_type = FOOTSTEP_MOB_BAREFOOT
	var/custom_footstep = FOOTSTEP_MOB_SHOE

/datum/type_trait/footstep_rules/copy_values(datum/type_trait/footstep_rules/into)
	into.footstep_volume = footstep_volume
	into.footstep_e_range = footstep_e_range
	into.footstep_type = footstep_type
	into.custom_footstep = custom_footstep

/datum/entry_engine/type_trait/footstep_rules
	kind = ENTRY_FOOTSTEP_RULES
	trait_type = /datum/type_trait/footstep_rules
	publish_key = FOOTSTEP_RULES_KEY
	base_type = /mob/living
	var_names = list("footstep_volume" = "footstep_volume", "footstep_e_range" = "footstep_e_range", "footstep_type" = "footstep_type", "custom_footstep" = "custom_footstep")

/// The holder's footstep_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/footstep_of, FOOTSTEP_RULES_KEY)
/proc/footstep_of(mob/living/holder) as /datum/type_trait/footstep_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_FOOTSTEP_RULES)

/// What a type declares (no instance): the old initial().
/proc/footstep_of_type(type) as /datum/type_trait/footstep_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_FOOTSTEP_RULES)

/mob/living/proc/set_footstep_volume(value)
	return set_trait(src, ENTRY_FOOTSTEP_RULES, "footstep_volume", value)

/mob/living/proc/set_footstep_e_range(value)
	return set_trait(src, ENTRY_FOOTSTEP_RULES, "footstep_e_range", value)

/mob/living/proc/set_footstep_type(value)
	return set_trait(src, ENTRY_FOOTSTEP_RULES, "footstep_type", value)

/mob/living/proc/set_custom_footstep(value)
	return set_trait(src, ENTRY_FOOTSTEP_RULES, "custom_footstep", value)
