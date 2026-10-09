// The light fixture frames (doc/rewrite/final_api.html section 12, doc/rewrite/conversion_guide.md).
//
// A frame is a build ladder: bare, wired (a length of cable), closed (a screwdriver: the fixture of its kind takes its place, with the emergency cell
// the frame held). A wrench takes a bare frame down into the sheets it was made of. A frame takes one emergency cell at any stage.

STAGE_DEF(light_frame, bare)
STAGE_DEF(light_frame, wired)
STAGE_DEF(light_frame, closed)

MSG_DEF_SELF(stage/light_frame/bare, "It's an empty frame.")
MSG_DEF_SELF(stage/light_frame/wired, "It's wired.")
MSG_DEF_SELF(stage/light_frame/closed, "The casing is closed.")
MSG_DEF_SELF(light_frame/unwire_first, "You have to remove the wires first.")
MSG_DEF_SELF(light_frame/no_cells, "This casing can't support a power cell!")

/obj/machinery/light_construct
	name = "light fixture frame"
	desc = "A light fixture under construction."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "tube-construct-stage1"
	anchored = TRUE
	plane = MOB_PLANE
	layer = BELOW_MOB_LAYER
	/// The fixture type this builds, and the sheets a bare frame comes apart into.
	var/fixture_type = /obj/machinery/light
	var/sheets_refunded = 2
	/// The picture prefix of the type: "[construct_state]-construct-stage1", "-stage2".
	var/construct_state = "tube"
	/// The emergency cell in the casing.
	var/obj/item/cell/emergency_light/cell
	var/cell_connectors = TRUE

CAPABILITIES(/obj/machinery/light_construct)
	construction(start(STAGE_LIGHT_FRAME_BARE),
		stage(STAGE_LIGHT_FRAME_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(0), then(PROC_REF(wired)), undone(PROC_REF(unwired)), undo = list(tool(TOOL_WIRECUTTER), wait(0))),
		stage(STAGE_LIGHT_FRAME_CLOSED, tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(closed_into_fixture)), undo = NO_UNDO),
		dismantle(tool(TOOL_WRENCH), wait(3 SECONDS), then(PROC_REF(taken_apart))))
	extend("construction.dismantle", needs(req_not(req_built(STAGE_LIGHT_FRAME_WIRED, because = MSG(light_frame/unwire_first)), because = MSG(light_frame/unwire_first))))
	owns_one(nameof(cell), /obj/item/cell/emergency_light)
	cell_bay(nameof(cell), accepts = /obj/item/cell/emergency_light)
	extend("cell_bay.cell.take", when(req_empty_hand()))
	extend("cell_bay.cell.insert", needs(req_bool(PROC_REF(takes_cells), because = MSG(light_frame/no_cells)), req_empty(nameof(cell), because = MSG(bay/full))))
	examine_line(PROC_REF(examine_cell))
	param(nameof(dir), pos = 1)
	param(nameof(fixture_at_make), pos = 4, keep = FALSE)

/// The fixture the frame was taken down from (its constructor param, dropped after init).
/obj/machinery/light_construct/var/tmp/obj/machinery/light/fixture_at_make

// ALLOW(init/INSTANCE_STATE): a frame taken down from a fixture keeps its facing and wiring
/obj/machinery/light_construct/Initialize(mapload)
	. = ..()
	if(fixture_at_make)
		var/obj/machinery/light/fixture = fixture_at_make
		fixture_type = fixture.type
		fixture.transfer_fingerprints_to(src)
		set_dir(fixture.dir)
		graph_place(src, STAGE_LIGHT_FRAME_WIRED)
	update_state()

/// The picture follows how far the frame is built.
/obj/machinery/light_construct/proc/update_state()
	icon_state = built(src, STAGE_LIGHT_FRAME_WIRED) ? "[construct_state]-construct-stage2" : "[construct_state]-construct-stage1"

/obj/machinery/light_construct/proc/takes_cells(datum/act/A)
	return cell_connectors

/// Within two tiles it says what the casing can hold.
/obj/machinery/light_construct/proc/examine_cell(datum/act/op/A)
	var/mob/user = A.actor
	if(!user || get_dist(user, src) > 2)
		return null
	if(!cell_connectors)
		return span_danger("This casing doesn't support power cells for backup power.")
	if(!cell)
		return "The casing has no power cell for backup power."
	return null

/obj/machinery/light_construct/proc/wired(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF("You add wires to %T%."), MSG_OTHERS("[A.actor.name] adds wires to %T%."))
	update_state()
	return OP_OK

/// The ledger gives the cable back; the frame is bare again.
/obj/machinery/light_construct/proc/unwired(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF("You remove the wiring from %T%."), MSG_OTHERS("[A.actor.name] removes the wiring from %T%."), MSG_BLIND("You hear a noise."))
	update_state()
	return OP_OK

/// The casing closes: the fixture of its kind takes the frame's place, facing the same way, with the frame's cell.
/obj/machinery/light_construct/proc/closed_into_fixture(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF("You close %T%'s casing."), MSG_OTHERS("[user.name] closes %T%'s casing."), MSG_BLIND("You hear a noise."))
	var/obj/machinery/light/finished_light = new fixture_type(loc, src)
	finished_light.set_dir(dir)
	transfer_fingerprints_to(finished_light)
	if(cell)
		finished_light.latent_cell_charge = null
		cell.forceMove(finished_light)
		rel_move(src, nameof(cell), finished_light, nameof(finished_light.cell))
	replace_with(src, finished_light)
	return OP_OK

/// A bare frame comes apart into its sheets.
/obj/machinery/light_construct/proc/taken_apart(datum/act/op/A)
	act_message(A.actor, src, MSG_SELF("You deconstruct %T%."), MSG_OTHERS("[A.actor.name] deconstructs %T%."), MSG_BLIND("You hear a noise."))
	play_sfx(src, SFX_ITEMS_DECONSTRUCT, 1.5)
	replace_with(src, /obj/item/stack/material/steel, sheets_refunded)
	return OP_OK

/obj/machinery/light_construct/small
	name = "small light fixture frame"
	desc = "A small light fixture under construction."
	icon_state = "bulb-construct-stage1"
	construct_state = "bulb"
	fixture_type = /obj/machinery/light/small
	sheets_refunded = 1

/obj/machinery/light_construct/flamp
	name = "floor light fixture frame"
	desc = "A floor light fixture under construction."
	icon_state = "flamp-construct-stage1"
	construct_state = "flamp"
	anchored = FALSE
	plane = OBJ_PLANE
	layer = OBJ_LAYER
	fixture_type = /obj/machinery/light/flamp
	sheets_refunded = 2

/obj/machinery/light_construct/floortube
	name = "floor light fixture frame"
	desc = "A floor light fixture under construction."
	icon_state = "floortube-construct-stage1"
	construct_state = "floortube"
	anchored = FALSE
	fixture_type = /obj/machinery/light/floortube
	sheets_refunded = 2

// ALLOW(init/INSTANCE_STATE): make_rotatable() grants this construct its rotation ops
/obj/machinery/light_construct/floortube/Initialize(mapload, newdir, building, datum/frame/frame_types/frame_type, obj/machinery/light/fixture)
	. = ..()
	make_rotatable()

/obj/machinery/light_construct/bigfloorlamp
	name = "big floor light fixture frame"
	desc = "A big floor light fixture under construction."
	icon = 'icons/obj/lighting32x64.dmi'
	icon_state = "big_flamp-construct-stage1"
	construct_state = "big_flamp"
	anchored = FALSE
	fixture_type = /obj/machinery/light/bigfloorlamp
	sheets_refunded = 3
