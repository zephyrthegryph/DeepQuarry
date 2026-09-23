#define ENERGY_PER_K 20
#define MINIMUM_PLASMA_TEMPERATURE 10000

/obj/machinery/power/hydromagnetic_trap
	maintenance_flags = MACHINE_MAINT_WRENCH
	name = "\improper hydromagnetic trap"
	desc = "A device for extracting power from high-energy plasma in toroidal fields."
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "mag_trap0"
	anchored = TRUE
	var/list/things_in_range//what is in a radius of us?
	var/list/fields_in_range//What EM fields are in that radius?
	var/list/active_field//Our active field.
	var/active = 0 //are we even on?
	var/id_tag //needed for !!rasins!!
	circuit = /obj/item/circuitboard/hydromagnetic_trap

/obj/machinery/power/hydromagnetic_trap/process()
	if(anchored)
		if(!powernet)
			src.active = 0
			connect_to_network()
			if(!powernet)
				return PROCESS_KILL

		Search()
		if(!length(active_field))
			active = FALSE
			icon_state = "mag_trap0"
			return PROCESS_KILL
		Active()

	else
		if(powernet)
			LAZYCLEARLIST(active_field)
			disconnect_from_network()
		return PROCESS_KILL

/obj/machinery/power/hydromagnetic_trap/proc/Search()//let's not have +100 instances of the same field in active_field.
	things_in_range = range(7, src)
	LAZYCLEARLIST(fields_in_range) // rebuild fresh each tick so in-range fields don't accumulate as duplicates
	for (var/obj/effect/fusion_em_field/FFF in things_in_range)
		LAZYADD(fields_in_range, FFF)

	listclearnulls(active_field)
	listclearnulls(fields_in_range)

	for (var/obj/effect/fusion_em_field/FFF in fields_in_range)
		if(get_dist(src, FFF) > 7)
			LAZYREMOVE(fields_in_range, FFF)
			continue

		if (length(active_field) > 0)
			return
		else if (length(active_field) == 0)
			Link()
	return

/obj/machinery/power/hydromagnetic_trap/proc/Link() //discover our EM field
	var/obj/effect/fusion_em_field/FFF
	for(FFF in fields_in_range)
		LAZYADD(active_field, FFF)
		active = 1
	return

/obj/machinery/power/hydromagnetic_trap/proc/Active()//POWERRRRR
	if (active == 0)
		return
	for (var/obj/effect/fusion_em_field/FF in active_field)
		if (FF.plasma_temperature >= MINIMUM_PLASMA_TEMPERATURE)
			icon_state = "mag_trap1"
			add_avail(ENERGY_PER_K * FF.plasma_temperature)
		if (FF.plasma_temperature <= MINIMUM_PLASMA_TEMPERATURE)
			icon_state = "mag_trap0"
	return

#undef ENERGY_PER_K
#undef MINIMUM_PLASMA_TEMPERATURE
