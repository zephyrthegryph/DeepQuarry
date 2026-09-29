// The wires capability (doc/rewrite/dx_conventions.md §2): owns one /datum/wires (the existing wire
// system, code/datums/wires/) per holder, made on first use and kept in the holder's cap_data. A
// multitool or wirecutters on the exposed wires opens the wires window. Layer: "wires" while exposed.
// Accessors: wires_exposed(), wires_of().
//
//	. += wires(/datum/wires/apc, behind = PANEL)

/datum/capability/wires
	/// The /datum/wires subtype made for each holder.
	var/wires_type

/// Wires of `wires_type`, reachable while everything in `behind` is open.
/proc/wires(wires_type, behind = PANEL, log)
	var/datum/capability/wires/C = new
	C.wires_type = wires_type
	C.behind = behind
	C.log = log
	return C

/// A's wires datum (made on first use), or null when A has no wires capability.
/proc/wires_of(atom/A)
	RETURN_TYPE(/datum/wires)
	var/datum/capability/wires/C = cap_of(A, /datum/capability/wires)
	if(!C)
		return null
	var/datum/wires/W = A.cap_data?[C.key]
	if(!W)
		var/wires_type = A.wires_type_for(C.wires_type)
		W = new wires_type(A)
		LAZYSET(A.cap_data, C.key, W)
	return W

/// The /datum/wires subtype A's wires capability makes for A: the capability's type default, or a
/// per-instance choice (design review H1: an airlock built with secure electronics).
/atom/proc/wires_type_for(default_type)
	return default_type

/datum/capability/wires/interactions(atom/holder)
	return list(
		own_entry(tool("Pulse wires", TOOL_MULTITOOL, TYPE_PROC_REF(/atom, cap_wires_open), behind = behind, log = log, priority = 10), id = "wires:multitool"),
		own_entry(tool("Cut wires", TOOL_WIRECUTTER, TYPE_PROC_REF(/atom, cap_wires_open), behind = behind, log = log, priority = 10), id = "wires:wirecutter"),
	)

/datum/capability/wires/draw(atom/holder, datum/look/look)
	look.overlay("wires", when = wires_exposed(holder))

/datum/capability/wires/on_holder_destroy(atom/holder)
	var/datum/wires/W = holder.cap_data?[key]
	if(W)
		LAZYREMOVE(holder.cap_data, key)
		qdel(W)

/atom/proc/cap_wires_open(mob/user, obj/item/held)
	var/datum/wires/W = wires_of(src)
	W.Interact(user)
	return TRUE
