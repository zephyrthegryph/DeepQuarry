// rotate(): hand entries that turn the holder. "Rotate clockwise" answers Alternate (alt-click);
// "Rotate counter-clockwise" is in the Menu (or answers Alternate when it is the only one).

/datum/capability/rotate
	layer_name = CAP_NO_LAYER
	var/clockwise = TRUE
	var/counter = TRUE
	/// Refuse while the holder is anchored.
	var/needs_unanchored = TRUE

/proc/cap_rotate(clockwise = TRUE, counter = TRUE, needs_unanchored = TRUE, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, layer = CAP_NO_LAYER)
	var/datum/capability/rotate/C = new
	C.clockwise = clockwise
	C.counter = counter
	C.needs_unanchored = needs_unanchored
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/rotate/interactions(atom/holder)
	. = list()
	var/needs = needs_unanchored ? TYPE_PROC_REF(/atom/movable, cap_rotate_free) : null
	// Alt-click turns it (ACT_TOGGLE, the alternate use); the other way is ACT_NONE when both are offered. Fastened in
	// place it is not what an alt-click means (offered): the alt-click falls through.
	var/datum/req/free = needs ? req_proc(needs) : null
	if(clockwise)
		var/datum/interaction/capability/E = adopt_entry(lib_op("Rotate clockwise", TYPE_PROC_REF(/atom/movable, cap_rotate_clockwise), OP_SHAPE_HAND, key = "rotate_clockwise", action = ACT_TOGGLE, offered = free, works_broken = TRUE, works_unpowered = TRUE))
		E.default_action = INPUT_ACTION_ALTERNATE
		. += E
	if(counter)
		var/datum/interaction/capability/E = adopt_entry(lib_op("Rotate counter-clockwise", TYPE_PROC_REF(/atom/movable, cap_rotate_counter), OP_SHAPE_HAND, key = "rotate_counter", action = clockwise ? ACT_NONE : ACT_TOGGLE, offered = free, works_broken = TRUE, works_unpowered = TRUE))
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
