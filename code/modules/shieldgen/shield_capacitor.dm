
//---------- shield capacitor
//pulls energy out of a power net and charges an adjacent generator

/obj/machinery/shield_capacitor
	name = "shield capacitor"
	desc = "A machine that charges a shield generator."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "capacitor"
	var/active = 0
	density = TRUE
	var/stored_charge = 0	//not to be confused with power cell charge, this is in Joules
	var/last_stored_charge = 0
	var/time_since_fail = 100
	var/max_charge = 8e6	//8 MJ
	var/max_charge_rate = 400000	//400 kW
	var/locked = 0
	use_power = USE_POWER_OFF //doesn't use APC power
	var/charge_rate = 100000	//100 kW
	var/obj/machinery/shield_gen/owned_gen
	interact_offline = TRUE

/obj/machinery/shield_capacitor/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/climbable)
	AddElement(/datum/element/rotatable)

/obj/machinery/shield_capacitor/advanced
	name = "advanced shield capacitor"
	desc = "A machine that charges a shield generator.  This version can store, input, and output more electricity."
	max_charge = 12e6
	max_charge_rate = 600000

/obj/machinery/shield_capacitor/emag_act(remaining_charges, mob/user)
	if(prob(75))
		src.locked = !src.locked
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
		. = 1
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(5, 1, src)
	s.start()

/obj/machinery/shield_capacitor/attackby(obj/item/W, mob/user)

	if(istype(W, /obj/item/card/id))
		var/obj/item/card/id/C = W
		if((ACCESS_CAPTAIN in C.GetAccess()) || (ACCESS_SECURITY in C.GetAccess()) || (ACCESS_ENGINE in C.GetAccess()))
			src.locked = !src.locked
			to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
		else
			to_chat(user, span_red("Access denied."))
	else
		..()

/obj/machinery/shield_capacitor/wrench_act(mob/user, obj/item/W)
	anchored = !anchored
	playsound(src, W.usesound, 75, 1)
	src.visible_message(span_blue("[icon2html(src,viewers(src))] [src] has been [anchored ? "bolted to the floor" : "unbolted from the floor"] by [user]."))

	if(anchored)
		START_MACHINE_PROCESSING(src)
		spawn(0)
			for(var/obj/machinery/shield_gen/gen in range(1, src))
				if(get_dir(src, gen) == src.dir)
					owned_gen = gen
					LAZYOR(owned_gen.capacitors, src)
	else
		if(owned_gen && (src in owned_gen.capacitors))
			LAZYREMOVE(owned_gen.capacitors, src)
		owned_gen = null
	return ITEM_INTERACT_SUCCESS

/obj/machinery/shield_capacitor/attack_hand(mob/user)
	if(stat & (BROKEN))
		return
	tgui_interact(user)

/obj/machinery/shield_capacitor/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShieldCapacitor", name)
		ui.open()

/obj/machinery/shield_capacitor/tgui_status(mob/user)
	if(stat & BROKEN)
		return STATUS_CLOSE
	return ..()

/obj/machinery/shield_capacitor/tgui_data(mob/user)
	var/list/data = list()

	data["active"] = active
	data["time_since_fail"] = time_since_fail
	data["stored_charge"] = stored_charge
	data["max_charge"] = max_charge
	data["charge_rate"] = charge_rate
	data["max_charge_rate"] = max_charge_rate

	return data

/obj/machinery/shield_capacitor/process()
	if (!anchored)
		active = 0
		return PROCESS_KILL

	//see if we can connect to a power net.
	var/datum/powernet/PN
	var/turf/T = get_turf(src)
	var/obj/structure/cable/C = T.get_cable_node()
	if (C && anchored) //Make sure its anchored too.
		PN = C.get_powernet()

	if (PN)
		var/power_draw = between(0, max_charge - stored_charge, charge_rate) //what we are trying to draw
		power_draw = PN.draw_power(power_draw) //what we actually get
		stored_charge += power_draw
		if(power_draw <= 0 && stored_charge < max_charge)
			sleep_until_keys(list(REACT_KEY_POWERNET, REACT_ID(PN), REACT_POWERNET_RATE|REACT_POWERNET_STATE))
			return PROCESS_KILL
	else
		return PROCESS_KILL

	time_since_fail++
	if(stored_charge < last_stored_charge)
		time_since_fail = 0 //losing charge faster than we can draw from PN
	last_stored_charge = stored_charge
	if(stored_charge >= max_charge)
		stored_charge = max_charge
		return PROCESS_KILL

/obj/machinery/shield_capacitor/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("toggle")
			if(!active && !anchored)
				to_chat(ui.user, span_red("The [src] needs to be firmly secured to the floor first."))
				return
			active = !active
			if(stored_charge < max_charge)
				START_MACHINE_PROCESSING(src)
			. = TRUE
		if("charge_rate")
			charge_rate = clamp(text2num(params["rate"]), 10000, max_charge_rate)
			if(stored_charge < max_charge)
				START_MACHINE_PROCESSING(src)
			. = TRUE

/obj/machinery/shield_capacitor/power_change()
	if(stat & BROKEN)
		icon_state = "broke"
	else
		..()


// === merged from shield_capacitor_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/shield_capacitor
	icon = 'icons/obj/machines/shielding.dmi'

/// Audit: a sleeping capacitor must be full or have nothing to draw from.
/obj/machinery/shield_capacitor/react_sleep_violation()
	if(!asleep_on_keys() || !anchored || stored_charge >= max_charge)
		return null
	var/turf/T = get_turf(src)
	var/obj/structure/cable/C = T?.get_cable_node()
	var/datum/powernet/PN = C?.get_powernet()
	if(PN && PN.avail - PN.load > 0)
		return "asleep below full charge on a grid with [PN.avail - PN.load] W spare"
	return null
