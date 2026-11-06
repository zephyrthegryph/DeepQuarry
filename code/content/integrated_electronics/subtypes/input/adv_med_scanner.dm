//Racial addition for medscanner circuitry.
//Because if we die from water, probably shouldn't feed em protein shakes yknow or if you are an antag this can be useful info too

/obj/item/integrated_circuit/input/adv_med_scanner

	name = "integrated advanced medical analyzer"
	desc = "A very small version of the medibot's medical analyzer.  This allows the machine to know how healthy someone is.  \

	This type is much more precise, allowing the machine to know much more about the target than a normal analyzer."
	icon_state = "medscan_adv"
	complexity = 12
	inputs = list("target" = IC_PINTYPE_REF)
	outputs = list(
		"total health %"		= IC_PINTYPE_NUMBER,
		"total missing health"	= IC_PINTYPE_NUMBER,
		"heart rate"			= IC_PINTYPE_NUMBER,
		"SpO2 %"				= IC_PINTYPE_NUMBER,
		"respiratory rate"		= IC_PINTYPE_NUMBER,
		"temperature (C)"		= IC_PINTYPE_NUMBER,
		"findings"				= IC_PINTYPE_NUMBER,
		"species"				= IC_PINTYPE_STRING,
		"size %"				= IC_PINTYPE_NUMBER
	)
	activators = list("scan" = IC_PINTYPE_PULSE_IN, "on scanned" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 80

/obj/item/integrated_circuit/input/adv_med_scanner/do_work()
	var/mob/living/carbon/human/H = get_pin_data_as_type(IC_INPUT, 1, /mob/living/carbon/human)
	if(!istype(H)) //Invalid input
		return

	if(H in view(get_turf(H))) // Like medbot's analyzer it can be used in range..

		var/total_health = round(H.vitality(), 0.01)*100
		var/missing_health = round(H.get_endurance() * (1 - H.vitality()), 0.1)

		set_pin_data(IC_OUTPUT, 1, total_health)
		set_pin_data(IC_OUTPUT, 2, missing_health)
		set_diagnosis_pins(H)
		set_pin_data(IC_OUTPUT, 8, H.species.name)
		set_pin_data(IC_OUTPUT, 9, H.size_multiplier *100)

	push_data()
	activate_pin(2)

/// Output pins 3-7: vitals and the number of findings from the analyzer's
/// diagnosis (the advanced analyzer's sensors).
/obj/item/integrated_circuit/input/adv_med_scanner/proc/set_diagnosis_pins(mob/living/carbon/human/H)
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/health_analyzer/advanced)
	set_pin_data(IC_OUTPUT, 3, D?.heart_rate)
	set_pin_data(IC_OUTPUT, 4, D?.oxygenation)
	set_pin_data(IC_OUTPUT, 5, D?.respiratory_rate)
	set_pin_data(IC_OUTPUT, 6, D?.temperature)
	set_pin_data(IC_OUTPUT, 7, LAZYLEN(D?.findings))
	spent(D, H)
