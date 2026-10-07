/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay
	name = "energy relay"
	desc = "Wirelessly drains energy from any available power channel in area. The performance index is quite low."
	icon_state = "tesla"
	equip_cooldown = 10
	energy_drain = 0
	range = 0
	var/coeff = 100
	var/static/list/use_channels = list(EQUIP,ENVIRON,LIGHT)
	equip_type = EQUIP_UTILITY

OM_FIELD(/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, relaying, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE_ALL(/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, PERIODIC_FAST, list("relaying", "chassis"))

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/periodic_step()
	if(mech_body_plan().has_affliction(chassis, MECHA_INT_SHORT_CIRCUIT))
		set_ready_state(TRUE)
		set_relaying(FALSE)
		return PROCESS_KILL
	var/cur_charge = chassis.get_charge()
	if(isnull(cur_charge) || !chassis.cell)
		set_ready_state(TRUE)
		occupant_message("No powercell detected.")
		set_relaying(FALSE)
		return PROCESS_KILL
	if(cur_charge<chassis.cell.maxcharge)
		var/area/A = get_area(chassis)
		if(A)
			var/pow_chan
			for(var/c in list(EQUIP,ENVIRON,LIGHT))
				if(A.powered(c))
					pow_chan = c
					break
			if(pow_chan)
				var/delta = min(12, chassis.cell.maxcharge-cur_charge)
				chassis.give_power(delta)
				A.use_power_oneoff(delta*coeff, pow_chan)
	return

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/detach()
	set_relaying(FALSE)
	if(chassis?.energy_relay == src)
		rel_clear(chassis, nameof(chassis.energy_relay))
	..()
	return

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/attach(obj/mecha/M)
	..()
	rel_set(chassis, nameof(chassis.energy_relay), src)
	return

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/can_attach(obj/mecha/M)
	if(..())
		if(!M.energy_relay)
			return 1
	return 0

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/proc/dyngetcharge()
	if(equip_ready) //disabled
		return chassis.dyngetcharge()
	var/area/A = get_area(chassis)
	var/pow_chan = get_power_channel(A)
	var/charge = 0
	if(pow_chan)
		charge = 1000 //making magic
	else
		return chassis.dyngetcharge()
	return charge

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/proc/get_power_channel(area/A)
	var/pow_chan
	if(A)
		for(var/c in use_channels)
			if(A.powered(c))
				pow_chan = c
				break
	return pow_chan

CAPABILITIES(/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay)
	op("toggle_relay", topic("toggle_relay"), then(PROC_REF(topic_toggle_relay)))

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/proc/topic_toggle_relay(datum/act/op/A)
	if(relaying)
		set_relaying(FALSE)
		set_ready_state(TRUE)
		src.mecha_log_message("Deactivated.")
	else
		set_relaying(TRUE)
		set_ready_state(FALSE)
		src.mecha_log_message("Activated.")
	return

/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/get_equip_info()
	if(!chassis) return
	return (equip_ready ? span_green("*") : span_red("*")) + "&nbsp;[src.name] - <a href='byond://?src=\ref[src];toggle_relay=1'>[relaying?"Dea":"A"]ctivate</a>"
