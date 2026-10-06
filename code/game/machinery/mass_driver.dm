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

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/mass_driver/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/mass_driver/proc/id_title(datum/act/A)
	return "[src] ID]"

/obj/machinery/mass_driver/proc/id_question(datum/act/A)
	return "[src] has an id of \"[id]\". What would you like it to be?"

/// The multitool's answer: the driver's new id (the keyed buttons and consoles follow it).
/obj/machinery/mass_driver/proc/driver_id_entered(datum/act/op/A)
	var/new_id = A.answer?.value
	if(!new_id)
		to_chat(A.actor, "No input found please hang up and try your call again.")
		return OP_OK
	keyed_set_id(src, nameof(id), new_id) // re-links the keyed buttons and consoles
	return OP_OK

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

CAPABILITIES(/obj/machinery/mass_driver)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(mass_driver_emp))))
	// the multitool sets the id behind an open panel; with the panel shut it takes the click and does nothing
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT - 1), wait(0), label("Set ID"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)),
		asks(/datum/prompt/number, fields = list("title" = computed(PROC_REF(id_title)), "question" = computed(PROC_REF(id_question)), "default" = nameof(id), "max_value" = 9999, "timeout" = 0)),
		then(PROC_REF(driver_id_entered)))

/// An EMP fires the driver.
/obj/machinery/mass_driver/proc/mass_driver_emp(datum/act/hit/emp/A)
	if(!operable())
		return HOOK_DECLINE
	drive()
	return HOOK_DECLINE
