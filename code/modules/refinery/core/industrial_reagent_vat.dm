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

/obj/machinery/reagent_refinery/vat/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/reagent_refinery/vat/process()
	if(buckled_mobs && buckled_mobs.len && reagents.total_volume > 0)
		for(var/mob/living/L in buckled_mobs)
			reagents.trans_to(L, 1) // Soak in the juices

	if(!anchored)
		return

	power_change()
	if(stat & (NOPOWER|BROKEN))
		return

	refinery_transfer()

/obj/machinery/reagent_refinery/vat/update_icon()
	cut_overlays()
	// GOOBY!
	if(reagents && reagents.total_volume >= 5)
		var/percent = (reagents.total_volume / reagents.maximum_volume) * 100
		switch(percent)
			if(5 to 20)			percent = 2
			if(20 to 40) 		percent = 4
			if(40 to 60)		percent = 6
			if(60 to 80)		percent = 8
			if(80 to INFINITY)	percent = 10
		var/image/filling = image(icon, loc, "vat_r_[percent]",dir = dir)
		filling.color = reagents.get_color()
		add_overlay(filling)
	// Get main dir pipe
	var/image/pipe = image(icon, icon_state = "vat_cons", dir = dir)
	add_overlay(pipe)
	if(anchored)
		if(!(stat & (NOPOWER|BROKEN)))
			var/image/dot = image(icon, icon_state = "vat_dot_[ amount_per_transfer_from_this > 0 ? "on" : "off" ]")
			add_overlay(dot)
		update_input_connection_overlays("vat_intakes")

/obj/machinery/reagent_refinery/vat/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is pumping chemicals at a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_SINGLEOUTPUT, .)

/obj/machinery/reagent_refinery/vat/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// no back/forth, filters don't use just their forward, they send the side too!
	if(dir == GLOB.reverse_dir[source_forward_dir])
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

/obj/machinery/reagent_refinery/vat/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_drag/reagent_vat_drain_trolley,
		/datum/interaction/machine_drag/reagent_vat_drain_container,
	)
	..()

/// The old MouseDrop_T's guard clause, shared by both drag branches.
/obj/machinery/reagent_refinery/vat/proc/mousedrop_allowed(mob/user, atom/movable/C)
	return !(user.buckled || user.stat || user.restrained() || !Adjacent(user) || !user.Adjacent(C) || !istype(C) || (user == C && !user.canmove))

/// The old MouseDrop_T's first branch: drains a trolley tank into the vat.
/datum/interaction/machine_drag/reagent_vat_drain_trolley
	id = "reagent_vat_drain_trolley"
	name = "Drain into vat"
	held_type = /obj/vehicle/train/trolley_tank
	effect = /obj/machinery/reagent_refinery/vat/proc/interaction_drain_trolley

/obj/machinery/reagent_refinery/vat/proc/interaction_drain_trolley(mob/user, atom/movable/dropping, datum/interaction/interaction)
	if(!mousedrop_allowed(user, dropping))
		return TRUE
	var/atom/movable/C = dropping
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	visible_message("\The [user] drains \the [C] into \the [src].")
	update_icon()
	return TRUE

/// The old MouseDrop_T's second branch: dumps a reagent container into the vat.
/datum/interaction/machine_drag/reagent_vat_drain_container
	id = "reagent_vat_drain_container"
	name = "Dump into vat"
	held_type = list(
		/obj/item/reagent_containers/glass,
		/obj/item/reagent_containers/food/drinks/glass2,
		/obj/item/reagent_containers/food/drinks/shaker,
		/obj/item/reagent_containers/chem_canister,
	)
	effect = /obj/machinery/reagent_refinery/vat/proc/interaction_drain_container

/obj/machinery/reagent_refinery/vat/proc/interaction_drain_container(mob/user, atom/movable/dropping, datum/interaction/interaction)
	if(!mousedrop_allowed(user, dropping))
		return TRUE
	var/atom/movable/C = dropping
	// Drain it!
	C.reagents.trans_to_holder( src.reagents, src.reagents.maximum_volume)
	visible_message("\The [user] dumps \the [C] into \the [src].")
	update_icon()
	return TRUE

/obj/machinery/reagent_refinery/vat/declare_interactions(list/into)
	. = ..()
	into -= /datum/interaction/machine_verb/reagent_refinery_set_transfer_amount
