/datum/wires/apc
	holder_type = /obj/machinery/power/apc
	wire_count = 4
	proper_name = "APC"

/datum/wires/apc/New(atom/_holder)
	wires = list(WIRE_IDSCAN, WIRE_MAIN_POWER1, WIRE_MAIN_POWER2, WIRE_AI_CONTROL)
	return ..()

/datum/wires/apc/get_status()
	. = ..()
	var/obj/machinery/power/apc/A = holder
	. += "The APC is [lock_locked(A) ? "" : "un"]locked."
	. += A.shorted ? "The APCs power has been shorted." : "The APC is working properly!"
	. += "The 'AI control allowed' light is [A.aidisabled ? "off" : "on"]."

/datum/wires/apc/interactable(mob/user)
	var/obj/machinery/power/apc/A = holder
	return panel_open(A) && !cover_open(A)

/datum/wires/apc/on_pulse(wire)
	var/obj/machinery/power/apc/A = holder

	switch(wire)
		if(WIRE_IDSCAN)
			A.set_locked(FALSE)
			om_after(A, 30 SECONDS, TYPE_PROC_REF(/obj/machinery/power/apc, set_locked), TRUE)

		if(WIRE_MAIN_POWER1, WIRE_MAIN_POWER2)
			if(!A.shorted)
				A.set_shorted(TRUE)

				om_after(src, 2 MINUTES, PROC_REF(main_power_pulse_ends))

		if(WIRE_AI_CONTROL)
			if(!A.aidisabled)
				A.aidisabled = TRUE

				om_after(src, 1 SECOND, PROC_REF(ai_control_pulse_ends))

/datum/wires/apc/on_cut(wire, mend, mob/user)
	var/obj/machinery/power/apc/A = holder

	switch(wire)
		if(WIRE_MAIN_POWER1, WIRE_MAIN_POWER2)
			if(!mend)
				if(isliving(user))
					A.shock(user, 50)
				A.set_shorted(TRUE)

			else if(!is_cut(WIRE_MAIN_POWER1) && !is_cut(WIRE_MAIN_POWER2))
				A.set_shorted(FALSE)
				if(isliving(user))
					A.shock(user, 50)

		if(WIRE_AI_CONTROL)
			A.aidisabled = !mend

/datum/wires/apc/proc/main_power_pulse_ends()
	var/obj/machinery/power/apc/A = holder
	if(!is_cut(WIRE_MAIN_POWER1) && !is_cut(WIRE_MAIN_POWER2))
		A.set_shorted(FALSE)

/datum/wires/apc/proc/ai_control_pulse_ends()
	var/obj/machinery/power/apc/A = holder
	if(!is_cut(WIRE_AI_CONTROL))
		A.aidisabled = FALSE
