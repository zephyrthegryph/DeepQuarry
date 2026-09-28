//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/mass_driver
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "mass driver"
	desc = "Shoots things into space."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "mass_driver"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 50
	circuit = /obj/item/circuitboard/mass_driver

	var/power = 1.0
	var/code = 1.0
	var/id = null
	var/drive_range = 50 //this is mostly irrelevant since current mass drivers throw into space, but you could make a lower-range mass driver for interstation transport or something I guess.

/obj/machinery/mass_driver/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/mass_driver/multitool_act(mob/user, obj/item/tool)
	if(!panel_open)
		return ITEM_INTERACT_BLOCKING
	om_ask(user, /datum/om/prompt/number/mass_driver_id, PROC_REF(driver_id_entered), message = "[src] has an id of \"[id]\". What would you like it to be?", title = "[src] ID]", default = id)
	return ITEM_INTERACT_SUCCESS

/datum/om/prompt/number/mass_driver_id
	max = 9999
	requires = PROMPT_ADJACENT

/datum/om/prompt/number/mass_driver_id/cancelled()
	to_chat(answerer, "No input found please hang up and try your call again.")

/obj/machinery/mass_driver/proc/driver_id_entered(datum/om/prompt/number/mass_driver_id/ask)
	var/mob/user = ask.answerer
	var/new_id = ask.number
	if(!new_id)
		to_chat(user, "No input found please hang up and try your call again.")
		return ITEM_INTERACT_BLOCKING
	id = new_id
	return ITEM_INTERACT_SUCCESS

/obj/machinery/mass_driver/proc/drive(amount)
	if(stat & (BROKEN|NOPOWER))
		return
	use_power(500)
	var/O_limit
	var/atom/target = get_edge_target_turf(src, dir)
	for(var/atom/movable/O in loc)
		if(!O.anchored||istype(O, /obj/mecha))//Mechs need their launch platforms.
			O_limit++
			if(O_limit >= 20)
				for(var/mob/M in hearers(src, null))
					to_chat(M, span_notice("The mass driver lets out a screech, it mustn't be able to handle any more items."))
				break
			use_power(500)
			O.throw_at(target, drive_range * power, power)
	flick("mass_driver1", src)
	return

/obj/machinery/mass_driver/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || stat & (BROKEN|NOPOWER))
		return
	drive()
