/obj/item/integrated_circuit/input/atmo_scanner
	name = "integrated atmospheric analyser"
	desc = "The same atmospheric analysis module that is integrated into every PDA.  \
	This allows the machine to know the composition, temperature and pressure of the surrounding atmosphere."
	icon_state = "medscan_adv"
	complexity = 6
	inputs = list()
	outputs = list(
		"pressure"       = IC_PINTYPE_NUMBER,
		"temperature" = IC_PINTYPE_NUMBER,
		GAS_O2         = IC_PINTYPE_NUMBER,
		GAS_N2          = IC_PINTYPE_NUMBER,
		GAS_CO2           = IC_PINTYPE_NUMBER,
		GAS_CH4           = IC_PINTYPE_NUMBER,
		GAS_PHORON           = IC_PINTYPE_NUMBER,
		"other"           = IC_PINTYPE_NUMBER
	)
	activators = list("scan" = IC_PINTYPE_PULSE_IN, "on scanned" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 60

/obj/item/integrated_circuit/input/atmo_scanner/do_work()
	var/turf/T = get_turf(src)
	if(!istype(T)) //Invalid input
		return
	var/datum/gas_mixture/environment = T.return_air()

	var/pressure = environment.return_pressure()
	var/total_moles = environment.total_moles()

	if (total_moles)
		var/o2_level = LINDA_GAS_AMT(environment, GAS_O2)/total_moles
		var/n2_level = LINDA_GAS_AMT(environment, GAS_N2)/total_moles
		var/co2_level = LINDA_GAS_AMT(environment, GAS_CO2)/total_moles
		var/methane_level = LINDA_GAS_AMT(environment, GAS_CH4)/total_moles
		var/phoron_level = LINDA_GAS_AMT(environment, GAS_PHORON)/total_moles
		var/unknown_level =  1-(o2_level+n2_level+co2_level+phoron_level+methane_level)
		set_pin_data(IC_OUTPUT, 1, pressure)
		set_pin_data(IC_OUTPUT, 2, round(environment.return_temperature()-T0C,0.1))
		set_pin_data(IC_OUTPUT, 3, round(o2_level*100,0.1))
		set_pin_data(IC_OUTPUT, 4, round(n2_level*100,0.1))
		set_pin_data(IC_OUTPUT, 5, round(co2_level*100,0.1))
		set_pin_data(IC_OUTPUT, 6, round(phoron_level*100,0.01))
		set_pin_data(IC_OUTPUT, 7, round(methane_level*100,0.01))
		set_pin_data(IC_OUTPUT, 8, round(unknown_level, 0.01))
	else
		set_pin_data(IC_OUTPUT, 1, 0)
		set_pin_data(IC_OUTPUT, 2, -273.15)
		set_pin_data(IC_OUTPUT, 3, 0)
		set_pin_data(IC_OUTPUT, 4, 0)
		set_pin_data(IC_OUTPUT, 5, 0)
		set_pin_data(IC_OUTPUT, 6, 0)
		set_pin_data(IC_OUTPUT, 7, 0)
		set_pin_data(IC_OUTPUT, 8, 0)
	push_data()
	activate_pin(2)
