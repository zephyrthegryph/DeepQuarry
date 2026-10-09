// ---- fixing a window to its place and taking it apart, declared ----
//
// A window is loose or screwed to the floor (`anchored`); a reinforced window also sits out of its frame (`state` 0), pried into it (1) or
// fastened to it (2). The window's own vars hold the state, and the steps are ops that read them: window_construction() is listed in the window's
// CAPABILITIES block (window.dm). A loose window, plain or reinforced and out of its frame, is taken apart with a wrench. Welding cracks out is a
// repair op of the window, not a step.

MSG_DEF_SELF(window/dismantle_refused, "You're not sure how to dismantle it properly.")

/// The ops that fix a window to the floor, into its frame, and take it apart.
/proc/window_construction()
	return list(
		op("anchor", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/structure/window, can_anchor)), priority(OP_PRIORITY_PART), label("Fasten to or free from the floor"), wait(0), then(TYPE_PROC_REF(/obj/structure/window, anchor_toggled))),
		op("pry_in", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/obj/structure/window, frame_open)), priority(OP_PRIORITY_PART), label("Pry the window into the frame"), wait(0), then(TYPE_PROC_REF(/obj/structure/window, pried_in))),
		op("pry_out", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/obj/structure/window, frame_seated)), priority(OP_PRIORITY_PART - 1), label("Pry the window out of the frame"), wait(0), then(TYPE_PROC_REF(/obj/structure/window, pried_out))),
		op("fasten_frame", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/structure/window, frame_seated)), priority(OP_PRIORITY_PART - 1), label("Fasten the window to the frame"), wait(0), then(TYPE_PROC_REF(/obj/structure/window, frame_fastened))),
		op("unfasten_frame", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/structure/window, frame_fastened_now)), priority(OP_PRIORITY_PART - 2), label("Unfasten the window from the frame"), wait(0), then(TYPE_PROC_REF(/obj/structure/window, frame_unfastened))),
		op("dismantle", tool(TOOL_WRENCH), when(TYPE_PROC_REF(/obj/structure/window, can_take_apart)), needs(req(TYPE_PROC_REF(/obj/structure/window, can_dismantle), because = MSG(window/dismantle_refused))), priority(OP_PRIORITY_PART), label("Dismantle the window"), wait(0), then(TYPE_PROC_REF(/obj/structure/window, taken_apart))))

/// A plain window, or a reinforced one out of its frame: the screws take it to the floor or free it.
/obj/structure/window/proc/can_anchor(datum/act/A)
	return read_once(!reinf || state == 0)

/// A reinforced window out of its frame.
/obj/structure/window/proc/frame_open(datum/act/A)
	return read_once(reinf && state == 0)

/// A reinforced window pried into its frame, not yet fastened.
/obj/structure/window/proc/frame_seated(datum/act/A)
	return read_once(reinf && state == 1)

/// A reinforced window fastened to its frame.
/obj/structure/window/proc/frame_fastened_now(datum/act/A)
	return read_once(reinf && state == 2)

/// Loose (not on the floor), and, if reinforced, out of its frame.
/obj/structure/window/proc/can_take_apart(datum/act/A)
	return read_once(!anchored && (!reinf || state == 0))

/// The window can be taken apart into glass.
/obj/structure/window/proc/can_dismantle(datum/act/A)
	return glasstype ? TRUE : FALSE

/obj/structure/window/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)
	update_nearby_tiles(need_rebuild = TRUE)
	update_nearby_icons()
	update_verbs()
	to_chat(A.actor, span_notice("You have [anchored ? "" : "un"]fastened the [reinf ? "frame" : "window"] [anchored ? "to" : "from"] the floor."))
	return OP_OK

/obj/structure/window/proc/pried_in(datum/act/op/A)
	state = 1
	to_chat(A.actor, span_notice("You have pried the window into the frame."))
	return OP_OK

/obj/structure/window/proc/pried_out(datum/act/op/A)
	state = 0
	to_chat(A.actor, span_notice("You have pried the window out of the frame."))
	return OP_OK

/obj/structure/window/proc/frame_fastened(datum/act/op/A)
	state = 2
	update_nearby_icons()
	to_chat(A.actor, span_notice("You have fastened the window to the frame."))
	return OP_OK

/obj/structure/window/proc/frame_unfastened(datum/act/op/A)
	state = 1
	update_nearby_icons()
	to_chat(A.actor, span_notice("You have unfastened the window from the frame."))
	return OP_OK

/// Take a loose window apart into its glass: one sheet, four for a full tile.
/obj/structure/window/proc/taken_apart(datum/act/op/A)
	visible_message(span_notice("[A.actor] dismantles 	he [src]."))
	var/obj/item/stack/material/mats = new glasstype(loc)
	if(is_fulltile())
		mats.set_amount(4)
	spent(src, A.actor)
	return OP_OK

// ---- Repair ----

MSG_DEF_SELF(interaction/window_repair, "You repair %T%.")
MSG_DEF_SELF(window/undamaged, "It is already in good condition.")

MSG_DEF_SELF(start/interaction/window_repair, "You begin repairing %T%...")

/// Requirement for weld repair: the window is damaged.
/obj/structure/window/proc/is_damaged(datum/act/op/A)
	return get_integrity_damage() > 0

/obj/structure/window/proc/weld_repair(datum/act/op/A)
	repair_damage(max_integrity)
	update_icon()
	return OP_OK
