// The wires capability (doc/rewrite/dx_conventions.md §2): owns one /datum/wires (the existing wire
// system, code/datums/wires/) per holder, made on first use and kept in the holder's cap_data. A
// multitool or wirecutters on the exposed wires opens the wires window. Layer: LOOK_WIRES while exposed.
// Accessors: wires_exposed(), wires_of().
//
//	. += cap_wires(/datum/wires/apc)			// behind the maintenance panel

/datum/capability/wires
	layer_name = LOOK_WIRES
	// The wires sit behind the maintenance panel (wires_exposed() reads it); `needs` adds more.
	behind = PANEL
	/// The /datum/wires subtype made for each holder.
	var/wires_type

/// Wires of `wires_type`, reachable while the maintenance panel is open (and whatever `needs` asks).
/proc/cap_wires(wires_type, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/wires/C = new
	C.wires_type = wires_type
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

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

/// A machine's wires default to its machine_wires type var (cap_wires() with no type).
/obj/machinery/wires_type_for(default_type)
	return default_type || machine_wires

/datum/capability/wires/interactions(atom/holder)
	return list(
		adopt_entry(cap_tool("Pulse wires", TOOL_MULTITOOL, TYPE_PROC_REF(/atom, cap_wires_open), priority = 10), id = "wires:multitool"),
		adopt_entry(cap_tool("Cut wires", TOOL_WIRECUTTER, TYPE_PROC_REF(/atom, cap_wires_open), priority = 10), id = "wires:wirecutter"),
	)

/datum/capability/wires/draw(atom/holder, datum/look/look)
	draw_layer(look, when = wires_exposed(holder))

/datum/capability/wires/on_holder_destroy(atom/holder)
	var/datum/wires/W = holder.cap_data?[key]
	if(W)
		LAZYREMOVE(holder.cap_data, key)
		qdel(W)

/atom/proc/cap_wires_open(mob/user, obj/item/held)
	var/datum/wires/W = wires_of(src)
	W.Interact(user)
	return TRUE
