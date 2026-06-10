// Surface freight export terminal.
//
// The turn-in point for the Freight Quota floor. Cargo hauls mined ore up
// the elevator, stages it (loose or in crates) on the tiles around this
// terminal, and ships it off to Central — that shipment is what credits
// the active freight order, NOT merely arriving at the surface bay. One
// terminal is placed next to the surface elevator bay at round start.
//
// "Active freight order" is whichever Freight Quota floor sits at the
// frontier gate (see SSquarry.active_freight_depth). Shipping when no
// freight order is open refuses and keeps the ore — so a stray shipment
// can't waste a player's haul.

/obj/structure/quarry_freight_export
	name = "freight export terminal"
	desc = "A bonded shipping terminal. Stage ore around it — loose or crated — and ship it off to Central to fill the standing freight order."
	icon = 'icons/obj/turbolift.dmi'
	icon_state = "button"
	density = TRUE
	anchored = TRUE
	light_range = 2
	light_power = 0.7

/obj/structure/quarry_freight_export/examine(mob/user)
	. = ..()
	if(!SSquarry)
		return
	var/depth = SSquarry.active_freight_depth()
	if(!depth)
		. += span_notice("No freight order is open right now.")
		return
	var/list/status = SSquarry.freight_order_progress(depth)
	if(islist(status))
		. += span_notice("Standing order (depth [depth]): [status["progress"]] / [status["target"]] units shipped.")
	else
		. += span_notice("A freight order from depth [depth] is open.")

/obj/structure/quarry_freight_export/attack_hand(mob/user)
	if(!user.Adjacent(src))
		to_chat(user, span_warning("You need to be next to \the [src]."))
		return
	if(user.incapacitated())
		return
	if(!SSquarry)
		to_chat(user, span_warning("\The [src] is offline."))
		return

	var/depth = SSquarry.active_freight_depth()
	if(!depth)
		to_chat(user, span_warning("\The [src] beeps: no freight order is currently open."))
		return

	// Gather staged ore: loose on the surrounding tiles, plus ore inside
	// any non-mob container (crates, closets, ore bags) on those tiles.
	var/list/ore_items = list()
	for(var/turf/T in range(1, src))
		for(var/atom/movable/AM in T)
			if(ismob(AM))
				continue
			if(istype(AM, /obj/item/ore))
				ore_items += AM
				continue
			for(var/obj/item/ore/O in AM)
				ore_items += O

	if(!length(ore_items))
		to_chat(user, span_warning("\The [src] beeps: stage ore on the surrounding tiles first."))
		return

	var/shipped = length(ore_items)
	for(var/obj/item/ore/O as anything in ore_items)
		qdel(O)
	playsound(src, 'sound/machines/ping.ogg', 50, 1)
	SSquarry.on_layer_delivery(depth, shipped)
	visible_message(span_notice("\The [src] hums as [shipped] units of ore are bonded and shipped off to Central."))

	// Report the standing order's new state.
	var/list/status = SSquarry.freight_order_progress(SSquarry.active_freight_depth() || depth)
	if(islist(status))
		to_chat(user, span_notice("Freight order: [status["progress"]] / [status["target"]] units."))
