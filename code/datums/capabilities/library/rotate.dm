// rotate(): hand entries that turn the holder. "Rotate clockwise" answers Alternate (alt-click);
// "Rotate counter-clockwise" is in the Menu (or answers Alternate when it is the only one).

/datum/capability/rotate
	layer_name = CAP_NO_LAYER
	var/clockwise = TRUE
	var/counter = TRUE
	/// Refuse while the holder is anchored.
	var/needs_unanchored = TRUE

/proc/cap_rotate(clockwise = TRUE, counter = TRUE, needs_unanchored = TRUE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/rotate/C = new
	C.clockwise = clockwise
	C.counter = counter
	C.needs_unanchored = needs_unanchored
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/rotate/interactions(atom/holder)
	. = list()
	var/needs = needs_unanchored ? TYPE_PROC_REF(/atom/movable, cap_rotate_free) : null
	if(clockwise)
		var/datum/interaction/capability/E = adopt_entry(cap_hand("Rotate clockwise", TYPE_PROC_REF(/atom/movable, cap_rotate_clockwise), needs = needs, works_broken = TRUE, works_unpowered = TRUE))
		E.default_action = INPUT_ACTION_ALTERNATE
		. += E
	if(counter)
		var/datum/interaction/capability/E = adopt_entry(cap_hand("Rotate counter-clockwise", TYPE_PROC_REF(/atom/movable, cap_rotate_counter), needs = needs, works_broken = TRUE, works_unpowered = TRUE))
		E.default_action = clockwise ? null : INPUT_ACTION_ALTERNATE
		. += E

/atom/movable/proc/cap_rotate_free(mob/user, obj/item/held)
	return anchored ? "it's fastened in place" : TRUE

/atom/movable/proc/cap_rotate_clockwise(mob/user, obj/item/held)
	set_dir(turn(dir, -90))
	return TRUE

/atom/movable/proc/cap_rotate_counter(mob/user, obj/item/held)
	set_dir(turn(dir, 90))
	return TRUE
