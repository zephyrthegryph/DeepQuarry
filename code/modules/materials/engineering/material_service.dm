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

/proc/build_material_corrosive_gases()
	var/list/types = list()
	for(var/datum/gas/gas_type as anything in subtypesof(/datum/gas))
		if(initial(gas_type.material_corrosivity))
			types += gas_type
	return types

GLOBAL_TABLE(material_corrosive_gases, GLOBAL_PROC_REF(build_material_corrosive_gases))

// An object's service, diagnostics identity, wear and fabricated flag are its /datum/material_assembly
// (material_state.dm); material_service_of() reads the service.

/// Single admission point for material simulation. Callers report a physical
/// event and normalized severity; they never decide lifecycle from their type.
/obj/proc/material_service_event(event, severity = 0, observed_temperature)
	if(!has_functional_construction())
		return
	var/datum/material_assembly/state = material_assembly_view(src)
	var/admit = !!state.service || state.custom
	if(!admit)
		switch(event)
			if(MATERIAL_EVENT_CONFIGURATION)
				admit = state.custom
			if(MATERIAL_EVENT_MONITORING)
				admit = TRUE
			if(MATERIAL_EVENT_PRESSURE)
				admit = severity >= MATERIAL_PRESSURE_STRESS_RATIO || state.fatigue > 0 || state.leaking
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
	var/first_sample = 0
	var/datum/material_assembly/assembly = material_assembly(src)
	if(!assembly.service)
		rel_set(assembly, nameof(assembly.service), new /datum/material_service(src))
		// Services admitted while the world initializes (every power cell, pipes seeing their
		// first pressure) take their baseline sample spread over the first seconds after boot
		// rather than all on the first tick.
		if(!Kernel.current_runlevel)
			first_sample = rand(0, MATERIAL_SERVICE_BOOT_SPREAD)
	assembly.last_event = event
	var/datum/material_service/service = assembly.service
	service.last_admission_event = event
	if(isnum(observed_temperature) && observed_temperature > service.temperature())
		heat_store_set_temperature(service.heat_store, observed_temperature, HEAT_SOURCE_MATERIAL) // it saw something this hot
	service.schedule(first_sample)
	return service

/// Compatibility entry for explicit test/debug callers. Gameplay integrations
/// must publish a material_service_event() with a physical reason.
/obj/proc/enable_material_service()
	return material_service_event(MATERIAL_EVENT_MONITORING)

/// Observe a pressure boundary using the same admission policy for every tank,
/// pipe, canister, and machine. Composition and thermal hazards share it too.
/obj/proc/material_observe_gases(datum/gas_mixture/internal, datum/gas_mixture/external)
	if(!internal || !has_functional_construction())
		return material_service_of(src)
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
	return material_service_of(src)

/obj/proc/material_service_can_retire(datum/material_service/service)
	var/datum/material_assembly/state = material_assembly_view(src)
	if(!service || state.custom || service.monitor_tool || service.maintenance_open || service.chemical_rate > 0)
		return FALSE
	if(state.leaking || state.fatigue > 0 || state.liner_integrity < 100 || state.exterior_integrity < 100)
		return FALSE
	var/turf/location = get_turf(src)
	var/datum/gas_mixture/ambient = location?.return_air()
	var/ambient_temperature = ambient?.return_temperature() || T20C
	return abs(service.temperature() - ambient_temperature) < MATERIAL_THERMAL_RESOLUTION

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
	var/tmp/obj/owner
	var/list/mixture_ids
	/// One native gas watch per watched mixture (code/domains/atmos/gas_watch.dm): Rust reports each change of the gas the assembly sits in or holds.
	var/list/datum/native_watch/gas/gas_watches
	/// Last pressure published for each watched mixture. Stable, harmless
	/// pressure jitter updates this cache without waking the physical model.
	var/list/mixture_pressures
	var/list/mixture_corrosion
	var/list/movement_sources
	var/tmp/turf/watched_turf
	var/timer
	var/next_update = 0
	var/last_update
	/// The assembly's heat: a Rust heat store (code/domains/heat/heat_store.dm) of its thermal stock, with its phase plateau.
	var/heat_store
	/// Its heat link (or, for a thermoelectric conductor, heat engine) to its turf's air, and its links to the gas it holds.
	var/ambient_link
	var/list/port_links
	var/ambient_engine = FALSE
	var/chemical_rate = 0
	EXPIRY_DECLARE(chemical_last_update)
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
	var/tmp/datum/material/thermal_stock_static
	var/tmp/datum/material/electrical_stock_static
	var/thermal_capacity = 1000
	var/watches_dirty = TRUE
	var/last_environment_temperature = T20C
	/// The first observation establishes a baseline. Time spent waiting in the
	/// startup queue is not physical exposure time.
	var/has_sampled = FALSE
	var/last_admission_event

/datum/material_service/New(obj/holder)
	..()
	rel_set(src, nameof(owner), holder)
	var/datum/material_assembly/assembly = material_assembly(holder)
	if(!assembly.assembly_id)
		assembly.assembly_id = "ME-[++GLOB.next_material_assembly_id]"
	EXPIRY_STAMP(src, last_update, CLOCK_WORLD)
	EXPIRY_STAMP(src, chemical_last_update, CLOCK_WORLD)
	initialize_thermal_stock()
	register_diagnostics()
	// Not scheduled here: material_service_event(), the only creator, schedules the first
	// sample right after. A 1 s deadline here was superseded at once, leaving a stale wheel
	// entry per service (about 1,400 at boot, one per power cell and admitted pipe).

// unregisters diagnostics and its service timer; its owner forgets it.
/datum/material_service/on_destroy(force)
	drop_heat_links()
	if(heat_store)
		heat_store_release(heat_store)
		heat_store = null
	var/datum/destroy_batch/batch = GLOB.dq_destroy_batch
	if(batch && (batch.doomed[src] || batch.doomed[owner()]))
		// Batched destroy (doc/rewrite/init_and_turfs.md sec 4.4 step 6): no hook is unhooked one by one --
		// this service's own teardown (its activations end with it) drops every observe()
		// it holds, on the doomed owner and on its turf and holders alike.
		gas_watch_many_clear(src, nameof(gas_watches))
		rel_clear(src, nameof(monitor_tool))
		rel_clear(src, nameof(monitor_user))
		last_reading = null
		rel_clear(src, nameof(watched_turf))
		mixture_ids = null
		mixture_pressures = null
		mixture_corrosion = null
		movement_sources = null
		..()
		return
	unregister_diagnostics()
	clear_watches()
	..()

/datum/material_service/proc/schedule(delay = MATERIAL_SERVICE_INTERVAL)
	if(QDELETED(owner()))
		return
	var/due = world.time + delay
	if(!timer)
		after(src, delay, PROC_REF(service_due), key = "material_service")
		next_update = due
		timer = TRUE
	else
		if(due < next_update)
			next_update = due
			after(src, delay, PROC_REF(service_due), key = "material_service")

/datum/material_service/proc/clear_watches()
	if(watched_turf())
		unobserve(watched_turf(), /datum/notice/turf_change, src)
		rel_clear(src, nameof(watched_turf))
	gas_watch_many_clear(src, nameof(gas_watches))
	mixture_ids = null
	mixture_pressures = null
	mixture_corrosion = null
	for(var/atom/movable/source as anything in movement_sources)
		unobserve(source, /datum/notice/moved, src)
	movement_sources = null

/datum/material_service/proc/moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	watches_dirty = TRUE
	environment_changed()

/datum/material_service/proc/changing_turf(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	var/datum/notice/turf_change/event = A
	var/list/post_change_callbacks = event.post_change_callbacks
	unobserve(source, /datum/notice/turf_change, src)
	rel_clear(src, nameof(watched_turf))
	watches_dirty = TRUE
	post_change_callbacks += list(om_callable(src, PROC_REF(environment_changed)))

/datum/material_service/proc/environment_changed(topology_changed = TRUE)
	// Sleeping means the previous environment had no continuing effect. Do not
	// charge minutes spent asleep against a newly hot or corrosive mixture.
	if(!active && !timer)
		EXPIRY_STAMP(src, last_update, CLOCK_WORLD)
	if(topology_changed)
		watches_dirty = TRUE
	schedule(active && !topology_changed ? MATERIAL_SERVICE_INTERVAL : 0)

/// Environmental assemblies care about thermal/composition changes. Pressure is
/// relevant only to pressure-rated objects, so ordinary machine housings do not
/// wake whenever their turf's atmos revision advances.
/datum/material_service/proc/gas_dependency_interest_mask()
	var/mask = GAS_DEPENDENCY_TEMPERATURE | GAS_DEPENDENCY_COMPOSITION
	if(owner().material_service_rating() > 0)
		mask |= GAS_DEPENDENCY_PRESSURE
	return mask

/// The handler of the assembly's gas watches (gas_watch_ids()), one per watched mixture: filters
/// Rust's compact gas publication before entering the exposure queue. This is deliberately a
/// semantic threshold, not a timer: cumulative changes are compared with the cached latest state
/// and a dangerous pressure crossing wakes immediately.
/datum/material_service/proc/on_gas_notify(datum/native_watch/gas/watch, mixture_id, change_mask, list/observation, observation_index)
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
	if((change_mask & GAS_DEPENDENCY_TEMPERATURE) && abs(new_temperature - temperature()) >= MATERIAL_THERMAL_RESOLUTION)
		return TRUE
	var/rating = owner().material_service_rating()
	if(!(change_mask & GAS_DEPENDENCY_PRESSURE) || rating <= 0)
		return FALSE
	var/lowest = new_pressure
	var/highest = new_pressure
	for(var/id in mixture_pressures)
		var/pressure = mixture_pressures[id]
		lowest = min(lowest, pressure)
		highest = max(highest, pressure)
	var/limit = owner().material_environment_pressure_limit(rating, owner().material_service_radius(), owner().material_service_thickness(), temperature())
	return material_assembly_view(owner()).leaking || (highest - lowest) / max(limit, ONE_ATMOSPHERE) >= MATERIAL_PRESSURE_STRESS_RATIO

/datum/material_service/proc/rebind()
	watches_dirty = FALSE
	var/list/next_ids = list()
	var/list/next_pressures = list()
	var/list/next_corrosion = list()
	var/list/air_ports = owner().material_service_gases()
	var/turf/location = get_turf(owner())
	if(location != watched_turf())
		if(watched_turf())
			unobserve(watched_turf(), /datum/notice/turf_change, src)
		rel_set(src, nameof(watched_turf), location)
		if(watched_turf())
			observe(watched_turf(), /datum/notice/turf_change, src, then(PROC_REF(changing_turf)))
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
	var/list/watched_ids = mixture_ids || list()
	if(length(next_ids ^ watched_ids))
		gas_watch_ids(src, nameof(gas_watches), next_ids, gas_dependency_interest_mask(), PROC_REF(on_gas_notify))
	mixture_ids = next_ids
	mixture_pressures = next_pressures
	mixture_corrosion = next_corrosion
	var/list/next_sources = list()
	var/atom/movable/location_source = owner()
	while(istype(location_source))
		next_sources += location_source
		location_source = location_source.loc
	for(var/atom/movable/source as anything in movement_sources)
		if(!(source in next_sources))
			unobserve(source, /datum/notice/moved, src)
	for(var/atom/movable/source as anything in next_sources)
		if(!(source in movement_sources))
			observe(source, /datum/notice/moved, src, then(PROC_REF(moved)))
	movement_sources = next_sources
	rebuild_heat_links(location)

/datum/material_service/proc/contents_changed()
	if(QDELETED(owner()))
		return
	settle_chemical()
	if(QDELETED(owner()))
		return
	chemical_rate = 0
	var/datum/material/liner = owner().material_for_role(MATERIAL_ROLE_LINER)
	if(liner && owner().reagents?.total_volume)
		for(var/datum/reagent/chemical in owner().reagents.reagent_list)
			chemical_rate += liner.corrosion_rate(chemical.id, temperature()) * chemical.volume / owner().reagents.total_volume
	if(chemical_rate)
		schedule()

/datum/material_service/proc/settle_chemical()
	var/elapsed = max(0, (world.time - chemical_last_update) / 10)
	EXPIRY_STAMP(src, chemical_last_update, CLOCK_WORLD)
	if(chemical_rate && elapsed)
		var/datum/material_assembly/wear = material_assembly(owner())
		wear.liner_integrity = max(0, wear.liner_integrity - chemical_rate * elapsed)
		if(wear.liner_integrity <= 0)
			chemical_rate = 0
			owner().material_environment_rupture()

/datum/material_service/proc/thermal_mass()
	return thermal_capacity

/datum/material_service/proc/initialize_thermal_stock()
	var/datum/material/thermal = owner().material_for_role(MATERIAL_ROLE_THERMAL) || owner().primary_construction_material()
	thermal_stock_static = thermal
	electrical_stock_static = owner().material_for_role(MATERIAL_ROLE_CONDUCTOR)
	thermal_capacity = max((thermal?.specific_heat || 125) * MATERIAL_SERVICE_REFERENCE_MASS, 1000)
	if(!heat_store)
		heat_store = heat_store_create(thermal_capacity, T20C)
	else
		heat_store_set_capacity(heat_store, thermal_capacity)
	// An exothermic stock is a heat source for as long as the assembly is in service.
	heat_store_set_power(heat_store, thermal?.exothermic_heat_rate || 0)
	if(thermal_material_id == thermal?.name)
		return
	thermal_material_id = thermal?.name
	// Fresh stock is at the assembly temperature. A cryogenic phase material starts discharged at room temperature (its plateau's latent
	// heat held) and must actually be cooled first.
	heat_store_set_phase(heat_store, thermal?.phase_change_temperature || 0, thermal?.phase_change_capacity || 0)

/// The assembly's temperature, K.
/datum/material_service/proc/temperature()
	return heat_store_temperature(heat_store)

/// The heat its phase plateau holds, J.
/datum/material_service/proc/buffer_energy()
	return heat_store_latent(heat_store)

/// Positive heat enters this solid, negative heat leaves, booked under `source`. Phase storage belongs to this assembly and survives material
/// recalculation. Returns the joules accepted (the solid never goes below TCMB).
/datum/material_service/proc/add_heat(joules, source = HEAT_SOURCE_DEVICE)
	if(!joules || QDELETED(owner()))
		return 0
	var/old_temperature = temperature()
	var/accepted = heat_store_add(heat_store, joules, source)
	temperature_moved(old_temperature)
	return accepted

/// The assembly's temperature moved from `old_temperature`: what reads it hears.
/datum/material_service/proc/temperature_moved(old_temperature)
	var/now = temperature()
	if(now != old_temperature && owner().reagents?.total_volume)
		// Temperature is an input to chemical attack. Settle the previous rate
		// and publish the new one at the mutation, not at the next reagent edit.
		contents_changed()
	if(istype(owner(), /obj/structure/cable))
		var/obj/structure/cable/cable = owner()
		var/datum/material/conductor = electrical_stock()
		var/crossed_critical = conductor?.critical_temperature && ((now < conductor.critical_temperature) != (electrical_reference_temperature < conductor.critical_temperature))
		if(abs(now - electrical_reference_temperature) >= 0.1 || crossed_critical)
			if(cable.material_overlay?.material_graph)
				cable.material_overlay.material_graph.invalidate_cable(cable)
			electrical_reference_temperature = now
	// Retain sub-resolution heat in the solid instead of scheduling every cable
	// for fractions of a millikelvin. No energy is discarded by this coalescing.
	if(active || monitor_tool || abs(now - last_environment_temperature) >= MATERIAL_THERMAL_RESOLUTION)
		schedule()

/// The heat links of the assembly where it is: to its turf's air through its exterior (a heat engine when its conductor is thermoelectric:
/// part of the heat that flows becomes charge), and to the gas it holds through its wall. Rust moves the heat every world step.
/datum/material_service/proc/rebuild_heat_links(turf/location)
	drop_heat_links()
	if(!heat_store || QDELETED(owner()))
		return
	if(location?.return_air())
		var/conductance = ambient_conductance()
		var/efficiency = thermoelectric_efficiency()
		ambient_engine = !isnull(efficiency)
		ambient_link = ambient_engine ? heat_store_engine(heat_store, location, efficiency, conductance) : heat_store_link(heat_store, location, conductance)
	if(!owner().material_service_conducts_contents())
		return
	var/list/ports = owner().material_service_heat_ports()
	var/share = port_conductance() / max(length(ports), 1)
	for(var/list/port as anything in ports)
		var/id = heat_store_link(heat_store, port, share)
		if(id)
			LAZYADD(port_links, id)

/datum/material_service/proc/drop_heat_links()
	if(ambient_link)
		vg_heat_edge_remove(ambient_link)
		ambient_link = null
	for(var/id in port_links)
		vg_heat_edge_remove(id)
	port_links = null

/// Conductance of the exterior to the air, W/K, at the assembly's temperature.
/datum/material_service/proc/ambient_conductance()
	return owner().construction_thermal_conductance(0.1, 0.004, temperature()) || 0

/// Conductance of the wall to the gas it holds, W/K, at the assembly's temperature.
/datum/material_service/proc/port_conductance()
	return owner().construction_thermal_conductance(0.25, max(owner().material_service_thickness() / 1000, 0.001), temperature()) || 0

/// A cell's thermoelectric conductor converts this fraction of the heat that flows to charge (capped at Carnot by the engine), or null when
/// it has none. A full cell converts nothing.
/datum/material_service/proc/thermoelectric_efficiency()
	if(!istype(owner(), /obj/item/cell))
		return null
	var/datum/material/conductor = owner().material_for_role(MATERIAL_ROLE_CONDUCTOR)
	if(!conductor?.thermoelectric_coefficient)
		return null
	var/obj/item/cell/cell = owner()
	return cell.amount_missing() > 0 ? clamp(conductor.thermoelectric_coefficient, 0, 1) : 0

/// Brings the links' conductances to the assembly's temperature now, and pays a thermoelectric engine's work into the cell (what the cell
/// cannot take goes back into the assembly as heat). Returns TRUE while heat still flows.
/datum/material_service/proc/refresh_heat_links(datum/gas_mixture/ambient)
	if(ambient_link)
		vg_heat_edge_set(ambient_link, HEAT_PARAM_CONDUCTANCE, ambient_conductance())
		if(ambient_engine)
			var/work = -(vg_heat_edge_take_work(ambient_link) || 0)
			if(work > 0)
				var/obj/item/cell/cell = owner()
				var/stored = cell.give(work * CELLRATE) / CELLRATE
				if(work - stored > 0)
					heat_store_add(heat_store, work - stored, HEAT_SOURCE_DEVICE)
			vg_heat_edge_set(ambient_link, HEAT_PARAM_EFFICIENCY, thermoelectric_efficiency() || 0)
	var/share = length(port_links) ? port_conductance() / length(port_links) : 0
	for(var/id in port_links)
		vg_heat_edge_set(id, HEAT_PARAM_CONDUCTANCE, share)
	var/now = temperature()
	if(ambient && abs(now - ambient.return_temperature()) >= MATERIAL_THERMAL_RESOLUTION)
		return TRUE
	if(length(port_links))
		for(var/datum/gas_mixture/air as anything in owner().material_service_gases())
			if(air.heat_capacity() > 0 && abs(air.return_temperature() - now) >= MATERIAL_THERMAL_RESOLUTION)
				return TRUE
	return FALSE

/// At its surroundings' temperature, before it retires: what it still holds over its air's temperature goes to the air.
/datum/material_service/proc/settle_heat()
	var/turf/location = get_turf(owner())
	if(heat_store && location?.return_air())
		heat_equalize(HEAT_STORE(heat_store), location)

/datum/material_service/proc/tick()
	cancel_after(src, "material_service")
	timer = null
	advance()

/// Material exposure work: one keyed after() per service (was SSmaterial_services' heap, then an OM deadline).
/// Setting it again moves it; deletion cancels it with the entity.
/datum/material_service/proc/service_due()
	if(QDELETED(src))
		return
	timer = FALSE
	advance()

/datum/material_service/proc/advance()
	if(updating || QDELETED(owner()))
		return
	updating = TRUE
	var/elapsed = has_sampled ? clamp((world.time - last_update) / 10, 0, MATERIAL_SERVICE_MAX_ELAPSED) : 0
	has_sampled = TRUE
	settle_chemical()
	EXPIRY_STAMP(src, last_update, CLOCK_WORLD)
	if(QDELETED(owner()))
		updating = FALSE
		return
	if(watches_dirty)
		rebind()
	var/turf/location = get_turf(owner())
	var/datum/gas_mixture/ambient = location?.return_air()
	active = chemical_rate > 0
	var/old_temperature = last_environment_temperature
	// An exothermic stock heats itself (its heat store's power, initialize_thermal_stock()).
	if(thermal_stock()?.exothermic_heat_rate > 0)
		active = TRUE
	var/list/air_ports = owner().material_service_gases()
	var/datum/gas_mixture/highest_load_port
	var/highest_pressure_delta = -1
	var/ambient_pressure = ambient?.return_pressure() || 0
	for(var/datum/gas_mixture/air as anything in air_ports)
		var/delta = abs(air.return_pressure() - ambient_pressure)
		if(delta > highest_pressure_delta)
			highest_pressure_delta = delta
			highest_load_port = air
	var/rating = owner().material_service_rating()
	var/effective_limit = rating > 0 ? owner().material_environment_pressure_limit(rating, owner().material_service_radius(), owner().material_service_thickness(), temperature()) : 0
	last_pressure_load = effective_limit > 0 ? highest_pressure_delta / effective_limit : 0
	for(var/datum/gas_mixture/air as anything in air_ports)
		active = owner().process_material_environment(air, ambient, elapsed, owner().material_service_rating(), owner().material_service_radius(), owner().material_service_thickness(), air == highest_load_port, TRUE, 1 / length(air_ports)) || active
		if(QDELETED(owner()))
			updating = FALSE
			return
	if(!length(air_ports))
		active = owner().process_material_exterior(ambient, elapsed) || active
	if(QDELETED(owner()))
		updating = FALSE
		return
	// The heat itself moves in Rust through the assembly's heat links (rebuild_heat_links()); the sample keeps their conductances at the
	// assembly's temperature, pays a thermoelectric engine's work, and stays awake while heat still flows.
	active = refresh_heat_links(ambient) || active
	temperature_moved(old_temperature)
	var/datum/material/structure = owner().material_for_role(MATERIAL_ROLE_STRUCTURE) || owner().primary_construction_material()
	last_stress = structure ? temperature() / max(structure.melting_point, 1) : 0
	status = material_assembly_view(owner()).leaking ? "Leaking" : (last_stress >= 1 ? "Overheated" : (last_pressure_load >= MATERIAL_PRESSURE_FATIGUE_RATIO ? "Pressure fatigue" : (last_pressure_load >= MATERIAL_PRESSURE_STRESS_RATIO ? "Pressure stress" : (last_stress > 0.8 ? "Thermal stress" : "Nominal"))))
	if(last_stress >= 1 && elapsed > 0)
		owner().take_damage((last_stress - 0.9) * 5 * elapsed, BURN, FIRE)
		active = TRUE
	updating = FALSE
	last_environment_temperature = temperature()
	active = sample_observation() || active
	if(active)
		schedule(monitor_tool ? 1 SECOND : MATERIAL_SERVICE_INTERVAL)
	else if(owner().material_service_can_retire(src))
		settle_heat()
		spent(src)

/obj/proc/material_service_conducts_contents()
	return TRUE

// Dedicated heat-exchange pipes retain their existing gas/turf/radiation
// transfer path. The service still owns their corrosion and pressure wear.
/obj/machinery/atmospherics/pipe/simple/heat_exchanging/material_service_conducts_contents()
	return FALSE

/// The gas the assembly's wall touches, as heat reservoirs (list(HEAT_TARGET_*, ref) each): the mixtures it holds.
/obj/proc/material_service_heat_ports()
	. = list()
	for(var/datum/gas_mixture/air as anything in material_service_gases())
		. += list(list(HEAT_TARGET_MIXTURE, air))

/// A pipe machine's wall touches the gas of the pipelines its ports are in, followed through merges and splits.
/obj/machinery/atmospherics/material_service_heat_ports()
	. = list()
	for(var/port_id in rust_pipe_port_ids)
		if(port_id)
			. += list(list(HEAT_TARGET_PIPE_PORT, port_id))

/datum/material_service/proc/summary()
	var/datum/material_assembly/wear = material_assembly_view(owner())
	return "[status]. Assembly [round(temperature(), 0.1)] K; pressure load [round(last_pressure_load * 100, 0.1)]%; thermal buffer [round(buffer_energy())] J. Liner [round(wear.liner_integrity)]%, exterior [round(wear.exterior_integrity)]%. Fatigue [round(wear.fatigue)]%."

/obj/proc/material_service_changed()
	material_assembly(src).configuration_revision++
	if(istype(src, /obj/structure/cable))
		var/obj/structure/cable/cable = src
		cable.material_overlay?.material_graph?.invalidate_cable(cable)
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
	var/datum/material_service/service = material_service_of(src)
	service?.initialize_thermal_stock()
	if(service)
		service.watches_dirty = TRUE
	service?.schedule(0)


/// the watched_turf this refers to (a relation view: null once it is deleted).
/datum/material_service/proc/watched_turf() as /turf
	return watched_turf

/// A shared definition/flyweight (never cleared).
/datum/material_service/proc/thermal_stock() as /datum/material
	return thermal_stock_static

/// A shared definition/flyweight (never cleared).
/datum/material_service/proc/electrical_stock() as /datum/material
	return electrical_stock_static

/// the owner this refers to (a relation view: null once it is deleted).
/datum/material_service/proc/owner() as /obj
	return owner

// An obj owns its material service (rel_set); `owner` is the service's one-sided view back.

/// A material service's assembly temperature, K.
/proc/material_service_temperature(datum/material_service/service)
	return service.temperature()

/// The heat a material service's phase buffer holds, J.
/proc/material_service_buffer(datum/material_service/service)
	return service.buffer_energy()
