#define ENERGY_PER_K 20
#define MINIMUM_PLASMA_TEMPERATURE 10000

/obj/machinery/power/hydromagnetic_trap
	maintenance_flags = MACHINE_MAINT_WRENCH
	name = "\improper hydromagnetic trap"
	desc = "A device for extracting power from high-energy plasma in toroidal fields."
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "mag_trap0"
	anchored = TRUE
	var/list/fields_in_range//What EM fields are in that radius?
	var/list/active_field//Our active field.
	active = 0 //are we even on?
	var/id_tag //needed for !!rasins!!
	circuit = /obj/item/circuitboard/hydromagnetic_trap

// The hydromagnetic trap (doc/rewrite/final_api.html section 16): bolted down and wired, every machine service interval it looks for a fusion
// field within 7 tiles and draws ENERGY_PER_K W per K of its plasma above MINIMUM_PLASMA_TEMPERATURE (trap_step()).
CAPABILITIES(/obj/machinery/power/hydromagnetic_trap)
	ref_many(nameof(fields_in_range), /obj/effect/fusion_em_field)
	ref_many(nameof(active_field), /obj/effect/fusion_em_field)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(trap_step)))
	on_change(nameof(anchored), ANY, then(PROC_REF(anchoring_changed)))

/// Unbolted, it lets go of its field and leaves its cable network.
/obj/machinery/power/hydromagnetic_trap/proc/anchoring_changed(datum/act/A)
	if(anchored || !power_region)
		return
	rel_clear(src, nameof(active_field))
	disconnect_from_network()

/// One step: bolted down and wired, it finds its field and draws from it.
/obj/machinery/power/hydromagnetic_trap/proc/trap_step(datum/act/timer/A)
	if(!anchored)
		return
	if(!power_region)
		set_active(0)
		connect_to_network()
		if(!power_region)
			return
	Search()
	if(!length(active_field))
		set_active(FALSE)
		icon_state = "mag_trap0"
		return
	Active()

/obj/machinery/power/hydromagnetic_trap/proc/Search()//let's not have +100 instances of the same field in active_field.
	rel_clear(src, nameof(fields_in_range)) // rebuild fresh each tick so in-range fields don't accumulate as duplicates
	for (var/obj/effect/fusion_em_field/FFF in range(7, src))
		rel_add(src, nameof(fields_in_range), FFF)

	listclearnulls(active_field)
	listclearnulls(fields_in_range)

	for (var/obj/effect/fusion_em_field/FFF in fields_in_range)
		if(get_dist(src, FFF) > 7)
			rel_remove(src, nameof(fields_in_range), FFF)
			continue

		if (length(active_field) > 0)
			return
		else if (length(active_field) == 0)
			Link()
	return

/obj/machinery/power/hydromagnetic_trap/proc/Link() //discover our EM field
	var/obj/effect/fusion_em_field/FFF
	for(FFF in fields_in_range)
		rel_add(src, nameof(active_field), FFF)
		set_active(1)
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

