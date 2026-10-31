// How a movable seats a rider: the buckle_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(buckle_rules(movable = ...))), read with buckle_of(A).movable, written at run time with set_<old var>().
//
//   movable   a rider may move while buckled
//   dir   the direction a rider faces
//   lying   -1 leaves the rider alone, else forces their lying
//   require_restraints   a rider must be handcuffed first
//   max_mobs   how many riders at once

STATIC_ENTRY(buckle_rules)

/proc/buckle_rules(movable = null, dir = null, lying = null, require_restraints = null, max_mobs = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_BUCKLE_RULES, null, list("movable" = movable, "dir" = dir, "lying" = lying, "require_restraints" = require_restraints, "max_mobs" = max_mobs))

/datum/type_trait/buckle_rules
	var/movable = 0
	var/dir = 0
	var/lying = -1
	var/require_restraints = 0
	var/max_mobs = 1

/datum/type_trait/buckle_rules/copy_values(datum/type_trait/buckle_rules/into)
	into.movable = movable
	into.dir = dir
	into.lying = lying
	into.require_restraints = require_restraints
	into.max_mobs = max_mobs

/datum/entry_engine/type_trait/buckle_rules
	kind = ENTRY_BUCKLE_RULES
	trait_type = /datum/type_trait/buckle_rules
	publish_key = BUCKLE_RULES_KEY
	base_type = /atom/movable
	var_names = list("buckle_movable" = "movable", "buckle_dir" = "dir", "buckle_lying" = "lying", "buckle_require_restraints" = "require_restraints", "max_buckled_mobs" = "max_mobs")

/// The holder's buckle_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/buckle_of, BUCKLE_RULES_KEY)
/proc/buckle_of(atom/movable/holder) as /datum/type_trait/buckle_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_BUCKLE_RULES)

/// What a type declares (no instance): the old initial().
/proc/buckle_of_type(type) as /datum/type_trait/buckle_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_BUCKLE_RULES)

/atom/movable/proc/set_buckle_movable(value)
	return set_trait(src, ENTRY_BUCKLE_RULES, "movable", value)

/atom/movable/proc/set_buckle_dir(value)
	return set_trait(src, ENTRY_BUCKLE_RULES, "dir", value)

/atom/movable/proc/set_buckle_lying(value)
	return set_trait(src, ENTRY_BUCKLE_RULES, "lying", value)

/atom/movable/proc/set_buckle_require_restraints(value)
	return set_trait(src, ENTRY_BUCKLE_RULES, "require_restraints", value)

/atom/movable/proc/set_max_buckled_mobs(value)
	return set_trait(src, ENTRY_BUCKLE_RULES, "max_mobs", value)
