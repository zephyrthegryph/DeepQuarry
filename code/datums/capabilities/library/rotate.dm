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
	var/needs = needs_unanchored ? GLOBAL_PROC_REF(cap_rotate_free) : null
	if(clockwise)
		var/datum/interaction/capability/E = adopt_entry(cap_hand("Rotate clockwise", GLOBAL_PROC_REF(cap_rotate_clockwise), needs = needs, works_broken = TRUE, works_unpowered = TRUE))
		E.default_action = INPUT_ACTION_ALTERNATE
		. += E
	if(counter)
		var/datum/interaction/capability/E = adopt_entry(cap_hand("Rotate counter-clockwise", GLOBAL_PROC_REF(cap_rotate_counter), needs = needs, works_broken = TRUE, works_unpowered = TRUE))
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
