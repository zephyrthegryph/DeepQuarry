/datum/wires/smes
	holder_type = /obj/machinery/power/smes/buildable
	wire_count = 5
	proper_name = "SMES"

/datum/wires/smes/New(atom/_holder)
	wires = list(WIRE_SMES_RCON, WIRE_SMES_INPUT, WIRE_SMES_OUTPUT, WIRE_SMES_GROUNDING, WIRE_SMES_FAILSAFES)
	return ..()

/datum/wires/smes/interactable(mob/user)
	var/obj/machinery/power/smes/buildable/S = holder
	if(S.panel_open)
		return TRUE
	return FALSE

/datum/wires/smes/get_status()
	var/obj/machinery/power/smes/buildable/S = holder
	. = ..()
	. += "The green light is [(S.input_cut || S.input_pulsed || S.output_cut || S.output_pulsed) ? "off" : "on"]."
	. += "The red light is [(S.safeties_enabled || S.grounding) ? "off" : "blinking"]."
	. += "The blue light is [S.RCon ? "on" : "off"]."

/datum/wires/smes/on_cut(wire, mend)
	var/obj/machinery/power/smes/buildable/S = holder
	switch(wire)
		if(WIRE_SMES_RCON)
			S.RCon = mend
		if(WIRE_SMES_INPUT)
			S.input_cut = !mend
			changed(S, CHANGE_MACHINE_SETTINGS)
		if(WIRE_SMES_OUTPUT)
			S.output_cut = !mend
			changed(S, CHANGE_MACHINE_SETTINGS)
		if(WIRE_SMES_GROUNDING)
			S.grounding = mend
			changed(S, CHANGE_MACHINE_SETTINGS)
		if(WIRE_SMES_FAILSAFES)
			S.safeties_enabled = mend
	..()

/datum/wires/smes/on_pulse(wire)
	var/obj/machinery/power/smes/buildable/S = holder
	switch(wire)
		if(WIRE_SMES_RCON)
			if(S.RCon)
				S.set_rcon(FALSE)
				om_after(S, 1 SECOND, TYPE_PROC_REF(/obj/machinery/power/smes/buildable, set_rcon), TRUE)
		if(WIRE_SMES_INPUT)
			S.toggle_input()
		if(WIRE_SMES_OUTPUT)
			S.toggle_output()
		if(WIRE_SMES_GROUNDING)
			S.grounding = 0
			changed(S, CHANGE_MACHINE_SETTINGS)
		if(WIRE_SMES_FAILSAFES)
			if(S.safeties_enabled)
				S.set_safeties(FALSE)
				om_after(S, 1 SECOND, TYPE_PROC_REF(/obj/machinery/power/smes/buildable, set_safeties), TRUE)
	..()
