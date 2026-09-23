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

// Attackby on the lightswitch for deconstruction steps.
/// The old attackby: fingerprinted, then fell through to ..().
/datum/interaction/machine_item/lightswitch_fingerprint
	id = "lightswitch_fingerprint"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/light_switch/proc/interaction_fingerprint

/obj/machinery/light_switch/proc/interaction_fingerprint(mob/user, obj/item/W, datum/interaction/interaction)
	src.add_fingerprint(user)
	return FALSE

/obj/machinery/light_switch
	maintenance_flags = MACHINE_MAINT_STANDARD

/obj/machinery/light_switch/dismantle()
	playsound(src, 'sound/items/Crowbar.ogg', 50, 1)
	var/obj/structure/construction/lightswitch/A = new(src.loc, src.dir)
	A.stage = FRAME_WIRED
	A.pixel_x = pixel_x
	A.pixel_y = pixel_y
	A.update_icon()
	qdel(src)
	return 1

//
// Simple Construction Frame - Simpler than the full frame system for circuitless construction.
// If this works out well for light switches we can use it for other lightweight constructables.
//

/obj/structure/construction
	name = "simple frame prototype"
	desc = "This is a prototype object and you should not see it, report to a developer"
	anchored = TRUE
	var/base_icon = "something"
	var/stage = FRAME_UNFASTENED
	var/build_machine_type = null
	var/x_offset = 26
	var/y_offset = 26

/obj/structure/construction/Initialize(mapload, ndir, building = FALSE)
	. = ..()
	if(ndir)
		set_dir(ndir)
	if(x_offset)
		pixel_x = (dir & 3) ? 0 : (dir == EAST ? -x_offset : x_offset)
	if(y_offset)
		pixel_y = (dir & 3) ? (dir == NORTH ? -y_offset : y_offset) : 0

/obj/structure/construction/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		switch(stage)
			if(FRAME_UNFASTENED)
				. += "It's an empty frame."
			if(FRAME_FASTENED)
				. += "It's fixed to the wall."
			if(FRAME_WIRED)
				. += "It's wired."

/obj/structure/construction/update_icon()
	icon_state = "[base_icon][stage]"

/obj/structure/construction/attackby(obj/item/W as obj, mob/user as mob)
	add_fingerprint(user)
	if(istype(W, /obj/item/stack/cable_coil))
		if (stage == FRAME_FASTENED)
			var/obj/item/stack/cable_coil/coil = W
			if (coil.use(1))
				stage = FRAME_WIRED
				user.update_examine_panel(src)
				user.visible_message("\The [user] adds wires to \the [src].", \
					"You add wires to \the [src].", "You hear a noise.")
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				update_icon()
		return

	. = ..()

/obj/structure/construction/welder_act(mob/user, obj/item/W)
	if(stage != FRAME_UNFASTENED)
		to_chat(user, stage == FRAME_FASTENED ? "You have to unscrew the case first." : "You have to remove the wires first.")
		return ITEM_INTERACT_BLOCKING
	if(use_tool(user, W, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, \
			message_self = "You start deconstructing \the [src].", message_others = "\The [user] begins deconstructing \the [src]."))
		new /obj/item/stack/material/steel(get_turf(src), 2)
		user.visible_message(span_warning("\The [user] has deconstructed \the [src]."), span_notice("You deconstruct \the [src]."))
		playsound(src, 'sound/items/Deconstruct.ogg', 75, 1)
		qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/structure/construction/wirecutter_act(mob/user, obj/item/W)
	if(stage != FRAME_WIRED)
		return ITEM_INTERACT_BLOCKING
	stage = FRAME_FASTENED
	user.update_examine_panel(src)
	new /obj/item/stack/cable_coil(get_turf(src), 1, "red")
	user.visible_message("\The [user] removes the wiring from \the [src].", "You remove the wiring from \the [src].", "You hear a snip.")
	playsound(src, W.usesound, 50, 1)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/structure/construction/screwdriver_act(mob/user, obj/item/W)
	if(stage == FRAME_UNFASTENED)
		stage = FRAME_FASTENED
		user.visible_message("\The [user] screws \the [src] in place.", "You screw \the [src] in place.", "You hear a noise.")
	else if(stage == FRAME_FASTENED)
		stage = FRAME_UNFASTENED
		user.visible_message("\The [user] unscrews \the [src].", "You unscrew \the [src].", "You hear a noise.")
	else
		user.visible_message("\The [user] closes \the [src]'s casing.", "You close \the [src]'s casing.", "You hear a click.")
		playsound(src, W.usesound, 75, 1)
		var/obj/newmachine = new build_machine_type(get_turf(src), src.dir)
		newmachine.pixel_x = pixel_x
		newmachine.pixel_y = pixel_y
		transfer_fingerprints_to(newmachine)
		qdel(src)
		return ITEM_INTERACT_SUCCESS
	user.update_examine_panel(src)
	playsound(src, W.usesound, 75, 1)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/structure/construction/get_description_interaction()
	. = list()
	switch(stage)
		if(FRAME_UNFASTENED)
			. += list(
				"[desc_panel_image("screwdriver")]to continue construction.",
				"[desc_panel_image("welder")]to deconstruct.")
		if(FRAME_FASTENED)
			. += list(
				"[desc_panel_image("cable coil")]to continue construction.",
				"[desc_panel_image("screwdriver")]to reverse construction.")
		if(FRAME_WIRED)
			. += list(
				"[desc_panel_image("screwdriver")]to finish construction.",
				"[desc_panel_image("wirecutters")]to reverse construction.")
