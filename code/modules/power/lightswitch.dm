//
// Lightswitch Construction
// Note: This does not use the normal frame.dm approach becuase:
// 1) That requires circuits, and I don't want a circuit board instance in every lightswitch.
// 2) This is an experiment in modernizing construction steps and examine tabs.

// The frame item in hand
/obj/item/frame/lightswitch
	name = "light switch frame"
	desc = "Used for building light switches."
	icon = 'icons/obj/power_vr.dmi'
	icon_state = "lightswitch-s1"
	build_machine_type = /obj/structure/construction/lightswitch
	refund_amt = 2

// The under construction light switch
/obj/structure/construction/lightswitch
	name = "light switch frame"
	desc = "A light switch under construction."
	icon = 'icons/obj/power_vr.dmi'
	icon_state = "lightswitch-s1"
	base_icon = "lightswitch-s"
	build_machine_type = /obj/machinery/light_switch
	x_offset = 26
	y_offset = 26

/obj/machinery/light_switch
	maintenance_flags = MACHINE_MAINT_STANDARD

/obj/machinery/light_switch/dismantle()
	play_sfx(src, SFX_ITEMS_CROWBAR)
	var/obj/structure/construction/lightswitch/A = new(src.loc, src.dir)
	graph_place(A, STAGE_LIGHTSWITCH_WIRED)
	A.pixel_x = pixel_x
	A.pixel_y = pixel_y
	A.update_state()
	replace_with(src, A)
	return 1

//
// Simple Construction Frame: circuitless construction for light switches (a graph: loose frame, fastened to the wall, wired, closed into the
// switch; a welder takes a loose frame down).
//

STAGE_DEF(lightswitch, frame)
STAGE_DEF(lightswitch, fastened)
STAGE_DEF(lightswitch, wired)
STAGE_DEF(lightswitch, finished)

MSG_DEF_SELF(stage/lightswitch/frame, "It's an empty frame.")
MSG_DEF_SELF(stage/lightswitch/fastened, "It's fixed to the wall.")
MSG_DEF_SELF(stage/lightswitch/wired, "It's wired.")
MSG_DEF_SELF(stage/lightswitch/finished, "It is finished.")

/obj/structure/construction
	name = "simple frame prototype"
	desc = "This is a prototype object and you should not see it, report to a developer"
	anchored = TRUE
	var/base_icon = "something"
	var/build_machine_type = null
	var/x_offset = 26
	var/y_offset = 26

CAPABILITIES(/obj/structure/construction)
	param(nameof(dir), pos = 1)

// ALLOW(init/INSTANCE_STATE): a wall frame sits on its wall, offset by its facing
/obj/structure/construction/Initialize(mapload)
	. = ..()
	if(x_offset)
		pixel_x = (dir & 3) ? 0 : (dir == EAST ? -x_offset : x_offset)
	if(y_offset)
		pixel_y = (dir & 3) ? (dir == NORTH ? -y_offset : y_offset) : 0
	update_state()

CAPABILITIES(/obj/structure/construction/lightswitch)
	construction(start(STAGE_LIGHTSWITCH_FRAME),
		stage(STAGE_LIGHTSWITCH_FASTENED, tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(stage_changed)), undone(PROC_REF(stage_changed))),
		stage(STAGE_LIGHTSWITCH_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(0), then(PROC_REF(wired)), undone(PROC_REF(unwired)), undo = list(tool(TOOL_WIRECUTTER), wait(0))),
		stage(STAGE_LIGHTSWITCH_FINISHED, tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(finished)), undo = NO_UNDO),
		dismantle(tool(TOOL_WELDER), wait(2 SECONDS), then(PROC_REF(deconstructed))))
	extend("construction.dismantle", needs(req_not(req_built(STAGE_LIGHTSWITCH_FASTENED, because = MSG(lightswitch/fastened_first)), because = MSG(lightswitch/fastened_first))))
	op("touch", item(/obj/item), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(touched_with)), passes())

MSG_DEF_SELF(lightswitch/fastened_first, "You have to unscrew the case first.")

/// How far the frame is built, as the number its picture is made from: FRAME_UNFASTENED, FRAME_FASTENED or FRAME_WIRED.
/obj/structure/construction/proc/frame_stage()
	if(built(src, STAGE_LIGHTSWITCH_WIRED))
		return FRAME_WIRED
	if(built(src, STAGE_LIGHTSWITCH_FASTENED))
		return FRAME_FASTENED
	return FRAME_UNFASTENED

/obj/structure/construction/proc/update_state()
	icon_state = "[base_icon][frame_stage()]"

/obj/structure/construction/proc/stage_changed(datum/act/op/A)
	update_state()
	play_sfx(src, SFX_ITEMS_SCREWDRIVER, 75)
	return OP_OK

/obj/structure/construction/proc/wired(datum/act/op/A)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	update_state()
	return OP_OK

/// The ledger gives the length of cable back.
/obj/structure/construction/proc/unwired(datum/act/op/A)
	update_state()
	return OP_OK

/obj/structure/construction/proc/touched_with(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/// The last screw closes the frame into the machine it stands for, on the same spot.
/obj/structure/construction/proc/finished(datum/act/op/A)
	var/obj/newmachine = new build_machine_type(get_turf(src), src.dir)
	newmachine.pixel_x = pixel_x
	newmachine.pixel_y = pixel_y
	transfer_fingerprints_to(newmachine)
	replace_with(src, newmachine)
	return OP_OK

/obj/structure/construction/proc/deconstructed(datum/act/op/A)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT, 1.5)
	replace_with(src, /obj/item/stack/material/steel, 2)
	return OP_OK
