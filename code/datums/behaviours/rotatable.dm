/// Rotation verbs (was /datum/element/rotatable). The atom grants the verbs to itself.
/atom/movable/proc/make_rotatable(only_flip = FALSE)
	if(!only_flip)
		grant(src, granted_verb(/atom/movable/proc/rotate_clockwise), src)
		grant(src, granted_verb(/atom/movable/proc/rotate_counterclockwise), src)
	grant(src, granted_verb(/atom/movable/proc/turn_around), src)

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
