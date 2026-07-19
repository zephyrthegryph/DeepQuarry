/proc/generated_station_seed_air(turf/open/T)
	if(!istype(T, /turf/simulated) || T.density)
		return FALSE
	if(!T.air)
		T.air = T.create_gas_mixture()
		if(SSair?.initialized)
			T.update_air_ref(0)
	var/datum/gas_mixture/air = T.return_air()
	if(!air)
		return FALSE
	for(var/gas_type in GLOB.meta_gas_info)
		air.set_moles(gas_type, 0)
	air.set_moles(/datum/gas/oxygen, MOLES_O2STANDARD)
	air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)
	air.set_temperature(T20C)
	return TRUE

/// Data/camera bridge whose destruction explicitly disconnects its department.
/obj/machinery/generated_station_data_relay
	name = "department sensor relay"
	desc = "A hardened camera and sensor uplink to the station director."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "doorctrl"
	density = FALSE
	anchored = TRUE
	max_integrity = 100
	var/station_id
	var/department_id
	var/datum/weakref/defense_runtime_ref
	var/datum/weakref/camera_ref

/// Camera software calls this when it positively identifies an intruder.
/obj/machinery/generated_station_data_relay/proc/report_hostile(atom/contact, confidence = 80)
	var/datum/generated_station_defense_runtime/runtime = defense_runtime_ref?.resolve()
	var/obj/machinery/camera/camera = camera_ref?.resolve()
	if(!runtime || !camera || QDELETED(camera) || (camera.stat & (BROKEN | NOPOWER)) || !can_see(camera, contact, 7))
		return null
	return runtime?.notify_sensor_contact(department_id, contact, "camera relay", confidence)

/obj/machinery/generated_station_data_relay/atom_destruction(damage_flag)
	var/datum/generated_station_simulation/simulation = generated_station_runtime(station_id)
	var/datum/expedition_site/site
	for(var/key in SSexpedition?.sites)
		var/datum/expedition_site/candidate = SSexpedition.sites[key]
		if(candidate.station_simulation == simulation)
			site = candidate
			break
	site?.station_director?.set_department_connected(department_id, FALSE)
	return ..()

/obj/machinery/generated_station_data_relay/Destroy()
	defense_runtime_ref = null
	camera_ref = null
	return ..()

/datum/expedition_site/proc/initialize_generated_station_infrastructure()
	if(!station_spec || !station_materialization || !station_director)
		return FALSE
	for(var/node_id in station_materialization.department_areas)
		var/area/generated_station/A = station_materialization.department_areas[node_id]
		for(var/turf/T in A)
			generated_station_seed_air(T)
	for(var/module_id in station_materialization.module_areas)
		var/area/generated_station/room_area = station_materialization.module_areas[module_id]
		for(var/turf/T in room_area)
			generated_station_seed_air(T)
	for(var/turf/T in station_materialization.transit_area)
		generated_station_seed_air(T)
	for(var/turf/T in station_materialization.maintenance_area)
		generated_station_seed_air(T)
	for(var/datum/generated_station_layout_node/node in station_spec.layout_nodes)
		var/datum/generated_station_department_instance/department
		for(var/datum/generated_station_department_instance/candidate in station_spec.departments)
			if(candidate.id == node.department_instance_id)
				department = candidate
				break
		if(!department)
			continue
		var/area/generated_station/A = station_materialization.department_areas[node.id]
		var/turf/placement
		var/turf/camera_placement
		for(var/turf/T in A)
			if(!T.density && !(locate(/obj/machinery) in T))
				placement = T
				break
		if(!placement)
			continue
		for(var/turf/T in A)
			if(T != placement && !T.density && !(locate(/obj/machinery) in T) && generated_station_adjacent_wall_direction(T))
				camera_placement = T
				break
		if(!camera_placement)
			continue
		var/obj/machinery/generated_station_data_relay/relay = new(placement)
		relay.station_id = station_spec.id
		relay.department_id = department.id
		station_materialization.infrastructure += relay
		var/obj/machinery/camera/camera = new(camera_placement)
		camera.set_dir(turn(generated_station_adjacent_wall_direction(camera_placement), 180))
		relay.camera_ref = WEAKREF(camera)
		station_materialization.infrastructure += camera
	return TRUE
