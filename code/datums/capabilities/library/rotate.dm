// rotate(): hand entries that turn the holder. "Rotate clockwise" answers Alternate (alt-click);
// "Rotate counter-clockwise" is in the Menu (or answers Alternate when it is the only one).

/datum/capability/rotate
	works_broken = TRUE
	works_unpowered = TRUE
	var/clockwise = TRUE
	var/counter = TRUE
	/// Refuse while the holder is anchored.
	var/needs_unanchored = TRUE

/proc/cap_rotate(clockwise = TRUE, counter = TRUE, needs_unanchored = TRUE, behind = NONE, log)
	var/datum/capability/rotate/C = new
	C.clockwise = clockwise
	C.counter = counter
	C.needs_unanchored = needs_unanchored
	C.behind = behind
	C.log = log
	return C

/datum/capability/rotate/interactions(atom/holder)
	. = list()
	var/needs = needs_unanchored ? TYPE_PROC_REF(/atom/movable, cap_rotate_free) : null
	if(clockwise)
		var/datum/interaction/capability/E = adopt_entry(cap_hand("Rotate clockwise", TYPE_PROC_REF(/atom/movable, cap_rotate_clockwise), behind = behind, needs = needs, works_broken = TRUE, works_unpowered = TRUE, log = log))
		E.default_action = INPUT_ACTION_ALTERNATE
		. += E
	if(counter)
		var/datum/interaction/capability/E = adopt_entry(cap_hand("Rotate counter-clockwise", TYPE_PROC_REF(/atom/movable, cap_rotate_counter), behind = behind, needs = needs, works_broken = TRUE, works_unpowered = TRUE, log = log))
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
