// Operating condition is owned by the assembly, independently of a machine's
// on/off processing roster. Stable assemblies retain watches but no timer.
GLOBAL_VAR_INIT(next_material_assembly_id, 0)

/datum/gas
	var/material_corrosivity = 0
	var/material_corrosion_temperature = 0

/datum/gas/plasma
	material_corrosivity = 0.03

/datum/gas/miasma
	material_corrosivity = 0.01

/datum/gas/zauker
	material_corrosivity = 0.1

/datum/gas/oxygen
	material_corrosivity = 0.02
	material_corrosion_temperature = 500

/datum/reagent
	/// Percent liner exposure per second, before material resistance.
	var/material_corrosivity = 0

/datum/reagent/acid
	material_corrosivity = 0.8

/datum/reagent/acid/polyacid
	material_corrosivity = 1.6

/proc/material_corrosive_gases()
	var/static/list/types
	if(!types)
		types = list()
		for(var/datum/gas/gas_type as anything in subtypesof(/datum/gas))
			if(initial(gas_type.material_corrosivity))
				types += gas_type
	return types

/obj
	var/datum/material_service/material_service
	var/material_configuration_revision = 0
	var/material_assembly_id
	/// TRUE for player-fabricated or deliberately reconfigured assemblies. Map
	/// defaults remain inspectable without enrolling every machine in exposure.
	var/material_custom_assembly = FALSE
	var/tmp/material_last_service_event

/// Single admission point for material simulation. Callers report a physical
/// event and normalized severity; they never decide lifecycle from their type.
/obj/proc/material_service_event(event, severity = 0, observed_temperature)
	if(!has_functional_construction())
		return
	var/admit = !!material_service || material_custom_assembly
	if(!admit)
		switch(event)
			if(MATERIAL_EVENT_CONFIGURATION)
				admit = material_custom_assembly
			if(MATERIAL_EVENT_MONITORING)
				admit = TRUE
			if(MATERIAL_EVENT_PRESSURE)
				admit = severity >= MATERIAL_PRESSURE_STRESS_RATIO || material_environment_fatigue > 0 || material_environment_leaking
			if(MATERIAL_EVENT_TEMPERATURE)
				admit = severity >= 0.8
			if(MATERIAL_EVENT_CORROSION)
				admit = severity > 0
			if(MATERIAL_EVENT_ELECTRICAL, MATERIAL_EVENT_WORK)
				admit = severity >= 1.1
			if(MATERIAL_EVENT_DAMAGE)
				admit = severity >= 0.5
	if(!admit)
		return
	if(!material_service)
		material_service = new(src)
	material_last_service_event = event
	material_service.last_admission_event = event
	if(isnum(observed_temperature) && observed_temperature > material_service.temperature)
		material_service.temperature = observed_temperature
	material_service.schedule(0)
	return material_service

/// Compatibility entry for explicit test/debug callers. Gameplay integrations
/// must publish a material_service_event() with a physical reason.
/obj/proc/enable_material_service()
	return material_service_event(MATERIAL_EVENT_MONITORING)

/// Observe a pressure boundary using the same admission policy for every tank,
/// pipe, canister, and machine. Composition and thermal hazards share it too.
/obj/proc/material_observe_gases(datum/gas_mixture/internal, datum/gas_mixture/external)
	if(!internal || !has_functional_construction())
		return material_service
	var/internal_temperature = internal.return_temperature()
	var/external_temperature = external?.return_temperature() || TCMB
	var/rating = material_service_rating()
	if(rating > 0)
		var/limit = material_environment_pressure_limit(rating, material_service_radius(), material_service_thickness(), max(internal_temperature, external_temperature))
		var/load_ratio = abs(internal.return_pressure() - (external?.return_pressure() || 0)) / max(limit, ONE_ATMOSPHERE)
		material_service_event(MATERIAL_EVENT_PRESSURE, load_ratio)
	var/corrosion = material_gas_corrosion_load(internal)
	if(external)
		corrosion = max(corrosion, material_gas_corrosion_load(external))
	material_service_event(MATERIAL_EVENT_CORROSION, corrosion)
	var/datum/material/structure = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	if(structure)
		material_service_event(MATERIAL_EVENT_TEMPERATURE, max(internal_temperature, external_temperature) / max(structure.melting_point, 1), max(internal_temperature, external_temperature))
	return material_service

/obj/proc/material_service_can_retire(datum/material_service/service)
	if(!service || material_custom_assembly || service.monitor_tool || service.maintenance_open || service.chemical_rate > 0)
		return FALSE
	if(material_environment_leaking || material_environment_fatigue > 0 || material_environment_liner_integrity < 100 || material_environment_exterior_integrity < 100)
		return FALSE
	var/turf/location = get_turf(src)
	var/datum/gas_mixture/ambient = location?.return_air()
	var/ambient_temperature = ambient?.return_temperature() || T20C
	return abs(service.temperature - ambient_temperature) < MATERIAL_THERMAL_RESOLUTION

/obj/proc/material_service_gases()
	return null

/obj/proc/material_service_rating()
	return 0

/obj/proc/material_service_radius()
	return MATERIAL_CANISTER_REFERENCE_RADIUS

/obj/proc/material_service_thickness()
	return MATERIAL_CANISTER_REFERENCE_THICKNESS

/obj/machinery/atmospherics/material_service_gases()
	var/list/result = list()
	for(var/port in 1 to 4)
		var/datum/gas_mixture/air = rust_pipe_port_air(port)
		if(air)
			result |= air
	return result

/obj/machinery/atmospherics/material_service_rating()
	return 70 * ONE_ATMOSPHERE

/obj/machinery/atmospherics/material_service_radius()
	return MATERIAL_PIPE_REFERENCE_RADIUS

/obj/machinery/atmospherics/material_service_thickness()
	return MATERIAL_PIPE_REFERENCE_THICKNESS

/obj/machinery/atmospherics/pipe/material_service_gases()
	var/datum/gas_mixture/air = return_air()
	return air ? list(air) : null

/obj/machinery/atmospherics/pipe/material_service_rating()
	return maximum_pressure

/obj/machinery/portable_atmospherics/material_service_gases()
	return air_contents ? list(air_contents) : null

/obj/machinery/portable_atmospherics/material_service_rating()
	return maximum_pressure

/obj/item/tank/material_service_gases()
	return air_contents ? list(air_contents) : null

/obj/item/tank/material_service_rating()
	return TANK_RUPTURE_PRESSURE

/obj/item/tank/material_service_radius()
	return MATERIAL_TANK_REFERENCE_RADIUS

/obj/item/tank/material_service_thickness()
	return MATERIAL_TANK_REFERENCE_THICKNESS

/datum/material_service
	var/obj/owner
	var/list/mixture_ids
	/// Last pressure published for each watched mixture. Stable, harmless
	/// pressure jitter updates this cache without waking the physical model.
	var/list/mixture_pressures
	var/list/mixture_corrosion
	var/list/movement_sources
	var/turf/watched_turf
	var/timer
	var/next_update = 0
	var/last_update
	var/temperature = T20C
	var/buffer_energy = 0
	var/chemical_rate = 0
	var/chemical_last_update = 0
	var/input_joules = 0
	var/output_joules = 0
	var/loss_joules = 0
	var/last_input_watts = 0
	var/last_output_watts = 0
	var/last_stress = 0
	var/last_pressure_load = 0
	var/status = "Nominal"
	var/limiting_role
	var/active = FALSE
	var/updating = FALSE
	var/electrical_reference_temperature = T20C
	var/thermal_material_id
	var/datum/material/thermal_stock
	var/datum/material/electrical_stock
	var/thermal_capacity = 1000
	var/watches_dirty = TRUE
	var/last_environment_temperature = T20C
	/// The first observation establishes a baseline. Time spent waiting in the
	/// startup queue is not physical exposure time.
	var/has_sampled = FALSE
	var/last_admission_event

/datum/material_service/New(obj/assembly)
	..()
	owner = assembly
	if(!owner.material_assembly_id)
		owner.material_assembly_id = "ME-[++GLOB.next_material_assembly_id]"
	last_update = world.time
	chemical_last_update = world.time
	initialize_thermal_stock()
	register_diagnostics()
	schedule(1 SECOND)

/datum/material_service/Destroy()
	unregister_diagnostics()
	SSmaterial_services.unqueue(src)
	if(SSmaterial_services.currentrun)
		SSmaterial_services.currentrun -= src
	clear_watches()
	if(owner?.material_service == src)
		owner.material_service = null
	owner = null
	last_delivery_mixture = null
	thermal_stock = null
	electrical_stock = null
	return ..()

/datum/material_service/proc/schedule(delay = MATERIAL_SERVICE_INTERVAL)
	if(QDELETED(owner))
		return
	var/due = world.time + delay
	if(!timer)
		SSmaterial_services.queue(src, due)
		next_update = due
		timer = TRUE
	else
		if(due < next_update)
			next_update = due
			SSmaterial_services.queue(src, due)

/datum/material_service/proc/clear_watches()
	if(watched_turf)
		UnregisterSignal(watched_turf, COMSIG_TURF_CHANGE)
		watched_turf = null
	// om_watch_disarm() keys off this datum's own ref string (code/datums/om/watch.dm), not a
	// weakref, so unlike the old subscribe_gas_dependency() transport there's no QDELETED race
	// to work around here.
	for(var/id in mixture_ids)
		om_watch_disarm(src, "gas[id]")
	mixture_ids = null
	mixture_pressures = null
	mixture_corrosion = null
	for(var/atom/movable/source as anything in movement_sources)
		UnregisterSignal(source, COMSIG_MOVABLE_MOVED)
	movement_sources = null

/datum/material_service/proc/moved()
	SIGNAL_HANDLER
	watches_dirty = TRUE
	environment_changed()

/datum/material_service/proc/changing_turf(datum/source, new_type, list/new_baseturfs, flags, list/post_change_callbacks)
	SIGNAL_HANDLER
	UnregisterSignal(source, COMSIG_TURF_CHANGE)
	watched_turf = null
	watches_dirty = TRUE
	post_change_callbacks += CALLBACK(src, PROC_REF(environment_changed))

/datum/material_service/proc/environment_changed(topology_changed = TRUE)
	// Sleeping means the previous environment had no continuing effect. Do not
	// charge minutes spent asleep against a newly hot or corrosive mixture.
	if(!active && !timer)
		last_update = world.time
	if(topology_changed)
		watches_dirty = TRUE
	schedule(active && !topology_changed ? MATERIAL_SERVICE_INTERVAL : 0)

/// Environmental assemblies care about thermal/composition changes. Pressure is
/// relevant only to pressure-rated objects, so ordinary machine housings do not
/// wake whenever their turf's atmos revision advances.
/datum/material_service/proc/gas_dependency_interest_mask()
	var/mask = GAS_DEPENDENCY_TEMPERATURE | GAS_DEPENDENCY_COMPOSITION
	if(owner.material_service_rating() > 0)
		mask |= GAS_DEPENDENCY_PRESSURE
	return mask

/// Raw forwarder (om_watch_arm_raw(), code/datums/om/watch.dm) for one watched mixture: filters
/// Rust's compact gas publication before entering the exposure queue. This is deliberately a
/// semantic threshold, not a timer: cumulative changes are compared with the cached latest state
/// and a dangerous pressure crossing wakes immediately.
/datum/material_service/proc/on_gas_notify(mixture_id, change_mask, list/observation, observation_index)
	if(gas_notify_actionable(mixture_id, change_mask, observation, observation_index) && !timer)
		environment_changed(FALSE)

/datum/material_service/proc/gas_notify_actionable(mixture_id, change_mask, list/observation, observation_index)
	if(!observation || !observation_index)
		return TRUE
	var/new_pressure = observation[observation_index + 3]
	var/new_temperature = observation[observation_index + 4]
	LAZYINITLIST(mixture_pressures)
	mixture_pressures["[mixture_id]"] = new_pressure
	if(change_mask & GAS_DEPENDENCY_COMPOSITION)
		LAZYINITLIST(mixture_corrosion)
		var/volume = max(observation[observation_index + 5], 1)
		var/corrosive_moles = observation[observation_index + 8] * 0.03 + observation[observation_index + 12] * 0.01 + observation[observation_index + 13] * 0.1
		if(new_temperature >= 500)
			corrosive_moles += observation[observation_index + 6] * 0.02
		var/new_corrosion = corrosive_moles * R_IDEAL_GAS_EQUATION * new_temperature / volume / ONE_ATMOSPHERE * max(0.25, 1 + (new_temperature - T20C) / 600)
		var/old_corrosion = mixture_corrosion["[mixture_id]"] || 0
		mixture_corrosion["[mixture_id]"] = new_corrosion
		if(abs(new_corrosion - old_corrosion) > 0.000001)
			return TRUE
	if((change_mask & GAS_DEPENDENCY_TEMPERATURE) && abs(new_temperature - temperature) >= MATERIAL_THERMAL_RESOLUTION)
		return TRUE
	var/rating = owner.material_service_rating()
	if(!(change_mask & GAS_DEPENDENCY_PRESSURE) || rating <= 0)
		return FALSE
	var/lowest = new_pressure
	var/highest = new_pressure
	for(var/id in mixture_pressures)
		var/pressure = mixture_pressures[id]
		lowest = min(lowest, pressure)
		highest = max(highest, pressure)
	var/limit = owner.material_environment_pressure_limit(rating, owner.material_service_radius(), owner.material_service_thickness(), temperature)
	return owner.material_environment_leaking || (highest - lowest) / max(limit, ONE_ATMOSPHERE) >= MATERIAL_PRESSURE_STRESS_RATIO

/datum/material_service/proc/rebind()
	watches_dirty = FALSE
	var/list/next_ids = list()
	var/list/next_pressures = list()
	var/list/next_corrosion = list()
	var/list/air_ports = owner.material_service_gases()
	var/turf/location = get_turf(owner)
	if(location != watched_turf)
		if(watched_turf)
			UnregisterSignal(watched_turf, COMSIG_TURF_CHANGE)
		watched_turf = location
		if(watched_turf)
			RegisterSignal(watched_turf, COMSIG_TURF_CHANGE, PROC_REF(changing_turf))
	var/datum/gas_mixture/ambient = location?.return_air()
	if(ambient)
		var/ambient_id = ambient.arena_id()
		next_ids |= ambient_id
		next_pressures["[ambient_id]"] = ambient.return_pressure()
		next_corrosion["[ambient_id]"] = material_gas_corrosion_load(ambient)
	for(var/datum/gas_mixture/air as anything in air_ports)
		var/air_id = air.arena_id()
		next_ids |= air_id
		next_pressures["[air_id]"] = air.return_pressure()
		next_corrosion["[air_id]"] = material_gas_corrosion_load(air)
	var/interest_mask = gas_dependency_interest_mask()
	for(var/id in mixture_ids)
		if(!(id in next_ids))
			om_watch_disarm(src, "gas[id]")
	for(var/id in next_ids)
		if(!(id in mixture_ids))
			om_watch_arm_raw(src, "gas[id]", id, interest_mask, CALLBACK(src, PROC_REF(on_gas_notify)))
	mixture_ids = next_ids
	mixture_pressures = next_pressures
	mixture_corrosion = next_corrosion
	var/list/next_sources = list()
	var/atom/movable/location_source = owner
	while(istype(location_source))
		next_sources += location_source
		location_source = location_source.loc
	for(var/atom/movable/source as anything in movement_sources)
		if(!(source in next_sources))
			UnregisterSignal(source, COMSIG_MOVABLE_MOVED)
	for(var/atom/movable/source as anything in next_sources)
		if(!(source in movement_sources))
			RegisterSignal(source, COMSIG_MOVABLE_MOVED, PROC_REF(moved))
	movement_sources = next_sources

/datum/material_service/proc/contents_changed()
	if(QDELETED(owner))
		return
	settle_chemical()
	if(QDELETED(owner))
		return
	chemical_rate = 0
	var/datum/material/liner = owner.material_for_role(MATERIAL_ROLE_LINER)
	if(liner && owner.reagents?.total_volume)
		for(var/datum/reagent/chemical in owner.reagents.reagent_list)
			chemical_rate += liner.material_corrosion_rate(chemical.id, temperature) * chemical.volume / owner.reagents.total_volume
	if(chemical_rate)
		schedule()

/datum/material_service/proc/settle_chemical()
	var/elapsed = max(0, (world.time - chemical_last_update) / 10)
	chemical_last_update = world.time
	if(chemical_rate && elapsed)
		owner.material_environment_liner_integrity = max(0, owner.material_environment_liner_integrity - chemical_rate * elapsed)
		if(owner.material_environment_liner_integrity <= 0)
			chemical_rate = 0
			owner.material_environment_rupture()

/datum/material_service/proc/thermal_mass()
	return thermal_capacity

/datum/material_service/proc/initialize_thermal_stock()
	var/datum/material/thermal = owner.material_for_role(MATERIAL_ROLE_THERMAL) || owner.primary_construction_material()
	thermal_stock = thermal
	electrical_stock = owner.material_for_role(MATERIAL_ROLE_CONDUCTOR)
	thermal_capacity = max((thermal?.specific_heat || 125) * MATERIAL_SERVICE_REFERENCE_MASS, 1000)
	if(thermal_material_id == thermal?.name)
		return
	thermal_material_id = thermal?.name
	// Fresh stock is at the assembly temperature. A cryogenic phase material
	// starts discharged at room temperature and must actually be cooled first.
	buffer_energy = thermal?.phase_change_temperature && temperature >= thermal.phase_change_temperature ? thermal.phase_change_capacity : 0

/// Positive heat enters this solid, negative heat leaves. Phase storage belongs
/// to this assembly and survives material recalculation.
/datum/material_service/proc/add_heat(joules)
	if(!joules || QDELETED(owner))
		return 0
	var/datum/material/thermal = thermal_stock
	var/mass = thermal_mass()
	var/old_temperature = temperature
	var/phase = thermal?.phase_change_temperature || 0
	var/capacity = thermal?.phase_change_capacity || 0
	var/accepted = joules
	if(joules > 0 && phase > 0 && capacity > buffer_energy)
		var/to_phase = max(0, phase - temperature) * mass
		var/sensible = min(joules, to_phase)
		temperature += sensible / mass
		joules -= sensible
		if(temperature >= phase)
			var/buffered = min(joules, capacity - buffer_energy)
			buffer_energy += buffered
			joules -= buffered
	else if(joules < 0 && buffer_energy > 0)
		var/above_phase = max(temperature - phase, 0) * mass
		var/sensible = min(-joules, above_phase)
		temperature -= sensible / mass
		joules += sensible
		var/released = min(-joules, buffer_energy)
		buffer_energy -= released
		joules += released
	var/minimum_heat = (TCMB - temperature) * mass
	if(joules < minimum_heat)
		accepted -= minimum_heat - joules
		joules = minimum_heat
	temperature += joules / mass
	if(temperature != old_temperature && owner.reagents?.total_volume)
		// Temperature is an input to chemical attack. Settle the previous rate
		// and publish the new one at the mutation, not at the next reagent edit.
		contents_changed()
	if(istype(owner, /obj/structure/cable))
		var/obj/structure/cable/cable = owner
		var/datum/material/conductor = electrical_stock
		var/crossed_critical = conductor?.critical_temperature && ((temperature < conductor.critical_temperature) != (electrical_reference_temperature < conductor.critical_temperature))
		if(abs(temperature - electrical_reference_temperature) >= 0.1 || crossed_critical)
			if(cable.powernet?.material_graph)
				cable.powernet.material_graph.invalidate_cable(cable)
			electrical_reference_temperature = temperature
	// Retain sub-resolution heat in the solid instead of scheduling every cable
	// for fractions of a millikelvin. No energy is discarded by this coalescing.
	if(active || monitor_tool || abs(temperature - last_environment_temperature) >= MATERIAL_THERMAL_RESOLUTION)
		schedule()
	return accepted

/datum/material_service/proc/tick()
	SSmaterial_services.unqueue(src)
	timer = null
	advance()

/datum/material_service/proc/advance()
	if(updating || QDELETED(owner))
		return
	updating = TRUE
	var/elapsed = has_sampled ? clamp((world.time - last_update) / 10, 0, MATERIAL_SERVICE_MAX_ELAPSED) : 0
	has_sampled = TRUE
	settle_chemical()
	last_update = world.time
	if(QDELETED(owner))
		updating = FALSE
		return
	if(watches_dirty)
		rebind()
	var/turf/location = get_turf(owner)
	var/datum/gas_mixture/ambient = location?.return_air()
	active = chemical_rate > 0
	var/datum/material/thermal_output = owner.material_for_role(MATERIAL_ROLE_THERMAL) || owner.primary_construction_material()
	if(elapsed > 0 && thermal_output?.exothermic_heat_rate > 0)
		add_heat(thermal_output.exothermic_heat_rate * elapsed)
		active = TRUE
	var/list/air_ports = owner.material_service_gases()
	var/datum/gas_mixture/highest_load_port
	var/highest_pressure_delta = -1
	var/ambient_pressure = ambient?.return_pressure() || 0
	for(var/datum/gas_mixture/air as anything in air_ports)
		var/delta = abs(air.return_pressure() - ambient_pressure)
		if(delta > highest_pressure_delta)
			highest_pressure_delta = delta
			highest_load_port = air
	var/rating = owner.material_service_rating()
	var/effective_limit = rating > 0 ? owner.material_environment_pressure_limit(rating, owner.material_service_radius(), owner.material_service_thickness(), temperature) : 0
	last_pressure_load = effective_limit > 0 ? highest_pressure_delta / effective_limit : 0
	for(var/datum/gas_mixture/air as anything in air_ports)
		active = owner.process_material_environment(air, ambient, elapsed, owner.material_service_rating(), owner.material_service_radius(), owner.material_service_thickness(), air == highest_load_port, TRUE, 1 / length(air_ports)) || active
		if(!QDELETED(owner) && owner.material_service_conducts_contents())
			active = exchange_with_gas(air, elapsed / length(air_ports)) || active
		if(QDELETED(owner))
			updating = FALSE
			return
	if(!length(air_ports))
		active = owner.process_material_exterior(ambient, elapsed) || active
	if(QDELETED(owner))
		updating = FALSE
		return
	if(ambient && elapsed > 0)
		var/ambient_capacity = ambient.heat_capacity()
		var/conductance = owner.construction_thermal_conductance(0.1, 0.004, temperature) || 0
		if(ambient_capacity > 0 && conductance > 0)
			var/equilibrium = (temperature - ambient.return_temperature()) / (1 / thermal_mass() + 1 / ambient_capacity)
			var/exchange = equilibrium * (1 - 2.718281828 ** (-conductance * elapsed * (1 / thermal_mass() + 1 / ambient_capacity)))
			if(abs(temperature - ambient.return_temperature()) >= MATERIAL_THERMAL_RESOLUTION && abs(exchange) > 0.01)
				var/converted = convert_transferred_heat(exchange, ambient.return_temperature())
				if(exchange > 0)
					ambient.add_thermal_energy(-add_heat(-exchange) - converted)
				else
					ambient.add_thermal_energy(-add_heat(-exchange - converted) - converted)
				active = TRUE
	var/datum/material/structure = owner.material_for_role(MATERIAL_ROLE_STRUCTURE) || owner.primary_construction_material()
	last_stress = structure ? temperature / max(structure.melting_point, 1) : 0
	status = owner.material_environment_leaking ? "Leaking" : (last_stress >= 1 ? "Overheated" : (last_pressure_load >= MATERIAL_PRESSURE_FATIGUE_RATIO ? "Pressure fatigue" : (last_pressure_load >= MATERIAL_PRESSURE_STRESS_RATIO ? "Pressure stress" : (last_stress > 0.8 ? "Thermal stress" : "Nominal"))))
	if(last_stress >= 1 && elapsed > 0)
		owner.take_damage((last_stress - 0.9) * 5 * elapsed, BURN, FIRE)
		active = TRUE
	updating = FALSE
	last_environment_temperature = temperature
	active = sample_observation() || active
	if(active)
		schedule(monitor_tool ? 1 SECOND : MATERIAL_SERVICE_INTERVAL)
	else if(owner.material_service_can_retire(src))
		qdel(src)

/obj/proc/material_service_conducts_contents()
	return TRUE

// Dedicated heat-exchange pipes retain their existing gas/turf/radiation
// transfer path. The service still owns their corrosion and pressure wear.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/material_service_conducts_contents()
	return FALSE

/datum/material_service/proc/exchange_with_gas(datum/gas_mixture/air, elapsed)
	if(!air || elapsed <= 0 || air.heat_capacity() <= 0)
		return FALSE
	if(abs(air.return_temperature() - temperature) < MATERIAL_THERMAL_RESOLUTION)
		return FALSE
	var/capacity = air.heat_capacity()
	var/conductance = owner.construction_thermal_conductance(0.25, max(owner.material_service_thickness() / 1000, 0.001), temperature) || 0
	var/equilibrium = (air.return_temperature() - temperature) / (1 / thermal_mass() + 1 / capacity)
	var/exchange = equilibrium * (1 - 2.718281828 ** (-conductance * elapsed * (1 / thermal_mass() + 1 / capacity)))
	if(abs(exchange) < 0.01)
		return FALSE
	air.add_thermal_energy(-add_heat(exchange))
	return TRUE

/// A thermoelectric cell converts only a fraction of actual hot-to-cold heat
/// flow, bounded by Carnot efficiency and available charge capacity.
/datum/material_service/proc/convert_transferred_heat(heat, ambient_temperature)
	if(!istype(owner, /obj/item/cell) || !heat)
		return 0
	var/obj/item/cell/cell = owner
	var/datum/material/conductor = owner.material_for_role(MATERIAL_ROLE_CONDUCTOR)
	if(!conductor?.thermoelectric_coefficient)
		return 0
	var/hot = max(temperature, ambient_temperature, TCMB)
	var/cold = min(temperature, ambient_temperature)
	var/efficiency = min(clamp(conductor.thermoelectric_coefficient, 0, 1), 1 - cold / hot)
	var/converted = min(abs(heat) * efficiency, cell.amount_missing() / CELLRATE)
	return cell.give(converted * CELLRATE) / CELLRATE

/datum/material_service/proc/summary()
	return "[status]. Assembly [round(temperature, 0.1)] K; pressure load [round(last_pressure_load * 100, 0.1)]%; thermal buffer [round(buffer_energy)] J. Liner [round(owner.material_environment_liner_integrity)]%, exterior [round(owner.material_environment_exterior_integrity)]%. Fatigue [round(owner.material_environment_fatigue)]%."

/obj/proc/material_service_changed()
	material_configuration_revision++
	if(istype(src, /obj/structure/cable))
		var/obj/structure/cable/cable = src
		cable.powernet?.material_graph?.invalidate_cable(cable)
	if(istype(src, /obj/machinery/atmospherics))
		var/obj/machinery/atmospherics/device = src
		if(device.power_rating > 0)
			device.ensure_pump_materials(FALSE)
	else if(istype(src, /obj/machinery/portable_atmospherics/powered))
		var/obj/machinery/portable_atmospherics/powered/device = src
		device.ensure_pump_materials(FALSE)
	// Ordinary mapped machinery keeps its established integrity behavior. Only
	// objects with a physical pressure, chemical, electrical, or energy-storage
	// role need a continuously observable material assembly.
	material_service_event(MATERIAL_EVENT_CONFIGURATION)
	material_service?.initialize_thermal_stock()
	if(material_service)
		material_service.watches_dirty = TRUE
	material_service?.schedule(0)
