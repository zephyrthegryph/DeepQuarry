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
	var/needs = needs_unanchored ? GLOBAL_PROC_REF(cap_rotate_free) : null
	// Alt-click turns it (ACT_TOGGLE, the alternate use); the other way is ACT_NONE when both are offered. Fastened in
	// place it is not what an alt-click means (offered): the alt-click falls through.
	var/datum/req/free = needs ? req_proc(needs) : null
	if(clockwise)
		var/datum/interaction/capability/E = adopt_entry(lib_op("Rotate clockwise", GLOBAL_PROC_REF(cap_rotate_clockwise), OP_SHAPE_HAND, key = "rotate_clockwise", action = ACT_TOGGLE, offered = free, works_broken = TRUE, works_unpowered = TRUE))
		E.default_action = INPUT_ACTION_ALTERNATE
		. += E
	if(counter)
		var/datum/interaction/capability/E = adopt_entry(lib_op("Rotate counter-clockwise", GLOBAL_PROC_REF(cap_rotate_counter), OP_SHAPE_HAND, key = "rotate_counter", action = clockwise ? ACT_NONE : ACT_TOGGLE, offered = free, works_broken = TRUE, works_unpowered = TRUE))
		E.default_action = clockwise ? null : INPUT_ACTION_ALTERNATE
		. += E

/proc/cap_rotate_free(mob/user, atom/movable/holder, obj/item/held)
	return holder.anchored ? "it's fastened in place" : TRUE

/proc/cap_rotate_clockwise(atom/movable/holder, mob/user, obj/item/held)
	holder.set_dir(turn(holder.dir, -90))
	return TRUE

/proc/cap_rotate_counter(atom/movable/holder, mob/user, obj/item/held)
	holder.set_dir(turn(holder.dir, 90))
	return TRUE
