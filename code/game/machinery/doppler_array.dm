/obj/machinery/doppler_array
	maintenance_flags = MACHINE_MAINT_STANDARD
	anchored = TRUE
	name = "tachyon-doppler array"
	density = TRUE
	desc = "A highly precise directional sensor array which measures the release of quants from decaying tachyons. The doppler shifting of the mirror-image formed by these quants can reveal the size, location and temporal affects of energetic disturbances within a large radius ahead of the array."
	dir = NORTH

	icon_state = "doppler"
	circuit = /obj/item/circuitboard/doppler_array

	var/list/detected_explosions

/obj/machinery/doppler_array/Initialize(mapload)
	//Explosive analysis
	var/static/list/explosive_events = list(
		/datum/notice/machinery_explosion_detected = TYPE_PROC_REF(/datum/experiment_handler, try_run_ordinance_experiment),
	)
	new /datum/experiment_handler(src, \
		config_mode = EXPERIMENT_CONFIG_ALTCLICK, \
		allowed_experiments = list(/datum/experiment/ordnance),\
		config_flags = EXPERIMENT_CONFIG_ALWAYS_ACTIVE|EXPERIMENT_CONFIG_SILENT_FAIL,\
		experiment_events = explosive_events, \
	)
	. = ..()
	observe(OM_WORLD, /datum/notice/world_explosion, src, then(PROC_REF(sense_explosion)))
	add_trait(src, TRAIT_ALT_CLICK_BLOCKER, ROUNDSTART_TRAIT)

CAPABILITIES(/obj/machinery/doppler_array)
	interface("DopplerArray")
	ui_shape(explosions = list_of(row(index = int(), time = schema_text(), x = int(), y = int(), z = int(), devastation_range = num(), heavy_impact_range = num(), light_impact_range = num(), seconds_taken = num())))

/obj/machinery/doppler_array/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["explosions"] = length(detected_explosions) ? detected_explosions : null
	return data

/obj/machinery/doppler_array/proc/sense_explosion(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/world_explosion/event = A
	var/turf/epicenter = event.epicenter
	var/devastation_range = event.devastation_range
	var/heavy_impact_range = event.heavy_impact_range
	var/light_impact_range = event.light_impact_range
	var/seconds_taken = event.took

	if(has_stat(NOPOWER))
		return

	var/x0 = epicenter.x
	var/y0 = epicenter.y
	var/z0 = epicenter.z
	if(!(z0 in GetConnectedZlevels(z)))
		return
	var/turf/our_turf = get_turf(src)
	if(our_turf.Distance(epicenter) > 100)
		return
	atom_say("Explosive disturbance detected - Epicenter at: grid ([x0],[y0],[z0]). Epicenter radius: [devastation_range]. Outer radius: [heavy_impact_range]. Shockwave radius: [light_impact_range]. Temporal displacement of tachyons: [seconds_taken] seconds.")
	OM_EMIT(src, /datum/om/event/machinery_explosion_detected, epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
	LAZYINITLIST(detected_explosions); detected_explosions += list(
		list(
			"index" = length(detected_explosions),
			"time" = stationtime2text(),
			"x" = x0,
			"y" = y0,
			"z" = z0,
			"devastation_range" = devastation_range,
			"heavy_impact_range" = heavy_impact_range,
			"light_impact_range" = light_impact_range,
			"seconds_taken" = seconds_taken,
		)
	)
	SStgui.update_uis(src)

/obj/machinery/doppler_array/power_change()
	. = ..()
	if(!has_stat(NOPOWER))
		icon_state = initial(icon_state)
	else
		icon_state = "[initial(icon_state)]_off"

EXTEND_INTERACTIONS(/obj/machinery/doppler_array, \
	INTERACT_INSERT(/obj/item/storage/part_replacer, PROC_REF(interaction_part_replacement_impl), "Replace parts"), \
)

/obj/machinery/doppler_array/proc/interaction_part_replacement_impl(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return default_part_replacement(user, held) ? TRUE : FALSE
