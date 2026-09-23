// the power cell
// charge from 0 to 100%
// fits in APC to provide backup power

/obj/item/cell
	material_template = /datum/material_template/cell
	material_total = 2 * SHEET_MATERIAL_AMOUNT
	name = "power cell"
	desc = "A rechargable electrochemical power cell."
	icon = 'icons/obj/power_cells.dmi' // swap to 'icons/obj/power_cells_.dmi' for new sprites. // Enable new sprites
	icon_state = "b_st"
	item_state = "cell"
	force = 5.0
	throwforce = 5.0
	throw_speed = 3
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	var/static/cell_uid = 1		// Unique ID of this power cell. Used to reduce bunch of uglier code in nanoUI.
	var/c_uid
	var/charge = 1000	// maximum charge on spawn
	var/maxcharge = 1000
	var/rigged = 0		// true if rigged to explode
	var/detonation_pending = FALSE
	var/minor_fault = 0 //If not 100% reliable, it will build up faults.
	var/self_recharge = FALSE // If true, the cell will recharge itself.
	var/charge_amount = 25 // How much power to give, if self_recharge is true.  The number is in absolute cell charge, as it gets divided by CELLRATE later.
	var/last_use = 0 // A tracker for use in self-charging
	var/connector_type = "standard" //What connector sprite to use when in a cell charger, null if no connectors
	var/charge_delay = 0  // How long it takes for the cell to start recharging after last use
	var/robot_durability = 50
	/// Material-derived resistance to EMP charge loss, as a percentage.
	var/material_emp_resistance = 0
	var/material_discharge_credit
	var/material_discharge_updated
	/// Hysteretic physical state. A quenched conductor must cool meaningfully
	/// below its transition before it can carry enhanced output again.
	var/material_superconducting = FALSE
	var/material_quenched = FALSE
	var/material_feedback_cooldown = 0


	drop_sound = 'sound/items/drop/component.ogg'
	pickup_sound = 'sound/items/pickup/component.ogg'

	// Overlay stuff.
	var/standard_overlays = TRUE
	var/last_overlay_state = null // Used to optimize update_icon() calls.

/obj/item/cell/Initialize(mapload)
	. = ..()
	// A cell's temperature and electrical phase are functional state even for
	// the standard construction. Unlike idle machine housings, cells therefore
	// always need a service datum; it sleeps dependency-driven when stable.
	apply_blueprint_effects()
	enable_material_service()
	AddElement(/datum/element/electrovoreable)
	c_uid = cell_uid++
	update_icon()
	if(self_recharge)
		START_PROCESSING(SSobj, src)

/obj/item/cell/Destroy()
	if(self_recharge)
		STOP_PROCESSING(SSobj, src)
	// Cells are normally owned through loc, but APCs also keep an explicit typed
	// reference.  A blast may delete the cell without deleting its APC first.
	if(istype(loc, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/holder = loc
		if(holder.cell == src)
			holder.cell = null
	return ..()

/obj/item/cell/get_cell()
	return src

/obj/item/cell/process()
	if(self_recharge)
		if(charge >= maxcharge)
			return PROCESS_KILL
		if(world.time >= last_use + charge_delay)
			give(charge_amount)
			// TGMC Ammo HUD - Update the HUD every time we're called to recharge.
			if(istype(loc, /obj/item/gun/energy)) // Are we in a gun currently?
				var/obj/item/gun/energy/gun = loc
				var/mob/living/user = gun.loc
				if(istype(user))
					user?.hud_used.update_ammo_hud(user, gun) // Update the HUD
	else
		return PROCESS_KILL

/obj/item/cell/drain_power(drain_check, surge, power = 0)

	if(drain_check)
		return 1

	if(charge <= 0)
		return 0

	var/cell_amt = power * CELLRATE

	return use(cell_amt) / CELLRATE

#define OVERLAY_FULL	2
#define OVERLAY_PARTIAL	1
#define OVERLAY_EMPTY	0

/obj/item/cell/update_icon()
	if(!standard_overlays)
		return
	var/ratio = 0
	if(maxcharge > 0)
		ratio = clamp(round(charge / maxcharge, 0.25) * 100, 0, 100)
	var/new_state = "[icon_state]_[ratio]"
	if(new_state != last_overlay_state)
		cut_overlay(last_overlay_state)
		add_overlay(new_state)
		last_overlay_state = new_state

#undef OVERLAY_FULL
#undef OVERLAY_PARTIAL
#undef OVERLAY_EMPTY

/obj/item/cell/proc/percent()		// return % charge of cell
	var/charge_percent = 0
	if(maxcharge > 0)
		charge_percent = 100.0 * charge / maxcharge
	return charge_percent

/obj/item/cell/proc/fully_charged()
	return (charge == maxcharge)

// checks if the power cell is able to provide the specified amount of charge
/obj/item/cell/proc/check_charge(amount)
	refresh_material_discharge()
	return amount >= 0 && charge >= amount / material_delivery_efficiency(amount) && material_discharge_credit >= amount

/obj/item/cell/proc/refresh_material_discharge()
	if(isnull(material_discharge_credit))
		material_discharge_credit = material_discharge_limit
	else
		material_discharge_credit = min(material_discharge_limit, material_discharge_credit + max(world.time - material_discharge_updated, 0) / 10 * material_discharge_limit)
	material_discharge_updated = world.time

/obj/item/cell/proc/material_delivery_efficiency(amount)
	var/temperature = material_service?.temperature || T20C
	var/current = max(amount / CELLRATE, 0) / MATERIAL_SERVICE_NOMINAL_VOLTAGE
	var/resistance = construction_electrical_resistance(0.1, MATERIAL_CABLE_REFERENCE_AREA, temperature, current / MATERIAL_CABLE_REFERENCE_AREA) || 0
	return 1 / (1 + resistance * current / MATERIAL_SERVICE_NOMINAL_VOLTAGE)

/// Refresh the conductor phase from actual assembly temperature. No predictive
/// UI is involved: the state is discovered through device performance and the
/// physical quench/recovery cues emitted here.
/obj/item/cell/proc/update_superconducting_state(requested_output = 0)
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR)
	if(!conductor?.critical_temperature || !material_service)
		material_superconducting = FALSE
		material_quenched = FALSE
		return FALSE
	var/temperature = material_service.temperature
	var/current_density = max(requested_output / CELLRATE, 0) / MATERIAL_SERVICE_NOMINAL_VOLTAGE / MATERIAL_CABLE_REFERENCE_AREA
	var/within_current = current_density <= conductor.critical_current_density
	if(material_quenched)
		if(temperature <= conductor.critical_temperature - MATERIAL_SUPERCONDUCTING_RECOVERY_MARGIN)
			material_quenched = FALSE
			material_superconducting = within_current
			material_phase_feedback(FALSE)
		else
			material_superconducting = FALSE
		return material_superconducting
	var/was_superconducting = material_superconducting
	material_superconducting = temperature < conductor.critical_temperature && within_current
	if(was_superconducting && !material_superconducting)
		material_quenched = TRUE
		material_phase_feedback(TRUE)
	return material_superconducting

/obj/item/cell/proc/material_phase_feedback(quenching)
	if(world.time < material_feedback_cooldown)
		return
	material_feedback_cooldown = world.time + 2 SECONDS
	var/atom/device = isobj(loc) ? loc : src
	if(quenching)
		device.visible_message(span_warning("[device] snaps with a harsh electrical crack as frost flashes from its casing!"))
		playsound(device, 'sound/effects/sparks4.ogg', 55, TRUE)
	else
		device.visible_message(span_notice("Condensation creeps across [device] as its electrical hum becomes suddenly clean."))

/// Return the strongest output envelope this cell can physically support for
/// one action. Ordinary cells always return 1; superconductors automatically
/// use available current and charge without a player-facing mode switch.
/obj/item/cell/proc/material_output_envelope(base_cost, device_limit = MATERIAL_SUPERCONDUCTING_MAX_OUTPUT)
	if(base_cost <= 0 || device_limit <= 1 || !update_superconducting_state(base_cost))
		return 1
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR)
	var/current_limited_cost = conductor.critical_current_density * MATERIAL_CABLE_REFERENCE_AREA * MATERIAL_SERVICE_NOMINAL_VOLTAGE * CELLRATE
	var/available_cost = min(material_available_output(base_cost * device_limit), current_limited_cost)
	return clamp(available_cost / base_cost, 1, device_limit)

/// Enhanced devices convert a small part of their additional work into heat in
/// the complete cell assembly. This is not conductor resistance; contacts,
/// electrodes, and the powered device itself still produce heat.
/obj/item/cell/proc/material_record_enhanced_output(base_cost, multiplier)
	if(multiplier <= 1 || !material_service)
		return
	material_service.add_heat((base_cost * (multiplier - 1) / CELLRATE) * MATERIAL_SUPERCONDUCTING_OVERDRIVE_HEAT)
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR)
	if(conductor?.critical_temperature && material_service.temperature >= conductor.critical_temperature)
		material_superconducting = FALSE
		material_quenched = TRUE
		material_phase_feedback(TRUE)

/// A deliberately fabricated heat-pump layer spends stored power to move the
/// cell's operating heat into its surroundings. This is the physical consumer
/// for cryogenic/thermoelectric composites: it can hold a conductor below its
/// critical temperature, while the insulation layer controls heat leaking back.
/obj/item/cell/proc/run_material_heat_pump(delivered_charge)
	if(delivered_charge <= 0 || !material_service)
		return 0
	var/datum/material/thermal = material_for_role(MATERIAL_ROLE_THERMAL)
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR)
	if(!thermal?.heat_pump_coefficient || !conductor?.critical_temperature)
		return 0
	var/target_temperature = conductor.critical_temperature - MATERIAL_SUPERCONDUCTING_RECOVERY_MARGIN
	if(material_service.temperature <= target_temperature)
		return 0
	var/available_cooling = (material_service.temperature - target_temperature) * material_service.thermal_mass()
	var/requested_cooling = min(available_cooling, delivered_charge / CELLRATE * thermal.heat_pump_coefficient * 6)
	var/work_joules = requested_cooling / max(thermal.heat_pump_coefficient, 0.1)
	var/work_charge = min(charge, work_joules * CELLRATE)
	var/moved_heat = work_charge / CELLRATE * thermal.heat_pump_coefficient
	if(moved_heat <= 0)
		return 0
	charge -= work_charge
	material_service.add_heat(-moved_heat)
	var/turf/location = get_turf(src)
	var/datum/gas_mixture/ambient = location?.return_air()
	ambient?.add_thermal_energy(moved_heat + work_charge / CELLRATE)
	material_service.input_joules += work_charge / CELLRATE
	material_service.loss_joules += work_charge / CELLRATE
	return moved_heat

/// A conservative preflight budget for consumers that perform physical work
/// before debiting the cell. Repeated callers share the same discharge credit.
/obj/item/cell/proc/material_available_output(requested)
	refresh_material_discharge()
	requested = max(0, min(requested, material_discharge_credit))
	return min(requested, charge * material_delivery_efficiency(requested))

// Returns how much charge is missing from the cell, useful to make sure not overdraw from the grid when recharging.
/obj/item/cell/proc/amount_missing()
	return max(maxcharge - charge, 0)

// use power from a cell, returns the amount actually used
/obj/item/cell/proc/use(amount, update_appearance = TRUE)
	if(rigged && amount > 0)
		explode()
		return 0
	refresh_material_discharge()
	if(amount > 0)
		material_service_event(MATERIAL_EVENT_ELECTRICAL, amount / max(material_discharge_limit, 1))
	material_service?.advance()
	if(QDELETED(src))
		return 0
	amount = material_cell_use_cost(amount)
	amount = clamp(amount, 0, material_discharge_credit)
	var/efficiency = material_delivery_efficiency(amount)
	var/used = min(charge * efficiency, amount)
	var/debited = used / efficiency
	var/charge_before = charge
	charge = max(0, min(charge - used, charge - debited))
	// BYOND uses single-precision numbers. Account the represented change in
	// stored charge, not a pre-rounding estimate of that change.
	debited = charge_before - charge
	if(debited < used)
		// Pay a representable charge step rather than reporting an affordable
		// fractional action as failed after already debiting the cell. Any
		// rounding surplus is included in the actual waste-heat accounting.
		charge = max(0, charge - max(charge_before * MATERIAL_CHARGE_FLOAT_EPSILON, MATERIAL_CHARGE_FLOAT_EPSILON))
		debited = charge_before - charge
	used = min(used, debited)
	material_discharge_credit -= used
	if(material_service)
		material_service.input_joules += debited / CELLRATE
		material_service.output_joules += used / CELLRATE
		material_service.loss_joules += (debited - used) / CELLRATE
		material_service.add_heat((debited - used) / CELLRATE)
		run_material_heat_pump(used)
	update_superconducting_state(amount)
	last_use = world.time
	if(used && self_recharge)
		START_PROCESSING(SSobj, src)
	if(used && istype(loc, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/A = loc
		if(!(A in SSmachines.processing_machines))
			A.wake_for_power_dependency()
	if(update_appearance)
		update_icon()
	return used

// Checks if the specified amount can be provided. If it can, it removes the amount
// from the cell and returns 1. Otherwise does nothing and returns 0.
/obj/item/cell/proc/checked_use(amount)
	if(!check_charge(amount))
		return 0
	return use(amount) >= amount

// recharge the cell
/obj/item/cell/proc/give(amount, update_appearance = TRUE)
	if(rigged && amount > 0)
		explode()
		return 0

	var/amount_used = clamp(amount, 0, maxcharge - charge)
	charge += amount_used
	if(amount_used && istype(loc, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/A = loc
		if(!(A in SSmachines.processing_machines))
			A.wake_for_power_dependency()
	if(update_appearance)
		update_icon()
		if(loc)
			loc.update_icon()
	return amount_used

/// Recharges the cell over time. 100 per second multiplied by the multiplier.
/obj/item/cell/proc/gradual_charge(iterations, multiplier, sparks, mob/living/user)
	var/charged_object = src
	if(!multiplier || iterations <= 0)
		return
	if(user) //If we have a user, time to check to make sure they're adjacent/holding us!
		if(istype(loc, /obj/machinery/power/apc)) //We're in an APC!
			charged_object = loc
		if(loc != user && !(user in orange(1,charged_object))) //If we have a user fed to us, they need to hold us or be in range of us.
			if(loc.loc && loc.loc != user) //Are we inside of something the user is holding?
				return
	charge += 100 * multiplier
	if(charge > maxcharge)
		charge = maxcharge
	if(sparks)
		var/T = get_turf(src)
		new /obj/effect/effect/sparks(T)
	update_icon()
	iterations--
	addtimer(CALLBACK(src, PROC_REF(gradual_charge), iterations, multiplier, sparks, user), 1 SECOND, TIMER_DELETE_ME)


/obj/item/cell/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "It has a power rating of [maxcharge]."
		. += "The charge meter reads [round(src.percent() )]%."

/obj/item/cell/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(isrobot(M))
		var/mob/living/silicon/robot/target = M
		if(target.opened)
			return ITEM_INTERACT_SUCCESS
	..()

/obj/item/cell/attackby(obj/item/W, mob/user)
	..()
	if(istype(W, /obj/item/reagent_containers/syringe))
		var/obj/item/reagent_containers/syringe/S = W

		to_chat(user, "You inject the solution into the power cell.")

		if(S.reagents.has_reagent(REAGENT_ID_PHORON, 5))

			rigged = 1

			log_admin("LOG: [user.name] ([user.ckey]) injected a power cell with phoron, rigging it to explode.")
			message_admins("LOG: [user.name] ([user.ckey]) injected a power cell with phoron, rigging it to explode.")

		S.reagents.clear_reagents()

/obj/item/cell/proc/explode()
	// use() and give() can both be reached before qdel drains.  Make detonation
	// idempotent so one rigged cell contributes exactly one blast to an epoch.
	if(QDELETED(src) || detonation_pending)
		return
	var/turf/T = get_turf(src.loc)
/*
 * 1000-cell	explosion(T, -1, 0, 1, 1)
 * 2500-cell	explosion(T, -1, 0, 1, 1)
 * 10000-cell	explosion(T, -1, 1, 3, 3)
 * 15000-cell	explosion(T, -1, 2, 4, 4)
 * */
	if (charge==0)
		return
	detonation_pending = TRUE
	var/devastation_range = -1 //round(charge/11000)
	var/heavy_impact_range = round(sqrt(charge)/60)
	var/light_impact_range = round(sqrt(charge)/30)
	var/flash_range = light_impact_range
	if (light_impact_range==0)
		detonation_pending = FALSE
		rigged = 0
		corrupt()
		return
	//explosion(T, 0, 1, 2, 2)

	log_admin("LOG: Rigged power cell explosion at [COORD(T)], charge [charge]/[maxcharge], holder [loc?.type], last touched by [forensic_data?.get_lastprint()]")
	message_admins("LOG: Rigged power cell explosion at [COORD(T)], charge [charge]/[maxcharge], holder [loc?.type], last touched by [forensic_data?.get_lastprint()]")

	// Clear the trigger before queueing.  Destruction callbacks and machinery
	// shutdown may attempt another draw while the explosion is pending.
	rigged = FALSE
	charge = 0
	explosion(T, devastation_range, heavy_impact_range, light_impact_range, flash_range)

	qdel(src)

/obj/item/cell/proc/corrupt()
	charge /= 2
	maxcharge /= 2
	if (prob(10))
		rigged = 1 //broken batterys are dangerous

/obj/item/cell/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	charge -= (charge / severity) * (1 - material_emp_resistance / 100)
	if (charge < 0)
		charge = 0

	update_icon()

/obj/item/cell/ex_act(severity)
	. = ..()
	if(!QDELETED(src) && prob(50 / severity))
		corrupt()

/obj/item/cell/proc/get_electrocute_damage()
	//1kW = 5
	//10kW = 24
	//100kW = 45
	//250kW = 53
	//1MW = 66
	//10MW = 88
	//100MW = 110
	//1GW = 132
	if(charge >= 1000)
		var/damage = log(1.1,charge)
		damage = damage - (log(1.1,damage)*1.5)
		return round(damage)
	else
		return 0
