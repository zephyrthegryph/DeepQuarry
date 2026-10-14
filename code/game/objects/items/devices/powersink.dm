// Powersink - used to drain station power

/obj/item/powersink
	name = "power sink"
	desc = "A nulling power sink which drains energy from electrical systems."
	icon_state = "powersink0"
	icon = 'icons/obj/device.dmi'
	w_class = ITEMSIZE_LARGE
	throw_speed = 1
	throw_range = 2

	MATERIAL_BULK(MAT_STEEL, 750)

	var/drain_rate = 1500000		// amount of power to drain per tick
	var/apc_drain_rate = 5000 		// Max. amount drained from single APC. In Watts.
	var/dissipation_rate = 20000	// Passive dissipation of drained power. In Watts.
	var/power_drained = 0 			// Amount of power drained.
	var/max_power = 1e9				// Detonation point.
	var/drained_this_tick = 0		// One drain per step, however many callers ask.

	var/PN = 0			// The power region we drain
	var/obj/structure/cable/attached		// the attached cable


/// 0 = off, 1 = clamped (off), 2 = operating
/obj/item/powersink/var/mode = 0
TRACKED(/obj/item/powersink, mode)

/// Whether the sink drains (its every() gate, polled).
/obj/item/powersink/proc/operating(datum/act/A)
	return mode == 2

/// It is attached over an exposed cable on bare plating.
/obj/item/powersink/proc/cable_refusal(datum/act/op/A)
	var/turf/T = read_once(loc)
	if(!isturf(T) || !read_once(T.is_plating()))
		return "the device must be placed over an exposed cable to attach to it"
	if(!read_once(locate_within(T, /obj/structure/cable)))
		return "there is no exposed cable here to attach to"

/obj/item/powersink/proc/attached_to_cable(datum/act/op/A)
	rel_set(src, nameof(attached), locate_within(loc, /obj/structure/cable))
	set_anchored(TRUE)
	act_message(A.actor, src, others = span_notice("%U% attaches %T% to the cable!"))
	playsound(src, sounds_of(A.held).use, 50, 1)
	return OP_OK

/obj/item/powersink/proc/detached_from_cable(datum/act/op/A)
	set_anchored(FALSE)
	act_message(A.actor, src, others = span_notice("%U% detaches %T% from the cable!"))
	set_glow(src, GLOW(0, null, null))
	playsound(src, sounds_of(A.held).use, 50, 1)
	set_icon_state("powersink0")
	return OP_OK


CAPABILITIES(/obj/item/powersink)
	configure(item_thrown(force = 5))
	configure(item_sounds(pickup = SFX_ITEMS_PICKUP_DEVICE, drop = SFX_ITEMS_DROP_DEVICE))
	// Drains the attached powernet while operating.
	every(2 SECONDS, then(PROC_REF(powersink_step)), when = PROC_REF(operating))
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))
	// 0 loose, 1 attached to a cable, 2 draining (turned on by hand); the screwdriver attaches it and takes it off again
	stages(nameof(mode),
		stage_step(0, 1, tool(TOOL_SCREWDRIVER), label("Attach to the cable"), needs(req(PROC_REF(cable_refusal))), wait(0), then(PROC_REF(attached_to_cable)), key = "attach"),
		stage_step(1, 0, tool(TOOL_SCREWDRIVER), label("Detach"), wait(0), then(PROC_REF(detached_from_cable)), key = "detach"),
		stage_step(2, 0, tool(TOOL_SCREWDRIVER), label("Detach"), wait(0), then(PROC_REF(detached_from_cable)), key = "detach_running"))
	ref_one(nameof(attached), /obj/structure/cable)

/obj/item/powersink/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	switch(mode)
		if(0)
			return OP_DECLINE
		if(1)
			act_message(user, src, others = span_notice("%U% activates %T%!"))
			set_mode(2)
			set_icon_state("powersink1")
		if(2)  //This switch option wasn't originally included. It exists now. --NeoFite
			act_message(user, src, others = span_notice("%U% deactivates %T%!"))
			set_mode(1)
			set_glow(src, GLOW(0, null, null))
			set_icon_state("powersink0")
		
	return TRUE
/obj/item/powersink/pwr_drain()
	if(!attached())
		return 0

	if(drained_this_tick)
		return 1
	drained_this_tick = 1

	var/drained = 0

	if(!PN)
		return 1

	set_glow(src, GLOW(12, null, null))
	power_warn(PN)
	// found a powernet, so drain up to max power from it
	drained = power_draw(PN, drain_rate)
	// if tried to drain more than available on powernet
	// now look for APCs and drain their cells
	if(drained < drain_rate)
		for(var/obj/machinery/power/terminal/T in power_grid_nodes(PN))
			// Enough power drained this tick, no need to torture more APCs
			if(drained >= drain_rate)
				break
			if(istype(T.master(), /obj/machinery/power/apc))
				var/obj/machinery/power/apc/A = T.master()
				if(A.operating && A.cell)
					var/cur_charge = A.cell.charge / CELLRATE
					var/drain_val = min(apc_drain_rate, cur_charge)
					A.set_cell_charge(A.cell.charge - drain_val * CELLRATE) // the cell and the power domain's charge together: a bare cell write is handed back by the next poll
					drained += drain_val
	power_drained += drained
	return 1

/// Every 2 s while operating: drain the attached powernet (and its APCs), then dissipate.
/obj/item/powersink/proc/powersink_step(datum/act/timer/A)
	drained_this_tick = 0
	PN = attached()?.get_power_region() || 0
	pwr_drain()
	power_drained -= min(dissipation_rate, power_drained)
	if(power_drained > max_power * 0.95)
		play_sfx(src, SFX_EFFECTS_SCREECH)
	if(power_drained >= max_power)
		explosion(src.loc, 3,6,9,12)
		destroyed(src)
		return
	PN = attached()?.get_power_region() || 0

/// Relation view: attached (reads null once it is gone).
/obj/item/powersink/proc/attached() as /obj/structure/cable
	return attached
