// How a movable flies and shows: the movable_motion() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(movable_motion(throw_speed = ...))), read with motion_of(A).throw_speed, written at run time with set_<old var>().
//
//   throw_speed / does_spin   how it flies when thrown
//   icon_height   the height its icon is expected to be
//   unacidable   acid cannot eat it
//   cone_x / cone_y   where its light cone sits

STATIC_ENTRY(movable_motion)

/proc/movable_motion(throw_speed = null, icon_height = null, does_spin = null, unacidable = null, cone_x = null, cone_y = null, blocks_emissive = null, throw_range = null, lifecycle_lifetime = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MOVABLE_MOTION, null, list("throw_speed" = throw_speed, "icon_height" = icon_height, "does_spin" = does_spin, "unacidable" = unacidable, "cone_x" = cone_x, "cone_y" = cone_y, "blocks_emissive" = blocks_emissive, "throw_range" = throw_range, "lifecycle_lifetime" = lifecycle_lifetime))

/datum/type_trait/movable_motion
	var/throw_speed = 2
	var/icon_height = 32
	var/does_spin = TRUE
	var/unacidable = TRUE
	var/cone_x = null
	var/cone_y = null
	var/blocks_emissive = EMISSIVE_BLOCK_NONE
	var/throw_range = 7
	var/lifecycle_lifetime = 0

/datum/type_trait/movable_motion/copy_values(datum/type_trait/movable_motion/into)
	into.throw_speed = throw_speed
	into.icon_height = icon_height
	into.does_spin = does_spin
	into.unacidable = unacidable
	into.cone_x = cone_x
	into.cone_y = cone_y
	into.blocks_emissive = blocks_emissive
	into.throw_range = throw_range
	into.lifecycle_lifetime = lifecycle_lifetime

/datum/entry_engine/type_trait/movable_motion
	kind = ENTRY_MOVABLE_MOTION
	trait_type = /datum/type_trait/movable_motion
	publish_key = MOVABLE_MOTION_KEY
	base_type = /atom/movable
	var_names = list("throw_speed" = "throw_speed", "icon_expected_height" = "icon_height", "does_spin" = "does_spin", "unacidable" = "unacidable", "light_cone_x_offset" = "cone_x", "light_cone_y_offset" = "cone_y", "blocks_emissive" = "blocks_emissive", "throw_range" = "throw_range", "lifecycle_lifetime" = "lifecycle_lifetime")

/// The holder's movable_motion values (its own once one was set at run time). Read only.
READS_AS(/proc/motion_of, MOVABLE_MOTION_KEY)
/proc/motion_of(atom/movable/holder) as /datum/type_trait/movable_motion
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MOVABLE_MOTION)

/// What a type declares (no instance): the old initial().
/proc/motion_of_type(type) as /datum/type_trait/movable_motion
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_MOVABLE_MOTION)

/atom/movable/proc/set_throw_speed(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "throw_speed", value)

/atom/movable/proc/set_icon_expected_height(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "icon_height", value)

/atom/movable/proc/set_does_spin(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "does_spin", value)

/atom/movable/proc/set_unacidable(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "unacidable", value)

/atom/movable/proc/set_light_cone_x_offset(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "cone_x", value)

/atom/movable/proc/set_light_cone_y_offset(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "cone_y", value)

/atom/movable/proc/set_blocks_emissive(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "blocks_emissive", value)

/atom/movable/proc/set_throw_range(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "throw_range", value)

/atom/movable/proc/set_lifecycle_lifetime(value)
	return set_trait(src, ENTRY_MOVABLE_MOTION, "lifecycle_lifetime", value)
