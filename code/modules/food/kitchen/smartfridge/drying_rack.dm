/obj/machinery/smartfridge/drying_rack
	name = "\improper Drying Rack"
	desc = "A machine for drying plants."
	wrenchable = 1
	icon_state = "drying_rack"
	icon_base = "drying_rack"
	circuit = /obj/item/circuitboard/smartfridge/drying
	// dry() works on each real item in turn.
	collapse_stock = FALSE

CAPABILITIES(/obj/machinery/smartfridge/drying_rack)
	climb()

/obj/machinery/smartfridge/drying_rack/accept_check(obj/item/O as obj)
	if(istype(O, /obj/item/reagent_containers/food/snacks/))
		var/obj/item/reagent_containers/food/snacks/S = O
		if (S.dried_type)
			return 1

	if(istype(O, /obj/item/stack/wetleather))
		return 1

	return 0

/obj/machinery/smartfridge/drying_rack/work_step(datum/act/timer/A)
	..()
	if(stored_count())
		dry()
		update_icon()
		return
	return PROCESS_KILL

/obj/machinery/smartfridge/drying_rack/has_pending_work()
	return ..() || stored_count()

DECLARE_APPEARANCE_PROC(/obj/machinery/smartfridge/drying_rack, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/smartfridge/drying_rack/appearance_overlays()
	. = list()
	var/not_working = !operable()
	var/hasItems
	for(var/datum/stored_item/I in item_records)
		if(I.get_amount())
			hasItems = 1
			break
	if(hasItems)
		if(not_working)
			icon_state = "[icon_base]-plant-off"
		else
			icon_state = "[icon_base]-plant"
	else
		if(not_working)
			icon_state = "[icon_base]-off"
		else
			icon_state = "[icon_base]"

/obj/machinery/smartfridge/drying_rack/proc/dry()
	for(var/datum/stored_item/I in item_records)
		for(var/obj/item/reagent_containers/food/snacks/S in I.instances)
			if(S.dry) continue
			if(S.dried_type == S.type)
				S.dry = 1
				S.name = "dried [S.name]"
				S.color = "#AAAAAA"
				rel_remove(I, nameof(I.instances), S)
				S.forceMove(get_turf(src))
			else
				var/D = S.dried_type
				new D(get_turf(src))
				replaced_by(S)
			return

		for(var/obj/item/stack/wetleather/WL in I.instances)
			if(!WL.wetness)
				if(WL.get_amount())
					WL.forceMove(get_turf(src))
					WL.dry()
				rel_remove(I, nameof(I.instances), WL)
				break

			WL.set_wetness(max(0, WL.wetness - rand(1, 3)))

	return

/obj/machinery/smartfridge/drying_rack/step_gate(datum/act/A)
	return operable()

/obj/machinery/smartfridge/drying_rack/step_start_condition()
	return TRUE
