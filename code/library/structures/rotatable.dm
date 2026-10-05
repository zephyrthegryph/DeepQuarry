// rotatable(only_flip =, while_anchored =): the holder can be turned in place (doc/rewrite/final_api.html, section 11 "The library": rotate()).
//
// Ops in the holder's menu: rotatable.clockwise, rotatable.counterclockwise and rotatable.turn_around (only_flip = TRUE: the last alone). A
// fastened holder does not turn unless while_anchored. Someone who cannot act cannot turn it (the actor gate), and a type that turns only
// sometimes says so with a condition on the capability: extend(CAP_ROTATABLE, when(nameof(can_rotate))). It replaces the rotation verbs a
// type granted itself with make_rotatable() (code/datums/behaviours/rotatable.dm), which the types not converted yet still use.

MSG_DEF_SELF(rotatable/fastened, "It is fastened to the floor!")

CAPABILITY_TYPE(rotatable, CAP_ROTATABLE, /datum/capability/lib/rotatable, key = NONE, only_flip = FALSE, while_anchored = FALSE)

/datum/capability/lib/rotatable

/datum/capability/lib/rotatable/entries()
	var/list/free = while_anchored ? null : needs(req_is(nameof(/atom/movable::anchored), FALSE, because = MSG(rotatable/fastened)))
	. = list(op("turn_around", menu(), label("Turn Around"), free, then(CAP_PROC(turned_around))))
	if(!only_flip)
		. += op("clockwise", menu(), label("Rotate Clockwise"), free, then(CAP_PROC(turned_clockwise)))
		. += op("counterclockwise", menu(), label("Rotate Counter Clockwise"), free, then(CAP_PROC(turned_counterclockwise)))

/datum/capability/lib/rotatable/proc/turned_clockwise(datum/act/op/A)
	return turned_by(A, 270)

/datum/capability/lib/rotatable/proc/turned_counterclockwise(datum/act/op/A)
	return turned_by(A, 90)

/datum/capability/lib/rotatable/proc/turned_around(datum/act/op/A)
	return turned_by(A, 180)

/// The holder turns by `angle` and the actor is told which way it faces now.
/datum/capability/lib/rotatable/proc/turned_by(datum/act/op/A, angle)
	var/atom/movable/holder = A.holder
	holder.set_dir(turn(holder.dir, angle))
	if(A.actor)
		to_chat(A.actor, span_notice("You rotate \the [holder] to face [dir2text(holder.dir)]!"))
	return OP_OK
