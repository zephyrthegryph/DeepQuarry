/obj/machinery/recharge_station
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "cyborg recharging station"
	desc = "A heavy duty rapid charging system, designed to quickly recharge cyborg power reserves."
	icon = 'icons/obj/objects.dmi'
	icon_state = "borgcharger0"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	flags = REMOTEVIEW_ON_ENTER
	circuit = /obj/item/circuitboard/recharge_station
	use_power = USE_POWER_IDLE
	idle_power_usage = 50
	var/mob/occupant = null
	var/obj/item/cell/cell = null
	var/icon_update_tick = 0	// Used to rebuild the overlay only once every 10 ticks
	var/charging = 0

	var/charging_power			// W. Power rating used for charging the cyborg. 120 kW if un-upgraded
	var/restore_power_active	// W. Power drawn from APC when an occupant is charging. 40 kW if un-upgraded
	var/restore_power_passive	// W. Power drawn from APC when idle. 7 kW if un-upgraded
	var/weld_rate = 0			// How much brute damage is repaired per tick
	var/wire_rate = 0			// How much burn damage is repaired per tick

	var/weld_power_use = 2300	// power used per point of brute damage repaired. 2.3 kW ~ about the same power usage of a handheld arc welder
	var/wire_power_use = 500	// power used per point of burn damage repaired.

/obj/machinery/recharge_station/Initialize(mapload)
	. = ..()
	default_apply_parts()
	cell = default_use_hicell()
	update_icon()

/obj/machinery/recharge_station/proc/has_cell_power()
	return cell && cell.percent() > 0

/obj/machinery/recharge_station/process()
	if(stat & (BROKEN))
		return PROCESS_KILL
	if(!cell) // Shouldn't be possible, but sanity check
		return PROCESS_KILL

	if((stat & NOPOWER) && !has_cell_power()) // No power and cell is dead.
		if(icon_update_tick)
			icon_update_tick = 0 //just rebuild the overlay once more only
			update_icon()
		return PROCESS_KILL

	// With no occupant and a full buffer there is no time-dependent work. Power
	// changes, part replacement, or somebody entering explicitly wake the station.
	if(!occupant && cell.fully_charged())
		return PROCESS_KILL

	//First, draw from the internal power cell to recharge/repair/etc the occupant
	if(occupant)
		process_occupant()

	//Then, if external power is available, recharge the internal cell
	var/recharge_amount = 0
	if(!(stat & NOPOWER))
		// Calculating amount of power to draw
		recharge_amount = (occupant ? restore_power_active : restore_power_passive) * CELLRATE

		recharge_amount = cell.give(recharge_amount)
		use_power(recharge_amount / CELLRATE)
	else
		// Since external power is offline, draw operating current from the internal cell
		cell.use(get_power_usage() * CELLRATE)

	if(icon_update_tick >= 10)
		icon_update_tick = 0
	else
		icon_update_tick++

	if(occupant || recharge_amount)
		update_icon()

//Processes the occupant, drawing from the internal power cell if needed.
/obj/machinery/recharge_station/proc/process_occupant()
	if(isrobot(occupant))
		var/mob/living/silicon/robot/R = occupant
		var/overcharged = FALSE
		if(R.cell.maxcharge < R.cell.charge)
			overcharged = TRUE
		if(R.module && !overcharged)
			R.module.respawn_consumable(R, charging_power * CELLRATE / 250) //consumables are magical, apparently
		if(R.cell && !R.cell.fully_charged() && !overcharged)
			var/diff = min(R.cell.maxcharge - R.cell.charge, charging_power * CELLRATE) // Capped by charging_power / tick
			var/charge_used = cell.use(diff)
			R.add_power(ROBOT_CELL_JOULES(charge_used), src)

		//Lastly, attempt to repair the cyborg if enabled
		if(weld_rate && R.injury_load(INJURY_CATEGORY_PHYSICAL) && cell.checked_use(weld_power_use * weld_rate * CELLRATE))
			R.mend(TREAT_PLATING_REPAIR, weld_rate)
		if(wire_rate && R.injury_load(INJURY_CATEGORY_THERMAL) && cell.checked_use(wire_power_use * wire_rate * CELLRATE))
			R.mend(TREAT_WIRING_REPAIR, wire_rate)

	else if(ispAI(occupant))
		var/mob/living/silicon/pai/P = occupant

		if(P.nutrition < 400)
			P.nutrition = min(P.nutrition+10, 400)
			cell.use(7000/450*10)

	else if(ishuman(occupant))
		var/mob/living/carbon/human/H = occupant

		if(H.isSynthetic())
			// Run diagnostics: clears processor / system faults on synthetic parts.
			if(H.is_injured())
				H.mend(TREAT_SYSTEM_RESTORE, rand(1,3))

			// Also recharge their internal battery.
			if(H.isSynthetic() && H.nutrition < 500)
				H.nutrition = min(H.nutrition+(10*(1-min(H.species.synthetic_food_coeff, 0.9))), 500)
				cell.use(7000/450*10)

			// And clear up radiation
			if(H.radiation > 0 || H.accumulated_rads > 0)
				H.radiation = max(H.radiation - 25, 0)
				H.accumulated_rads = max(H.accumulated_rads - 25, 0)

		if(H.wearing_rig) // stepping into a borg charger to charge your rig and fix your shit
			var/obj/item/rig/wornrig = H.get_rig()
			if(wornrig) // just to make sure
				for(var/obj/item/rig_module/storedmod in wornrig.installed_modules)
					if(weld_rate && storedmod.damage && cell.checked_use(weld_power_use * weld_rate * CELLRATE))
						to_chat(H, span_notice("[storedmod] is repaired!"))
						storedmod.damage = 0
				if(wornrig.chest)
					var/obj/item/clothing/suit/space/rig/rigchest = wornrig.chest
					if(weld_rate && rigchest.damage && cell.checked_use(weld_power_use * weld_rate * CELLRATE))
						rigchest.breaches = list()
						rigchest.calc_breach_damage()
						to_chat(H, span_notice("[rigchest] is repaired!"))
				if(wornrig.cell)
					var/obj/item/cell/rigcell = wornrig.cell
					var/diff = min(rigcell.maxcharge - rigcell.charge, charging_power * CELLRATE) // Capped by charging_power / tick
					var/charge_used = cell.use(diff)
					rigcell.give(charge_used)

/obj/machinery/recharge_station/examine(mob/user)
	. = ..()
	. += "The charge meter reads: [round(chargepercentage())]%"

/obj/machinery/recharge_station/proc/chargepercentage()
	if(!cell)
		return 0
	return cell.percent()

/obj/machinery/recharge_station/relaymove(mob/user as mob)
	if(user.stat)
		return
	go_out()
	return

/obj/machinery/recharge_station/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/recharge_station_part_replacement,
		/datum/interaction/machine_item/recharge_station_insert_grab,
		/datum/interaction/machine_drag/recharge_station_insert,
		/datum/interaction/machine_verb/recharge_station_eject,
		/datum/interaction/machine_verb/recharge_station_enter,
	)
	..()

/datum/interaction/machine_item/recharge_station_part_replacement
	id = "recharge_station_part_replacement"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/recharge_station/proc/is_vacant, null))
	effect = /obj/machinery/recharge_station/proc/interaction_part_replacement_impl

/obj/machinery/recharge_station/proc/is_vacant(mob/actor, atom/target, obj/item/held)
	return !occupant

/obj/machinery/recharge_station/proc/interaction_part_replacement_impl(mob/user, obj/item/held, datum/interaction/interaction)
	return default_part_replacement(user, held) ? TRUE : FALSE

/datum/interaction/machine_item/recharge_station_insert_grab
	id = "recharge_station_insert_grab"
	name = "Put in recharger"
	held_type = /obj/item/grab
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/recharge_station/proc/is_vacant, null), REQ_ON(PRED_TARGET, /obj/machinery/recharge_station/proc/grab_holds_living, null))
	effect = /obj/machinery/recharge_station/proc/interaction_insert_grab

/obj/machinery/recharge_station/proc/grab_holds_living(mob/actor, atom/target, obj/item/held)
	if(get_dist(src, actor) >= 2)
		return FALSE
	var/obj/item/grab/G = held
	return isliving(G.affecting)

/obj/machinery/recharge_station/proc/interaction_insert_grab(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/grab/G = held
	var/mob/living/M = G.affecting
	qdel(held)
	go_in(M)
	return FALSE

/datum/interaction/machine_drag/recharge_station_insert
	id = "recharge_station_drag_insert"
	name = "Put in recharger"
	held_type = /mob
	effect = /obj/machinery/recharge_station/proc/interaction_drag_insert

/obj/machinery/recharge_station/proc/interaction_drag_insert(mob/user, atom/movable/dropping, datum/interaction/interaction)
	var/mob/target = dropping
	if(user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user))
		return TRUE
	go_in(target)
	return TRUE

/datum/interaction/machine_verb/recharge_station_eject
	id = "recharge_station_eject"
	name = "Eject Recharger"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/recharge_station/proc/interaction_eject

/obj/machinery/recharge_station/proc/interaction_eject(mob/user, obj/item/held, datum/interaction/interaction)
	go_out()
	add_fingerprint(user)
	return TRUE

/datum/interaction/machine_verb/recharge_station_enter
	id = "recharge_station_enter"
	name = "Enter Recharger"
	category = INTERACTION_CAT_INSERT
	effect = /obj/machinery/recharge_station/proc/interaction_enter

/obj/machinery/recharge_station/proc/interaction_enter(mob/user, obj/item/held, datum/interaction/interaction)
	go_in(user)
	return TRUE

/obj/machinery/recharge_station/screwdriver_act(mob/user, obj/item/tool)
	return occupant ? ITEM_INTERACT_BLOCKING : ..()

/obj/machinery/recharge_station/crowbar_act(mob/user, obj/item/tool)
	return occupant ? ITEM_INTERACT_BLOCKING : ..()

/obj/machinery/recharge_station/RefreshParts()
	..()
	START_MACHINE_PROCESSING(src)
	var/man_rating = 0
	var/cap_rating = 0

	for(var/obj/item/stock_parts/P in component_parts)
		if(istype(P, /obj/item/stock_parts/capacitor))
			cap_rating += P.rating
		if(istype(P, /obj/item/stock_parts/manipulator))
			man_rating += P.rating
	cell = locate(/obj/item/cell) in component_parts

	charging_power = 40000 + 40000 * cap_rating
	restore_power_active = 10000 + 15000 * cap_rating
	restore_power_passive = 5000 + 1000 * cap_rating
	weld_rate = max(0, man_rating - 3)
	wire_rate = max(0, man_rating - 5)

	desc = initial(desc)
	desc += " Uses a dedicated internal power cell to deliver [charging_power]W when in use."
	if(weld_rate)
		desc += "<br>It is capable of repairing structural damage."
	if(wire_rate)
		desc += "<br>It is capable of repairing burn damage."

/obj/machinery/recharge_station/proc/build_overlays()
	cut_overlays()
	switch(round(chargepercentage()))
		if(1 to 20)
			add_overlay("statn_c0")
		if(21 to 40)
			add_overlay("statn_c20")
		if(41 to 60)
			add_overlay("statn_c40")
		if(61 to 80)
			add_overlay("statn_c60")
		if(81 to 98)
			add_overlay("statn_c80")
		if(99 to 110)
			add_overlay("statn_c100")

/obj/machinery/recharge_station/update_icon()
	..()
	if(stat & BROKEN)
		icon_state = "borgcharger0"
		return

	if(occupant)
		if((stat & NOPOWER) && !has_cell_power())
			icon_state = "borgcharger2"
		else
			icon_state = "borgcharger1"
	else
		icon_state = "borgcharger0"

	if(icon_update_tick == 0)
		build_overlays()

/obj/machinery/recharge_station/Bumped(mob/living/L)
	go_in(L)

/obj/machinery/recharge_station/proc/go_in(mob/living/L)

	if(occupant)
		return

	if(isrobot(L))
		var/mob/living/silicon/robot/R = L

		if(R.incapacitated())
			return

		if(!R.cell)
			return

		if(istype(R, /mob/living/silicon/robot/platform))
			to_chat(R, span_warning("You are too large to fit into \the [src]."))
			return

		add_fingerprint(R)
		R.forceMove(src)
		occupant = R
		START_MACHINE_PROCESSING(src)
		update_icon()
		return 1

	else if(ispAI(L))
		var/mob/living/silicon/pai/P = L

		if(P.incapacitated())
			return

		add_fingerprint(P)
		P.forceMove(src)
		occupant = P
		START_MACHINE_PROCESSING(src)
		update_icon()
		return 1

	else if(istype(L,  /mob/living/carbon/human))
		var/mob/living/carbon/human/H = L
		if(H.isSynthetic() || H.wearing_rig)
			add_fingerprint(H)
			H.forceMove(src)
			occupant = H
			START_MACHINE_PROCESSING(src)
			update_icon()
			return 1
	else
		return

/obj/machinery/recharge_station/proc/go_out()
	if(!occupant)
		return
	occupant.forceMove(get_turf(src))
	occupant = null
	update_icon()

/obj/machinery/recharge_station/power_change()
	. = ..()
	if(.)
		START_MACHINE_PROCESSING(src)

/obj/machinery/recharge_station/ghost_pod_recharger
	name = "drone pod"
	desc = "This is a pod which used to contain a drone... Or maybe it still does?"
	icon = 'icons/obj/structures.dmi'

/obj/machinery/recharge_station/ghost_pod_recharger/update_icon()
	..()
	if(stat & BROKEN)
		icon_state = "borg_pod_closed"
		desc = "It appears broken..."
		return

	if(occupant)
		if((stat & NOPOWER) && !has_cell_power())
			icon_state = "borg_pod_closed"
			desc = "It appears to be unpowered..."
		else
			icon_state = "borg_pod_closed"
	else
		icon_state = "borg_pod_opened"

	if(icon_update_tick == 0)
		build_overlays()
