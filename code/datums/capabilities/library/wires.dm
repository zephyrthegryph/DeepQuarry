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

/// Wires of `wires_type`, reachable while the maintenance panel is open (and whatever `needs` asks). type: a subtype
/// choosing the wires per instance (wires_type_for()).
/proc/cap_wires(wires_type, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, type = /datum/capability/wires)
	var/datum/capability/wires/C = new type
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
		var/wires_type = C.wires_type_for(A)
		if(!wires_type)
			return null
		W = new wires_type(A)
		LAZYSET(A.cap_data, C.key, W)
	return W

/// The /datum/wires subtype this capability makes for holder: the one cap_wires() was given. A per-instance choice
/// (design review H1: an airlock built with secure electronics) is a subtype overriding this.
/datum/capability/wires/proc/wires_type_for(atom/holder)
	return wires_type

/datum/capability/wires/interactions(atom/holder)
	return list(
		adopt_entry(lib_op("Pulse wires", GLOBAL_PROC_REF(cap_wires_open), OP_SHAPE_TOOL, using = TOOL_MULTITOOL, key = "pulse_wires", priority = OP_PRIORITY_PART), id = "wires:multitool"),
		adopt_entry(lib_op("Cut wires", GLOBAL_PROC_REF(cap_wires_open), OP_SHAPE_TOOL, using = TOOL_WIRECUTTER, key = "cut_wires", priority = OP_PRIORITY_PART), id = "wires:wirecutter"),
	)

/datum/capability/wires/draw(atom/holder, datum/look/look)
	draw_layer(look, when = wires_exposed(holder))

/datum/capability/wires/on_holder_destroy(atom/holder)
	var/datum/wires/W = holder.cap_data?[key]
	if(W)
		LAZYREMOVE(holder.cap_data, key)
		qdel(W) // ALLOW(lifecycle): a wires datum is a plain datum held by the capability, not an atom; the lifecycle verbs only take atoms

/proc/cap_wires_open(atom/holder, mob/user, obj/item/held)
	var/datum/wires/W = wires_of(holder)
	W.Interact(user)
	return TRUE
