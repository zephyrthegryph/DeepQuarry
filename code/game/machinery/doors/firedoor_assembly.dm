/obj/structure/firedoor_assembly
	name = "\improper emergency shutter assembly"
	desc = "It can save lives."
	icon = 'icons/obj/doors/DoorHazard.dmi'
	icon_state = "door_construction"
	anchored = FALSE
	opacity = 0
	density = TRUE
	var/glass = FALSE

TRACKED(/obj/structure/firedoor_assembly, glass)

/// The look (the draw sweep: from its layers).
/obj/structure/firedoor_assembly/draw(datum/look/look)
	..()
	switch("[glass]")
		if("1")
			look.set_icon('icons/obj/doors/DoorHazardGlass.dmi')
		else
			look.set_icon('icons/obj/doors/DoorHazard.dmi')
	switch("[anchored]")
		if("1")
			look.state("door_anchored")
		else
			look.state("door_construction")

// ---- what a firedoor assembly is, declared ----
//
// A loose frame, bolted down or loose by a wrench at any time. Wired (a length of cable, once it is bolted down; wirecutters take it back) and then
// finished with the circuit board of an air alarm, which stands the firedoor in its place. Reinforced glass makes it a glass shutter and a welder
// takes the glass back out; from a loose bare frame the same welder takes the whole assembly down into steel.

STAGE_DEF(firedoor_assembly, frame)
STAGE_DEF(firedoor_assembly, wired)
STAGE_DEF(firedoor_assembly, finished)

MSG_DEF_SELF(stage/firedoor_assembly/frame, "It is a bare frame.")
MSG_DEF_SELF(stage/firedoor_assembly/wired, "It is wired.")
MSG_DEF_SELF(stage/firedoor_assembly/finished, "It is finished.")

MSG_DEF_SELF(firedoor_assembly/bolt_first, "You must secure it first!")
MSG_DEF_SELF(firedoor_assembly/bolted_down, "Unbolt it from the floor first.")
MSG_DEF_SELF(firedoor_assembly/glazed, "Take the glass out first.")

CAPABILITIES(/obj/structure/firedoor_assembly)
	construction(start(STAGE_FIREDOOR_ASSEMBLY_FRAME),
		stage(STAGE_FIREDOOR_ASSEMBLY_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(4 SECONDS), needs(req_is(nameof(anchored), TRUE, because = MSG(firedoor_assembly/bolt_first))), then(PROC_REF(wired_up)), undone(PROC_REF(unwired)), undo = list(tool(TOOL_WIRECUTTER), wait(4 SECONDS))),
		stage(STAGE_FIREDOOR_ASSEMBLY_FINISHED, item(/obj/item/circuitboard/airalarm), wait(0), needs(req_is(nameof(anchored), TRUE, because = MSG(firedoor_assembly/bolt_first)), req_bool(PROC_REF(board_releasable), because = PROC_REF(board_release_refusal))), then(PROC_REF(finish_firedoor)), undo = null),
		dismantle(tool(TOOL_WELDER), wait(4 SECONDS), then(PROC_REF(disassembled))))
	op("anchor", tool(TOOL_WRENCH), label("Bolt or unbolt"), wait(0), then(PROC_REF(anchor_toggled)))
	op("plate_glass", item(/obj/item/stack/material/glass/reinforced), label("Install windows"), when(PROC_REF(unglazed)), wait(4 SECONDS), then(PROC_REF(glass_in)))
	op("unglaze", tool(TOOL_WELDER), label("Take the glass out"), when(nameof(glass)), priority(above("construction.dismantle")), wait(4 SECONDS), then(PROC_REF(glass_out)))
	extend("construction.dismantle", needs(req_is(nameof(anchored), FALSE, because = MSG(firedoor_assembly/bolted_down))))

/// No glass is fitted.
/obj/structure/firedoor_assembly/proc/unglazed(datum/act/A)
	return !glass

/// A wrench bolts the frame down or frees it.
/obj/structure/firedoor_assembly/proc/anchor_toggled(datum/act/op/A)
	set_anchored(!anchored)
	playsound(src, A.held.usesound, 50, TRUE)
	act_message(A.actor, src, MSG_SELF("You have [anchored ? "" : "un"]secured %T%!"), MSG_OTHERS(span_warning("%U% has [anchored ? "" : "un"]secured %T%!")))
	return OP_OK

/obj/structure/firedoor_assembly/proc/wired_up(datum/act/op/A)
	to_chat(A.actor, span_notice("You wire \the [src]."))
	return OP_OK

/obj/structure/firedoor_assembly/proc/unwired(datum/act/op/A)
	to_chat(A.actor, span_notice("You cut the wires!"))
	new /obj/item/stack/cable_coil(loc, 1)
	return OP_OK

/// A board must leave its actual holder before finishing can consume it.
/obj/structure/firedoor_assembly/proc/board_releasable(datum/act/op/A)
	return isnull(board_release_refusal(A))

/obj/structure/firedoor_assembly/proc/board_release_refusal(datum/act/op/A)
	if(!A.actor || A.actor.get_active_hand() != A.held)
		return /datum/msg/req_wrong_item
	return A.actor.release_refusal(A.held, A.actor)

/// The finished assembly stands the firedoor in its place, and the board goes into it.
/obj/structure/firedoor_assembly/proc/finish_firedoor(datum/act/op/A)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	act_message(A.actor, src, MSG_SELF("You have inserted the circuit into %T%!"), MSG_OTHERS(span_warning("%U% has inserted a circuit into %T%!")))
	consume(A.held, A.actor)
	replace_with(src, glass ? /obj/machinery/door/firedoor/glass : /obj/machinery/door/firedoor)
	return OP_OK

/// A loose bare frame comes apart into two sheets of steel.
/obj/structure/firedoor_assembly/proc/disassembled(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF("You have disassembled %T%."), MSG_OTHERS(span_warning("%U% has disassembled %T%.")))
	replace_with(src, /obj/item/stack/material/steel, 2)
	return OP_OK

/obj/structure/firedoor_assembly/proc/glass_in(datum/act/op/A)
	var/obj/item/stack/S = A.held
	if(glass || !S?.use(1))
		return OP_REFUSED
	to_chat(A.actor, span_notice("You installed reinforced glass windows into \the [src]."))
	set_glass(TRUE)
	return OP_OK

/obj/structure/firedoor_assembly/proc/glass_out(datum/act/op/A)
	to_chat(A.actor, span_notice("You welded the glass panel out!"))
	new /obj/item/stack/material/glass/reinforced(drop_location())
	set_glass(FALSE)
	return OP_OK
