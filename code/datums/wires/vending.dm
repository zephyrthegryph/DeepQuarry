/datum/wires/vending
	holder_type = /obj/machinery/vending
	wire_count = 4
	proper_name = "Vending machine"

/datum/wires/vending/New(atom/_holder)
	wires = list(WIRE_THROW_ITEM, WIRE_IDSCAN, WIRE_ELECTRIFY, WIRE_CONTRABAND)
	return ..()

/datum/wires/vending/interactable(mob/user)
	var/obj/machinery/vending/V = holder
	if(iscarbon(user) && V.seconds_electrified && V.shock(user, 100))
		return FALSE
	return panel_open(V)

/datum/wires/vending/get_status()
	var/obj/machinery/vending/V = holder
	. = ..()
	. += "The orange light is [V.seconds_electrified ? "on" : "off"]."
	. += "The red light is [V.shoot_inventory ? "off" : "blinking"]."
	. += "The green light is [(V.categories & CAT_HIDDEN) ? "on" : "off"]."
	. += "A [V.scan_id ? "purple" : "yellow"] light is on."

/datum/wires/vending/on_pulse(wire)
	var/obj/machinery/vending/V = holder
	switch(wire)
		if(WIRE_THROW_ITEM)
			V.set_shoot_inventory(!V.shoot_inventory)
		if(WIRE_CONTRABAND)
			V.set_categories(V.categories ^ CAT_HIDDEN)
		if(WIRE_ELECTRIFY)
			V.set_seconds_electrified(30)
		if(WIRE_IDSCAN)
			V.set_scan_id(!V.scan_id)
	..()

/datum/wires/vending/on_cut(wire, mend)
	var/obj/machinery/vending/V = holder
	switch(wire)
		if(WIRE_THROW_ITEM)
			V.set_shoot_inventory(!mend)
		if(WIRE_CONTRABAND)
			V.set_categories(V.categories & ~CAT_HIDDEN)
		if(WIRE_ELECTRIFY)
			if(mend)
				V.set_seconds_electrified(0)
			else
				V.set_seconds_electrified(-1)
		if(WIRE_IDSCAN)
			V.set_scan_id(TRUE)
	..()
