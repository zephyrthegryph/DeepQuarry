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

// Buttons and pod consoles find their drivers by id (REL_KEYED sources).
/obj/machinery/mass_driver/relations()
	. = ..()
	. += rel_key(nameof(id))

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
	keyed_set_id(src, nameof(id), new_id) // re-links the keyed buttons and consoles
	return ITEM_INTERACT_SUCCESS

/obj/machinery/mass_driver/proc/drive(amount)
	if(!operable())
		return
	use_power(500)
	var/O_limit
	var/atom/target = get_edge_target_turf(src, dir)
	for(var/atom/movable/O in contents_of(loc))
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

DAMAGE_REACTION(/obj/machinery/mass_driver, DAMAGE_EMP, PROC_REF(mass_driver_emp))
/// An EMP fires the driver.
/obj/machinery/mass_driver/proc/mass_driver_emp(datum/damage_packet/packet)
	if(!operable())
		return
	drive()
