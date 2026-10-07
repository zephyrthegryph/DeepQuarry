/obj/machinery/reagent_refinery/vat
	name = "Industrial Chemical Vat"
	desc = "A large storage vat for huge quantities of chemicals. Don't fall in!"
	icon_state = "vat"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 0
	active_power_usage = 50
	circuit = /obj/item/circuitboard/industrial_reagent_vat
	// Chemical bath funtimes!
	can_buckle = TRUE
	buckle_lying = TRUE
	default_max_vol = REAGENT_VAT_VOLUME

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/reagent_refinery/vat/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/reagent_refinery/vat/refinery_step()
	if(length(src?.buckled_mob_list()) && reagents.total_volume > 0)
		for(var/mob/living/L in src?.buckled_mob_list())
			reagents.trans_to(L, 1) // Soak in the juices

	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	refinery_transfer()

/obj/machinery/reagent_refinery/vat/draw(datum/look/look)
	..()
	// GOOBY!
	if(reagents && reagents.total_volume >= 5)
		var/percent = (reagents.total_volume / reagents.maximum_volume) * 100
		switch(percent)
			if(5 to 20) percent = 2
			if(20 to 40) percent = 4
			if(40 to 60) percent = 6
			if(60 to 80) percent = 8
			if(80 to INFINITY) percent = 10
		look.overlay(look_overlay_image(icon, "vat_r_[percent]", color = reagents.get_color(), dir = dir))
	// Get main dir pipe
	look.overlay(look_overlay_image(icon, "vat_cons", dir = dir))
	if(anchored)
		if(operable())
			look.overlay(look_overlay_image(icon, "vat_dot_[ amount_per_transfer_from_this > 0 ? "on" : "off" ]"))
		look.overlay(update_input_connection_overlays("vat_intakes"))

/obj/machinery/reagent_refinery/vat/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_SINGLEOUTPUT, .)

/obj/machinery/reagent_refinery/vat/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// no back/forth, filters don't use just their forward, they send the side too!
	if(dir == GLOB.reverse_dir[source_forward_dir])
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

/// The old MouseDrop_T's guard clause, shared by both drag branches.
/obj/machinery/reagent_refinery/vat/proc/mousedrop_allowed(mob/user, atom/movable/C)
	return !(user?.buckled_to() || user.stat || user.restrained() || !Adjacent(user) || !user.Adjacent(C) || !istype(C) || (user == C && !user.canmove))

/obj/machinery/reagent_refinery/vat/proc/interaction_drain_trolley(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/dropping = A.held
	if(!mousedrop_allowed(user, dropping))
		return OP_OK
	var/atom/movable/C = dropping
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	act_message(user, C, others = "%U% drains %T% into \the [src].")
	update_icon()
	return OP_OK

/obj/machinery/reagent_refinery/vat/proc/interaction_drain_container(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/dropping = A.held
	if(!mousedrop_allowed(user, dropping))
		return OP_OK
	var/atom/movable/C = dropping
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	act_message(user, C, others = "%U% dumps %T% into \the [src].")
	update_icon()
	return OP_OK

/// Busy while someone is buckled in to soak.
/obj/machinery/reagent_refinery/vat/refinery_busy()
	return length(src?.buckled_mob_list()) && reagents.total_volume > 0

CAPABILITIES(/obj/machinery/reagent_refinery/vat)
	without("reagent_refinery_set_transfer_amount")
	op("reagent_vat_drain_trolley", item(/obj/vehicle/train/trolley_tank), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Drain into vat"), then(PROC_REF(interaction_drain_trolley)))
	op("reagent_vat_drain_container", inputs(item(/obj/item/reagent_containers/glass), item(/obj/item/reagent_containers/food/drinks/glass2), item(/obj/item/reagent_containers/food/drinks/shaker), item(/obj/item/reagent_containers/chem_canister)), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Dump into vat"), then(PROC_REF(interaction_drain_container)))
