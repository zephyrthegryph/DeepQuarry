// ---- taking a girder apart, declared ----
//
// A girder is displaced (not anchored), anchored, or anchored with its support struts loose (`state` 1) or secured (2). The girder's own vars hold
// the state, and the steps are ops that read them: girder_construction() is listed in the girder's CAPABILITIES block (girders.dm). Plating it into a
// wall and adding reinforcement take a stack of material and stay with the stack (interaction_item); the screwdriver chooses which one a stack does.
// A cult column is only taken apart with a wrench.

MSG_DEF_SELF(girder/secured, "You secured the girder!")
MSG_DEF_SELF(girder/securing, "Now securing the girder...")
MSG_DEF_SELF(girder/dislodged, "You dislodged the girder!")
MSG_DEF_SELF(girder/dislodging, "Now dislodging the girder...")
MSG_DEF_SELF(girder/disassembled, "You dissasembled the girder!")
MSG_DEF_SELF(girder/disassembling, "Now disassembling the girder...")
MSG_DEF_SELF(girder/struts_unsecured, "You unsecured the support struts!")
MSG_DEF_SELF(girder/struts_unsecuring, "Now unsecuring support struts...")
MSG_DEF_SELF(girder/struts_removed, "You removed the support struts!")
MSG_DEF_SELF(girder/struts_removing, "Now removing support struts...")
MSG_DEF_SELF(girder/column_disassembled, "You disassembled the girder!")

/// The ops that take a girder apart.
/proc/girder_construction()
	return list(
		op("secure", tool(TOOL_WRENCH), when(TYPE_PROC_REF(/obj/structure/girder, is_displaced)), priority(OP_PRIORITY_PART), label("Secure the girder"), wait(4 SECONDS), begins(MSG(girder/securing)), says(MSG(girder/secured)), then(TYPE_PROC_REF(/obj/structure/girder, secured))),
		op("dislodge", tool(TOOL_CROWBAR), when(TYPE_PROC_REF(/obj/structure/girder, is_anchored)), priority(OP_PRIORITY_PART), label("Dislodge the girder"), wait(4 SECONDS), begins(MSG(girder/dislodging)), says(MSG(girder/dislodged)), then(TYPE_PROC_REF(/obj/structure/girder, dislodged))),
		op("disassemble", tool(TOOL_WRENCH), when(TYPE_PROC_REF(/obj/structure/girder, is_bare_anchored)), priority(OP_PRIORITY_PART + 1), label("Disassemble the girder"), wait(TYPE_PROC_REF(/obj/structure/girder, disassemble_time)), begins(MSG(girder/disassembling)), says(MSG(girder/disassembled)), then(TYPE_PROC_REF(/obj/structure/girder, disassembled))),
		// chooses whether a stack of material reinforces the girder or plates it into a wall
		op("toggle_reinforcing", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/structure/girder, is_bare_anchored)), priority(OP_PRIORITY_PART + 1), label("Switch between reinforcing and plating"), wait(0), then(TYPE_PROC_REF(/obj/structure/girder, reinforcing_toggled))),
		op("unsecure_struts", tool(TOOL_SCREWDRIVER), when(TYPE_PROC_REF(/obj/structure/girder, struts_secured)), priority(OP_PRIORITY_PART), label("Unsecure the support struts"), wait(4 SECONDS), begins(MSG(girder/struts_unsecuring)), says(MSG(girder/struts_unsecured)), then(TYPE_PROC_REF(/obj/structure/girder, struts_unsecured))),
		op("remove_struts", tool(TOOL_WIRECUTTER), when(TYPE_PROC_REF(/obj/structure/girder, struts_loose)), priority(OP_PRIORITY_PART), label("Remove the support struts"), wait(4 SECONDS), begins(MSG(girder/struts_removing)), says(MSG(girder/struts_removed)), then(TYPE_PROC_REF(/obj/structure/girder, struts_removed))))

/// Not a cult column, which has steps of its own.
/obj/structure/girder/proc/regular_girder()
	return TRUE

/obj/structure/girder/cult/regular_girder()
	return FALSE

/obj/structure/girder/proc/is_displaced(datum/act/A)
	return regular_girder() && !anchored

/obj/structure/girder/proc/is_anchored(datum/act/A)
	return read_once(regular_girder() && anchored && !state)

/// Anchored, struts neither loose nor secured, and no reinforcement material on it.
/obj/structure/girder/proc/is_bare_anchored(datum/act/A)
	return read_once(regular_girder() && anchored && !state && !reinf_material)

/obj/structure/girder/proc/struts_secured(datum/act/A)
	return read_once(regular_girder() && anchored && state == 2)

/obj/structure/girder/proc/struts_loose(datum/act/A)
	return read_once(regular_girder() && anchored && state == 1)

/// 3.5 seconds plus a tick for every 50 integrity (the op scales it by the tool).
/obj/structure/girder/proc/disassemble_time(datum/act/op/A)
	return 35 + round(max_integrity / 50)

/obj/structure/girder/proc/secured(datum/act/op/A)
	reset_girder()
	return OP_OK

/obj/structure/girder/proc/dislodged(datum/act/op/A)
	displace()
	return OP_OK

/obj/structure/girder/proc/disassembled(datum/act/op/A)
	dismantle()
	return OP_OK

/obj/structure/girder/proc/reinforcing_toggled(datum/act/op/A)
	reinforcing = !reinforcing
	to_chat(A.actor, span_notice("\The [src] can now be [reinforcing ? "reinforced" : "constructed"]!"))
	return OP_OK

/obj/structure/girder/proc/struts_unsecured(datum/act/op/A)
	state = 1
	return OP_OK

/obj/structure/girder/proc/struts_removed(datum/act/op/A)
	reinf_material.place_dismantled_product(get_turf(src))
	reinf_material = null
	reset_girder()
	return OP_OK

// ---- Cult columns: the wrench takes them apart, nothing else. ----

CAPABILITIES(/obj/structure/girder/cult)
	op("disassemble_column", tool(TOOL_WRENCH), priority(OP_PRIORITY_PART), label("Disassemble the column"), wait(4 SECONDS), begins(MSG(girder/disassembling)), says(MSG(girder/column_disassembled)), then(PROC_REF(column_disassembled)))

/obj/structure/girder/cult/proc/column_disassembled(datum/act/op/A)
	dismantle()
	return OP_OK
