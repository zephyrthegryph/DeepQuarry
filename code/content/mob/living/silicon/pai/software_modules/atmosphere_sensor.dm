/datum/pai_software/atmosphere_sensor
	name = "Atmosphere Sensor"
	ram_cost = 5
	id = "atmos_sense"
	toggle = 0

CAPABILITIES(/datum/pai_software/atmosphere_sensor)
	interface("pAIAtmos", state = nameof(GLOB.tgui_always_state))
	ui_shape(aircontents = list_of(map_of(schema_text(), schema_text())))

/datum/pai_software/atmosphere_sensor/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/turf/location = get_turf(user)
	data["aircontents"] = get_gas_mixture_default_scan_data(location?.return_air())
	return data
