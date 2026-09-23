//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33
/obj/machinery/power/rad_collector
	name = "Radiation Collector Array"
	desc = "A device which uses Hawking Radiation and phoron to produce power."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "ca"
	anchored = FALSE
	density = TRUE
	req_access = list(ACCESS_ENGINE_EQUIP)
//	use_power = 0
	var/obj/item/tank/phoron/P = null
	var/last_power = 0
	var/last_power_new = 0
	var/active = 0
	var/locked = 0
	var/drainratio = 1
	rad_insulation = RAD_EXTREME_INSULATION //It sucks up the radiation. If you're standing behind it, you're pretty safe.

REGISTRY_MEMBERSHIP(/obj/machinery/power/rad_collector, REGISTRY_RAD_COLLECTORS)

/obj/machinery/power/rad_collector/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/climbable)
	RegisterSignal(src, COMSIG_IN_RANGE_OF_IRRADIATION, PROC_REF(process_rads))

/obj/machinery/power/rad_collector/Destroy()
	UnregisterSignal(src, COMSIG_IN_RANGE_OF_IRRADIATION)
	return ..()

/obj/machinery/power/rad_collector/proc/process_rads(datum/source, datum/radiation_pulse_information/pulse_information)
	SIGNAL_HANDLER
	//so that we don't zero out the meter if the SM is processed first.
	last_power = last_power_new
	last_power_new = 0


	if(P && active)
		if(pulse_information)
			var/amount_of_rads = pulse_information.strength
			receive_pulse((amount_of_rads))

			if(LINDA_GAS_AMT(P.air_contents, GAS_PHORON) == 0) // XGM .gas[id] read
				investigate_log(span_red("out of fuel") + ".","singulo")
				eject()
			else
				P.air_contents.adjust_gas(GAS_PHORON, -0.0001*drainratio)
	return


/obj/machinery/power/rad_collector/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/rad_collector_load_tank,
		/datum/interaction/machine_item/rad_collector_lock,
		/datum/interaction/machine_hand/ungated/rad_collector_toggle,
	)
	..()

/datum/interaction/machine_hand/ungated/rad_collector_toggle
	id = "rad_collector_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	effect = /obj/machinery/power/rad_collector/proc/interaction_toggle

/obj/machinery/power/rad_collector/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	if(anchored)
		if(!src.locked)
			toggle_power()
			user.visible_message("[user.name] turns the [src.name] [active? "on":"off"].", \
			"You turn the [src.name] [active? "on":"off"].")
			investigate_log("turned [active?span_green("on"): span_red("off")] by [user.key]. [P?"Fuel: [round(LINDA_GAS_AMT(P.air_contents, GAS_PHORON)/0.29)]%":span_red("It is empty")].","singulo")
			return TRUE
		else
			to_chat(user, span_red("The controls are locked!"))
			return TRUE
	return TRUE

/datum/interaction/machine_item/rad_collector_load_tank
	id = "rad_collector_load_tank"
	name = "Load phoron tank"
	held_type = /obj/item/tank/phoron
	effect = /obj/machinery/power/rad_collector/proc/interaction_load_tank

/obj/machinery/power/rad_collector/proc/interaction_load_tank(mob/user, obj/item/tank/phoron/W, datum/interaction/interaction)
	if(!src.anchored)
		to_chat(user, span_red("The [src] needs to be secured to the floor first."))
		return TRUE
	if(src.P)
		to_chat(user, span_red("There's already a phoron tank loaded."))
		return TRUE
	user.drop_item()
	src.P = W
	W.loc = src
	update_icons()
	return TRUE

/datum/interaction/machine_item/rad_collector_lock
	id = "rad_collector_lock"
	name = "Toggle lock"
	held_type = list(/obj/item/card/id, /obj/item/pda)
	effect = /obj/machinery/power/rad_collector/proc/interaction_lock

/obj/machinery/power/rad_collector/proc/interaction_lock(mob/user, obj/item/W, datum/interaction/interaction)
	if (src.allowed(user))
		if(active)
			src.locked = !src.locked
			to_chat(user, "The controls are now [src.locked ? "locked." : "unlocked."]")
		else
			src.locked = 0 //just in case it somehow gets locked
			to_chat(user, span_red("The controls can only be locked when the [src] is active."))
	else
		to_chat(user, span_red("Access denied!"))
	return TRUE

/obj/machinery/power/rad_collector/crowbar_act(mob/user, obj/item/W)
	if(P && !locked)
		eject()
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/machinery/power/rad_collector/wrench_act(mob/user, obj/item/W)
	if(P)
		to_chat(user, span_blue("Remove the phoron tank first."))
		return ITEM_INTERACT_BLOCKING
	playsound(src, W.usesound, 75, 1)
	anchored = !anchored
	user.visible_message("[user.name] [anchored ? "secures" : "unsecures"] the [src.name].", \
		"You [anchored ? "secure" : "undo"] the external bolts.", \
		"You hear a ratchet.")
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/rad_collector/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 3)
		. += "The meter indicates that it is collecting [last_power] W."

/obj/machinery/power/rad_collector/ex_act(severity)
	switch(severity)
		if(2, 3)
			eject()
	return ..()


/obj/machinery/power/rad_collector/proc/eject()
	locked = 0
	var/obj/item/tank/phoron/Z = src.P
	if (!Z)
		return
	Z.loc = get_turf(src)
	Z.layer = initial(Z.layer)
	src.P = null
	if(active)
		toggle_power()
	else
		update_icons()

// Continuing here, SM giving us ~170 rads per pulse, a phoron canister full of 30 mols, and * 20 we get:
// 102000W per collector...So 10 collectors will give us ~1MW.
/obj/machinery/power/rad_collector/proc/receive_pulse(pulse_strength)
	if(P && active)
		var/power_produced = 0
		power_produced = LINDA_GAS_AMT(P.air_contents, GAS_PHORON)*pulse_strength*20
		if(power_produced)
			add_avail(power_produced)
			last_power_new = power_produced
		return
	return


/obj/machinery/power/rad_collector/proc/update_icons()
	cut_overlays()
	if(P)
		add_overlay("ptank")
	if(stat & (NOPOWER|BROKEN))
		return
	if(active)
		add_overlay("on")


/obj/machinery/power/rad_collector/proc/toggle_power()
	active = !active
	if(active)
		icon_state = "ca_on"
		flick("ca_active", src)
	else
		icon_state = "ca"
		flick("ca_deactive", src)
	update_icons()
	return
