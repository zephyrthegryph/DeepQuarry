/obj/machinery/pump_relay
	name = "Pump Relay"
	desc = "Pumps chemicals long distances using plastic hoses. It has multiple inputs to allow the creation of complex pump networks. Does not require power."
	icon = 'icons/obj/machines/refinery_machines.dmi'
	icon_state = "pumprelay"
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/pump_relay
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS

CAPABILITIES(/obj/machinery/pump_relay)
	reagents(200)
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))

/obj/machinery/pump_relay/Initialize(mapload)
	. = ..()
	default_apply_parts()

	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/input)
	add_hose_connector(/datum/hose_connector/output)

/obj/machinery/pump_relay/on_reagent_change(changetype)
	. = ..()
	if(prob(2))
		visible_message(span_infoplain("\The [src] gurgles as it pumps fluid."))

/obj/machinery/pump_relay/draw(datum/look/look)
	..()
	// GOOBY!
	var/datum/reagents/R = reagents
	look.watch(R) // its level and colour are tracked on the holder
	if(R?.total_volume >= 5)
		var/percent
		switch((R.total_volume / R.maximum_volume) * 100)
			if(5  to 10)		percent = 1
			if(10 to 20)		percent = 2
			if(20 to 30)		percent = 3
			if(30 to 40)		percent = 4
			if(40 to 50)		percent = 5
			if(50 to 60)		percent = 6
			if(60 to 70)		percent = 7
			if(70 to 80)		percent = 8
			if(80 to 90)		percent = 9
			if(90 to INFINITY)	percent = 10
		look.overlay(look_overlay_image(icon, "pumprelay_r_[percent]", color = R.tint, dir = dir), when = !isnull(percent))

/obj/machinery/pump_relay/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u."
