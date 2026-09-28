/// Rotation verbs (was /datum/element/rotatable). Stateless: the verbs themselves are
/// the only per-atom state, so this is a plain global proc rather than an OM behaviour (an
/// OM record per rotatable object would cost more than it carries).
/proc/make_rotatable(atom/movable/AM, only_flip = FALSE)
	if(!only_flip)
		AM.verbs |= /atom/movable/proc/rotate_clockwise
		AM.verbs |= /atom/movable/proc/rotate_counterclockwise
	AM.verbs |= /atom/movable/proc/turn_around

/proc/unmake_rotatable(atom/movable/AM)
	AM.verbs -= /atom/movable/proc/rotate_clockwise
	AM.verbs -= /atom/movable/proc/rotate_counterclockwise
	AM.verbs -= /atom/movable/proc/turn_around

// Core rotation proc, override me to add conditions to object rotations or update_icons/state after!
/atom/movable/proc/handle_rotation_verbs(angle, mob/user)
	if(isobserver(user))
		if(!ghosts_can_use_rotate_verbs())
			return FALSE
	else
		if(user.incapacitated())
			return FALSE
		if(HAS_TRAIT(user, TRAIT_AMBIENT_PEST_MOB))
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
	set category = "Object"
	set src in view(1)
	return handle_rotation_verbs(270, usr)

/atom/movable/proc/rotate_counterclockwise()
	SHOULD_NOT_OVERRIDE(TRUE)
	set name = "Rotate Counter Clockwise"
	set category = "Object"
	set src in view(1)
	return handle_rotation_verbs(90, usr)

/atom/movable/proc/turn_around()
	SHOULD_NOT_OVERRIDE(TRUE)
	set name = "Turn Around"
	set category = "Object"
	set src in view(1)
	return handle_rotation_verbs(180, usr)
