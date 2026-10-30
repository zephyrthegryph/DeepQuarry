/// Rotation verbs (was /datum/element/rotatable). The atom grants the verbs to itself.
/atom/movable/proc/make_rotatable(only_flip = FALSE)
	var/list/rotate_caps = rotate_verb_defs()
	if(!only_flip)
		grant(src, rotate_caps[1], src)
		grant(src, rotate_caps[2], src)
	grant(src, rotate_caps[3], src)

/// The three rotation verb grants (clockwise, counterclockwise, turn around), built once: a constructor call builds and interns a
/// definition, which a per-instance grant at map load paid for every window.
/proc/rotate_verb_defs()
	if(!length(GLOB.rotate_verb_defs))
		GLOB.rotate_verb_defs = list(granted_verb(/atom/movable/proc/rotate_clockwise), granted_verb(/atom/movable/proc/rotate_counterclockwise), granted_verb(/atom/movable/proc/turn_around))
	return GLOB.rotate_verb_defs

/// Filled by the first rotate_verb_defs() call: the capability tables are not up when the globals are made.
GLOBAL_LIST_EMPTY(rotate_verb_defs)

/atom/movable/proc/unmake_rotatable()
	revoke(src, /atom/movable/proc/rotate_clockwise, src)
	revoke(src, /atom/movable/proc/rotate_counterclockwise, src)
	revoke(src, /atom/movable/proc/turn_around, src)

// Core rotation proc, override me to add conditions to object rotations or update_icons/state after!
/atom/movable/proc/handle_rotation_verbs(angle, mob/user)
	if(isobserver(user))
		if(!ghosts_can_use_rotate_verbs())
			return FALSE
	else
		if(user.incapacitated())
			return FALSE
		if(has_trait(user, TRAIT_AMBIENT_PEST_MOB))
			to_chat(user, span_notice("You are too tiny to do that!"))
			return FALSE

	if(anchored && !can_use_rotate_verbs_while_anchored())
		to_chat(user, span_notice("It is fastened to the floor!"))
		return FALSE

	set_dir(turn(dir, angle))
	to_chat(user, span_notice("You rotate \the [src] to face [dir2text(dir)]!"))
	return TRUE

// Overrides for customization
/atom/movable/proc/ghosts_can_use_rotate_verbs()
	return FALSE

/atom/movable/proc/can_use_rotate_verbs_while_anchored()
	return FALSE

// Helper VERBS
/atom/movable/proc/rotate_clockwise()
	SHOULD_NOT_OVERRIDE(TRUE)
	set name = "Rotate Clockwise"
	set category = VERB_CAT_OBJECT
	set src in view(1)
	return handle_rotation_verbs(270, usr)

/atom/movable/proc/rotate_counterclockwise()
	SHOULD_NOT_OVERRIDE(TRUE)
	set name = "Rotate Counter Clockwise"
	set category = VERB_CAT_OBJECT
	set src in view(1)
	return handle_rotation_verbs(90, usr)

/atom/movable/proc/turn_around()
	SHOULD_NOT_OVERRIDE(TRUE)
	set name = "Turn Around"
	set category = VERB_CAT_OBJECT
	set src in view(1)
	return handle_rotation_verbs(180, usr)
