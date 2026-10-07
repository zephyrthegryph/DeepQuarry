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
	var/icon_update_tick = 0	// Used to rebuild the overlay only once every 10 ticks
	var/charging = 0

	var/charging_power			// W. Power rating used for charging the cyborg. 120 kW if un-upgraded
	var/restore_power_active	// W. Power drawn from APC when an occupant is charging. 40 kW if un-upgraded
	var/restore_power_passive	// W. Power drawn from APC when idle. 7 kW if un-upgraded
	var/weld_rate = 0			// How much brute damage is repaired per tick
	var/wire_rate = 0			// How much burn damage is repaired per tick

	var/weld_power_use = 2300	// power used per point of brute damage repaired. 2.3 kW ~ about the same power usage of a handheld arc welder
	var/wire_power_use = 500	// power used per point of burn damage repaired.

/// The internal buffer cell (the station steps only while it has one).
/obj/machinery/recharge_station/var/obj/item/cell/cell
/datum/scheduler_field_definition/obj/machinery/recharge_station/cell
	of = /obj/machinery/recharge_station
	field = "cell"
	channel = CHANGE_MACHINE_SETTINGS

/// Not BROKEN (an unpowered station still runs off its cell, so operable() is too strict).
/obj/machinery/recharge_station/proc/unbroken()
	return !broken_now()

// ALLOW(init/INSTANCE_STATE): takes its built parts and the high-capacity cell among them
/obj/machinery/recharge_station/Initialize(mapload)
	. = ..()
	default_apply_parts()
	rel_set(src, nameof(cell), default_use_hicell()) // component_parts owns the cell; this is a view onto it
	update_icon()

/// Sealed occupant slot (C8a, containment.md §10).
/datum/om/relation/slot/occupant/recharge_station
	holder = /obj/machinery/recharge_station
	slot_id = OCCUPANT_SLOT_RECHARGE_STATION
	name = "recharge station"
	// The slot IS the occupant: read it with SLOT_ITEM(holder, slot_id).

/obj/machinery/recharge_station/proc/has_cell_power()
	return cell && cell.percent() > 0

/obj/machinery/recharge_station/proc/work_step(datum/act/timer/A)
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_RECHARGE_STATION)
	if((power_lost()) && !has_cell_power()) // No power and cell is dead.
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
	if(!power_lost())
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

	if((occupant || recharge_amount) && !icon_update_tick) // redraw the gauge once every 10 steps
		update_icon()

//Processes the occupant, drawing from the internal power cell if needed.
/obj/machinery/recharge_station/proc/process_occupant()
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_RECHARGE_STATION)
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
		var/list/demand = R.treatment_demand(/datum/diagnostic_profile/robot_analyzer)
		if(weld_rate && demand?[TREAT_PLATING_REPAIR] && cell.checked_use(weld_power_use * weld_rate * CELLRATE))
			R.mend(TREAT_PLATING_REPAIR, weld_rate)
		if(wire_rate && demand?[TREAT_WIRING_REPAIR] && cell.checked_use(wire_power_use * wire_rate * CELLRATE))
			R.mend(TREAT_WIRING_REPAIR, wire_rate)

	else if(ispAI(occupant))
		var/mob/living/silicon/pai/P = occupant

		if(P.nutrition < 400)
			P.set_nutrition(min(P.nutrition+10, 400))
			cell.use(7000/450*10)

	else if(ishuman(occupant))
		var/mob/living/carbon/human/H = occupant

		if(HAS_SYNTHETIC_BIOLOGY(H))
			// Run diagnostics: clears processor / system faults on synthetic parts.
			if(H.is_injured())
				H.mend(TREAT_SYSTEM_RESTORE, rand(1,3))

			// Also recharge their internal battery.
			if(HAS_SYNTHETIC_BIOLOGY(H) && H.nutrition < 500)
				H.set_nutrition(min(H.nutrition+(10*(1-min(H.species.synthetic_food_coeff, 0.9))), 500))
				cell.use(7000/450*10)

			// And clear up radiation
			if(H.radiation > 0 || H.accumulated_rads > 0)
				H.purge_radiation(25)

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
						own_clear(rigchest, nameof(rigchest.breaches), OWN_DELETE)
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

/// Requirement (was REQ_* is_vacant): the legacy check answers TRUE to pass.
/obj/machinery/recharge_station/proc/is_vacant_holds(datum/act/op/A)
	var/answer = is_vacant(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Requirement (was REQ_* grab_holds_living): the legacy check answers TRUE to pass.
/obj/machinery/recharge_station/proc/grab_holds_living_holds(datum/act/op/A)
	var/answer = grab_holds_living(A.actor, src, A.held)
	return !istext(answer) && !!answer

/obj/machinery/recharge_station/proc/is_vacant(mob/actor, atom/target, obj/item/held)
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_RECHARGE_STATION)
	return !occupant

/obj/machinery/recharge_station/proc/interaction_part_replacement_impl(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(default_part_replacement(user, held))
		return OP_OK
	return OP_DECLINE

/obj/machinery/recharge_station/proc/grab_holds_living(mob/actor, atom/target, obj/item/held)
	if(get_dist(src, actor) >= 2)
		return FALSE
	var/obj/item/grab/G = held
	return isliving(G?.grab_target())

/obj/machinery/recharge_station/proc/interaction_insert_grab(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	var/obj/item/grab/G = held
	var/mob/living/M = G?.grab_target()
	consume(held, user)
	go_in(M)
	return OP_DECLINE

/obj/machinery/recharge_station/proc/interaction_drag_insert(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/dropping = A.held
	var/mob/target = dropping
	if(user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user))
		return OP_OK
	go_in(target)
	return OP_OK

/obj/machinery/recharge_station/proc/interaction_eject(datum/act/op/A)
	var/mob/user = A.actor
	go_out()
	add_fingerprint(user)
	return TRUE

/obj/machinery/recharge_station/proc/interaction_enter(datum/act/op/A)
	var/mob/user = A.actor
	go_in(user)
	return TRUE

/// Nobody is charging inside (an occupant keeps the panel shut and the frame whole: the click is taken and nothing happens).
/obj/machinery/recharge_station/proc/station_empty(datum/act/op/A)
	return !slot_occupant(OCCUPANT_SLOT_RECHARGE_STATION)

/obj/machinery/recharge_station/RefreshParts()
	..()
	work_start(src)
	var/man_rating = 0
	var/cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	man_rating += get_part_rating(/obj/item/stock_parts/manipulator)
	materialize_parts()
	rel_set(src, nameof(cell), locate_in_list(component_parts, /obj/item/cell)) // component_parts owns the cell; this is a view onto it

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

/// The charge gauge overlay for the occupant's charge.
/obj/machinery/recharge_station/proc/build_overlays()
	switch(round(chargepercentage()))
		if(1 to 20)
			return "statn_c0"
		if(21 to 40)
			return "statn_c20"
		if(41 to 60)
			return "statn_c40"
		if(61 to 80)
			return "statn_c60"
		if(81 to 98)
			return "statn_c80"
		if(99 to 110)
			return "statn_c100"

DECLARE_APPEARANCE_PROC(/obj/machinery/recharge_station, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/recharge_station/appearance_overlays()
	. = list()
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_RECHARGE_STATION)
	. += ..()
	if(broken_now())
		icon_state = "borgcharger0"
		return .

	if(occupant)
		if((power_lost()) && !has_cell_power())
			icon_state = "borgcharger2"
		else
			icon_state = "borgcharger1"
	else
		icon_state = "borgcharger0"

	. += build_overlays()

CAPABILITIES(/obj/machinery/recharge_station)
	ref_one(nameof(cell), /obj/item/cell) // component_parts owns the cell
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(cell), gate = PROC_REF(unbroken), wakes_on = list(STAT_OPERABLE, nameof(cell)), unpowered = TRUE)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	extend("machine_panel", needs(req(PROC_REF(station_empty), silent = TRUE)))
	extend("machine_panel_close", needs(req(PROC_REF(station_empty), silent = TRUE)))
	extend("machine_deconstruct", needs(req(PROC_REF(station_empty), silent = TRUE)))
	op("recharge_station_part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), when(req(PROC_REF(is_vacant_holds))), then(PROC_REF(interaction_part_replacement_impl)))
	op("recharge_station_insert_grab", item(/obj/item/grab), priority(OP_PRIORITY_DEFAULT - 1), label("Put in recharger"), when(req(PROC_REF(is_vacant_holds))), when(req(PROC_REF(grab_holds_living_holds))), then(PROC_REF(interaction_insert_grab)))
	op("recharge_station_drag_insert", item(/mob), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Put in recharger"), then(PROC_REF(interaction_drag_insert)))
	op("recharge_station_eject", menu(), label("Eject Recharger"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_eject)))
	op("recharge_station_enter", menu(), label("Enter Recharger"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_enter)))

/// Something walked into it (the bump action's notice).
/obj/machinery/recharge_station/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/mob/living/L = N.bumper
	go_in(L)

/obj/machinery/recharge_station/proc/go_in(mob/living/L)
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_RECHARGE_STATION)

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
		if(!move_into(src, OCCUPANT_SLOT_RECHARGE_STATION, R))
			return
		work_start(src)
		update_icon()
		return 1

	else if(ispAI(L))
		var/mob/living/silicon/pai/P = L

		if(P.incapacitated())
			return

		add_fingerprint(P)
		if(!move_into(src, OCCUPANT_SLOT_RECHARGE_STATION, P))
			return
		work_start(src)
		update_icon()
		return 1

	else if(istype(L,  /mob/living/carbon/human))
		var/mob/living/carbon/human/H = L
		if(HAS_SYNTHETIC_BIOLOGY(H) || H.wearing_rig)
			add_fingerprint(H)
			if(!move_into(src, OCCUPANT_SLOT_RECHARGE_STATION, H))
				return
			work_start(src)
			update_icon()
			return 1
	else
		return

/obj/machinery/recharge_station/proc/go_out()
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_RECHARGE_STATION)
	if(!occupant)
		return
	slot_remove(occupant, get_turf(src))
	update_icon()

/obj/machinery/recharge_station/power_change()
	. = ..()
	if(.)
		work_start(src)

/obj/machinery/recharge_station/ghost_pod_recharger
	name = "drone pod"
	desc = "This is a pod which used to contain a drone... Or maybe it still does?"
	icon = 'icons/obj/structures.dmi'

DECLARE_APPEARANCE_PROC(/obj/machinery/recharge_station/ghost_pod_recharger, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/recharge_station/ghost_pod_recharger/appearance_overlays()
	. = list()
	var/mob/occupant = src?.slot_item(OCCUPANT_SLOT_RECHARGE_STATION)
	. += ..()
	if(broken_now())
		icon_state = "borg_pod_closed"
		desc = "It appears broken..."
		return .

	if(occupant)
		if((power_lost()) && !has_cell_power())
			icon_state = "borg_pod_closed"
			desc = "It appears to be unpowered..."
		else
			icon_state = "borg_pod_closed"
	else
		icon_state = "borg_pod_opened"

	. += build_overlays()

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/recharge_station/step_start_condition()
	return TRUE // tops up its buffer
