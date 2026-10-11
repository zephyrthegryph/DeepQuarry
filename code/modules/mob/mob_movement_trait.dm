// How a mob moves and is moved: the mob_movement() type trait (doc/rewrite/proposals/base_vars.md). Bump, swap and push flags, dirt,
// climbing and pulling are per-type data in CAPABILITIES (configure(mob_movement(bump = HUMAN))), read with movement_of(M).bump;
// set_<old var>() writes the mob's own copy.

STATIC_ENTRY(mob_movement)

/proc/mob_movement(bump = null, swap = null, push = null, always_swap = null, makes_dirt = null, can_climb = null, pull_size = null, pull_mobs = null, no_pull_when_living = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MOB_MOVEMENT, null, list("bump" = bump, "swap" = swap, "push" = push, "always_swap" = always_swap, "makes_dirt" = makes_dirt, "can_climb" = can_climb, "pull_size" = pull_size, "pull_mobs" = pull_mobs, "no_pull_when_living" = no_pull_when_living))

/datum/type_trait/mob_movement
	var/bump = 0	// what this mob counts as when bumping (HUMAN, MONKEY, ...)
	var/swap = 0	// the bump flags it swaps places with
	var/push = 0	// the bump flags it pushes
	var/always_swap = 0	// swaps with anything
	var/makes_dirt = TRUE	// leaves dirt on the floor as it walks
	var/can_climb = FALSE	// climbs walls with climb_wall()
	var/pull_size = ITEMSIZE_NO_CONTAINER	// the largest w_class it can pull
	var/pull_mobs = MOB_PULL_LARGER	// which mobs it can pull
	var/no_pull_when_living = FALSE	// can be pulled only when dead

/datum/type_trait/mob_movement/copy_values(datum/type_trait/mob_movement/into)
	into.bump = bump
	into.swap = swap
	into.push = push
	into.always_swap = always_swap
	into.makes_dirt = makes_dirt
	into.can_climb = can_climb
	into.pull_size = pull_size
	into.pull_mobs = pull_mobs
	into.no_pull_when_living = no_pull_when_living

/datum/entry_engine/type_trait/mob_movement
	kind = ENTRY_MOB_MOVEMENT
	trait_type = /datum/type_trait/mob_movement
	publish_key = MOB_MOVEMENT_KEY
	base_type = /mob
	var_names = list("mob_bump_flag" = "bump", "mob_swap_flags" = "swap", "mob_push_flags" = "push", "mob_always_swap" = "always_swap", "makes_dirt" = "makes_dirt", "can_climb" = "can_climb", "can_pull_size" = "pull_size", "can_pull_mobs" = "pull_mobs", "no_pull_when_living" = "no_pull_when_living")

/// The holder's mob_movement values (its own once one was set at run time). Read only.
READS_AS(/proc/movement_of, MOB_MOVEMENT_KEY)
/proc/movement_of(mob/holder) as /datum/type_trait/mob_movement
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MOB_MOVEMENT)

/// What a type declares (no instance): the old initial().
/proc/movement_of_type(type) as /datum/type_trait/mob_movement
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_MOB_MOVEMENT)

/mob/proc/set_mob_bump_flag(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "bump", value)

/mob/proc/set_mob_swap_flags(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "swap", value)

/mob/proc/set_mob_push_flags(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "push", value)

/mob/proc/set_mob_always_swap(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "always_swap", value)

/mob/proc/set_makes_dirt(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "makes_dirt", value)

/mob/proc/set_can_climb(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "can_climb", value)

/mob/proc/set_can_pull_size(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "pull_size", value)

/mob/proc/set_can_pull_mobs(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "pull_mobs", value)

/mob/proc/set_no_pull_when_living(value)
	return set_trait(src, ENTRY_MOB_MOVEMENT, "no_pull_when_living", value)
