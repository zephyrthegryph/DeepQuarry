/obj/item/mecha_parts/mecha_equipment/generator
	name = "phoron generator"
	desc = "Generates power using solid phoron as fuel. Pollutes the environment."
	icon_state = "tesla"
	equip_cooldown = 10
	energy_drain = 0
	range = MECH_MELEE
	var/coeff = 100
	var/obj/item/stack/material/fuel
	var/fuel_type = /obj/item/stack/material/phoron
	var/fuel_amount = 0
	var/max_fuel = 150000
	var/fuel_per_cycle_idle = 100
	var/fuel_per_cycle_active = 500
	var/power_per_cycle = 20

	equip_type = EQUIP_UTILITY

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/generator)
	owns_one(nameof(fuel), starts = nameof(fuel_type))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))


OM_FIELD(/obj/item/mecha_parts/mecha_equipment/generator, generating, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE_ALL(/obj/item/mecha_parts/mecha_equipment/generator, PERIODIC_FAST, list("generating", "chassis"))

/obj/item/mecha_parts/mecha_equipment/generator/periodic_step()
	if(fuel_amount <= 0) // Spam fix
		src.mecha_log_message("Deactivated - no fuel.")
		set_ready_state(TRUE)
		set_generating(FALSE)
		return PROCESS_KILL
	var/cur_charge = chassis.get_charge()
	if(isnull(cur_charge))
		set_ready_state(TRUE)
		occupant_message("No powercell detected.")
		src.mecha_log_message("Deactivated.")
		set_generating(FALSE)
		return PROCESS_KILL
	var/use_fuel = fuel_per_cycle_idle
	if(cur_charge<chassis.cell.maxcharge)
		use_fuel = fuel_per_cycle_active
		chassis.give_power(power_per_cycle)
	fuel_amount -= min(use_fuel, fuel_amount) // allows fuel to get to 0
	update_equip_info()

/obj/item/mecha_parts/mecha_equipment/generator/detach()
	set_generating(FALSE)
	..()
	return

TOPIC_ACTION(/obj/item/mecha_parts/mecha_equipment/generator, "toggle", PROC_REF(topic_toggle))

/obj/item/mecha_parts/mecha_equipment/generator/proc/topic_toggle(mob/user, list/args)
	if(generating)
		set_generating(FALSE)
		set_ready_state(TRUE)
		src.mecha_log_message("Deactivated.")
	else
		set_generating(TRUE)
		set_ready_state(FALSE)
		src.mecha_log_message("Activated.")
	return

/obj/item/mecha_parts/mecha_equipment/generator/get_equip_info()
	var/output = ..()
	if(output)
		return "[output] \[[fuel]: [fuel_amount] cm<sup>3</sup>\] - <a href='byond://?src=\ref[src];toggle=1'>[generating?"Dea":"A"]ctivate</a>"
	return

/obj/item/mecha_parts/mecha_equipment/generator/action(target)
	if(chassis)
		var/result = load_fuel(target)
		var/message
		if(isnull(result))
			message = span_warning("[fuel] traces in target minimal. [target] cannot be used as fuel.")
		else if(!result)
			message = "Unit is full."
		else
			message = "[result] unit\s of [fuel] successfully loaded."
			send_byjax(chassis?.slot_item(MECHA_SLOT_PILOT),"exosuit.browser","\ref[src]",src.get_equip_info())
		occupant_message(message)
	return

/obj/item/mecha_parts/mecha_equipment/generator/proc/load_fuel(obj/item/stack/material/P)
	if(P.type == fuel_type && P.get_amount())
		var/to_load = max(max_fuel - fuel_amount,0)
		if(to_load >= 2000)
			if(to_load > P.get_amount() * 2000)
				to_load = P.get_amount() * 2000
			var/sheets = round(to_load / 2000, 1)
			if(P.get_amount() >= sheets)
				fuel_amount += sheets * 2000
				P.use(sheets)
				return sheets * 2000
		else
			return 0
	return

/// Old attackby.
/obj/item/mecha_parts/mecha_equipment/generator/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/weapon = A.held
	var/result = load_fuel(weapon)
	if(isnull(result))
		act_message(user, src, MSG_SELF(span_warning("[fuel] traces minimal. [weapon] cannot be used as fuel.")), \
			MSG_OTHERS("%U% tries to shove [weapon] into %T%. What a dumb-ass."))
	else if(!result)
		to_chat(user, "Unit is full.")
	else
		act_message(user, src, MSG_SELF("[result] unit\s of [fuel] successfully loaded."), MSG_OTHERS("%U% loads %T% with [fuel]."))
	return OP_PASS

/obj/item/mecha_parts/mecha_equipment/generator/critfail()
	..()
	var/turf/simulated/T = get_turf(src)
	if(!T)
		return
	var/datum/gas_mixture/GM = new
	if(prob(10))
		T.assume_gas(GAS_PHORON, 100, 1500+T0C)
		T.visible_message("The [src] suddenly disgorges a cloud of heated phoron.")
		destroy()
	else
		// T.air was XGM's per-turf mixture; under LINDA call return_air().
		var/datum/gas_mixture/turf_air = istype(T) ? T.return_air() : null
		T.assume_gas(GAS_PHORON, 5, turf_air ? turf_air.return_temperature() : T20C)
		T.visible_message("The [src] suddenly disgorges a cloud of phoron.")
	T.assume_air(GM)
	return

/obj/item/mecha_parts/mecha_equipment/generator/nuclear
	name = "\improper ExoNuclear reactor"
	desc = "Generates power using uranium. Pollutes the environment."
	icon_state = "tesla"
	max_fuel = 50000
	fuel_per_cycle_idle = 10
	fuel_per_cycle_active = 30
	power_per_cycle = 50
	fuel_type = /obj/item/stack/material/uranium
	var/rad_per_cycle = 0.3

/obj/item/mecha_parts/mecha_equipment/generator/nuclear/periodic_step()
	if(..())
		radiation_pulse(
			src,
			max_range = 5,
			threshold = RAD_MEDIUM_INSULATION,
			chance = URANIUM_IRRADIATION_CHANCE,
			strength = 25
		)
	return

/obj/item/mecha_parts/mecha_equipment/generator/nuclear/critfail()
	return
