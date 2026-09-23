/// Constitutive material physics used by every construction role. Layered
/// "composite stock" no longer exists; finished objects keep their materials
/// separate and call these functions for the relevant part.

/atom/proc/material_reaction_rate_multiplier()
	return 1

/datum/material/proc/material_electrical_resistance(length_m, area_mm2, temperature, current_density = 0)
	var/effective_resistivity = max(electrical_resistivity, 0.0001)
	if(critical_temperature > 0 && temperature < critical_temperature && current_density <= critical_current_density)
		effective_resistivity = 0.0001
	else if(temperature > T20C)
		effective_resistivity *= 1 + (temperature - T20C) / max(heat_resistance * 35, 500)
	return effective_resistivity * max(length_m, 0.01) / max(area_mm2, 0.1)

/datum/material/proc/material_thermal_conductance(area_m2, thickness_m, temperature)
	var/effective_conductivity = max(conductivity, 1) * (1 - thermal_insulation / 125)
	if(temperature > melting_point)
		effective_conductivity *= 1.5
	return max(0.001, effective_conductivity * max(area_m2, 0.001) / max(thickness_m, 0.0001))

/datum/material/proc/material_pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/temperature_factor = clamp((melting_point - temperature) / max(melting_point - T20C, 1), 0.08, 1)
	var/effective_strength = max(yield_strength, hardness * 5, 25) * temperature_factor
	var/fracture_factor = clamp(fracture_toughness / 50, 0.25, 1.5)
	return max(ONE_ATMOSPHERE, effective_strength * max(wall_thickness_mm, 0.1) / max(radius_mm, 1) * fracture_factor * ONE_ATMOSPHERE)

/datum/material/proc/material_corrosion_rate(reagent_id, temperature = T20C)
	var/datum/reagent/chemical = SSchemistry.chemical_reagents[reagent_id]
	var/aggression = chemical?.material_corrosivity || 0
	var/temperature_factor = max(0.25, 1 + (temperature - T20C) / 300)
	return max(0, aggression * temperature_factor * (100 - corrosion_resistance) / 100)

/datum/material/proc/material_radiation_transmission(thickness_mm)
	var/attenuation = max(0, radiation_resistance + density / 8) * max(thickness_mm, 0) / 100
	return clamp(2.718281828 ** (-attenuation), 0, 1)

/// Environmental load exerted by a gas mixture on an exposed material.  This
/// is deliberately composition-based: no infrastructure class owns its own
/// private list of "bad gases" anymore.
/datum/gas_mixture
	var/material_corrosion_revision = -1
	var/material_corrosion_cache = 0

/proc/material_gas_corrosion_load(datum/gas_mixture/mixture)
	if(!mixture)
		return 0
	var/revision = mixture.revision()
	if(mixture.material_corrosion_revision == revision)
		return mixture.material_corrosion_cache
	mixture.material_corrosion_revision = revision
	mixture.material_corrosion_cache = 0
	var/total_moles = mixture.total_moles()
	if(total_moles <= MINIMUM_MOLES_TO_PUMP)
		return 0
	var/temperature = mixture.return_temperature()
	var/load = 0
	for(var/datum/gas/gas_type as anything in material_corrosive_gases())
		if(temperature < initial(gas_type.material_corrosion_temperature))
			continue
		var/partial_pressure = mixture.get_moles(gas_type) * R_IDEAL_GAS_EQUATION * temperature / max(mixture.return_volume(), 1)
		load += initial(gas_type.material_corrosivity) * partial_pressure / ONE_ATMOSPHERE
	mixture.material_corrosion_cache = load * max(0.25, 1 + (temperature - T20C) / 600)
	return mixture.material_corrosion_cache

/obj
	/// Generic environmental state shared by pipes, vessels, cables, and machines.
	var/material_environment_liner_integrity = 100
	var/material_environment_exterior_integrity = 100
	var/material_environment_fatigue = 0
	var/material_environment_leaking = FALSE
	var/tmp/material_environment_last_process = 0

/obj/proc/material_environment_pressure_limit(base_pressure, radius_mm, wall_thickness_mm, temperature)
	var/selected_limit = construction_pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/reference_limit = steel?.material_pressure_limit(radius_mm, wall_thickness_mm, T20C)
	return (!isnull(selected_limit) && reference_limit) ? base_pressure * selected_limit / reference_limit : base_pressure

/obj/proc/material_environment_begin_leak()
	material_environment_leaking = TRUE
	material_service?.schedule(0)

/obj/proc/material_environment_repaired()
	return

/obj/proc/material_environment_owns_leak()
	return FALSE

/obj/proc/material_environment_rupture()
	if(uses_integrity && max_integrity > 0)
		take_damage(max_integrity, BRUTE)
	else
		qdel(src)

/// Applies conserved heat exchange, differential-pressure fatigue, and both
/// wetted- and exterior-surface corrosion. Returns TRUE while another sample
/// is physically required.
/obj/proc/process_material_environment(datum/gas_mixture/internal, datum/gas_mixture/external, elapsed_seconds, base_pressure, radius_mm, wall_thickness_mm, allow_pressure = TRUE, service_owns_heat = FALSE, surface_fraction = 1)
	if(!internal || QDELETED(src))
		return FALSE
	elapsed_seconds = max(elapsed_seconds, 0)
	var/internal_temperature = internal.return_temperature()
	var/external_temperature = external?.return_temperature() || TCMB
	var/datum/material/structure = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	var/datum/material/liner = material_for_role(MATERIAL_ROLE_LINER) || structure
	var/active = FALSE

	if(allow_pressure && base_pressure > 0)
		var/pressure_delta = abs(internal.return_pressure() - (external?.return_pressure() || 0))
		var/pressure_limit = material_environment_pressure_limit(base_pressure, radius_mm, wall_thickness_mm, service_owns_heat ? material_service.temperature : internal_temperature)
		var/load_ratio = pressure_delta / max(pressure_limit, ONE_ATMOSPHERE)
		if(load_ratio >= MATERIAL_PRESSURE_BURST_RATIO)
			material_environment_rupture()
			return TRUE
		if(load_ratio > MATERIAL_PRESSURE_FATIGUE_RATIO)
			material_environment_fatigue = min(100, material_environment_fatigue + (load_ratio - MATERIAL_PRESSURE_FATIGUE_RATIO) * MATERIAL_PRESSURE_FATIGUE_RATE * elapsed_seconds)
			active = TRUE
		else if(load_ratio < MATERIAL_PRESSURE_RECOVERY_RATIO && material_environment_fatigue > 0)
			material_environment_fatigue = max(0, material_environment_fatigue - MATERIAL_PRESSURE_RECOVERY_RATE * elapsed_seconds)
			active = material_environment_fatigue > 0
		if(material_environment_fatigue >= 100 && !material_environment_leaking)
			material_environment_begin_leak()

	if(elapsed_seconds > 0 && liner)
		var/internal_corrosion = material_gas_corrosion_load(internal) * (100 - liner.corrosion_resistance) / 100 * elapsed_seconds * surface_fraction
		if(internal_corrosion > 0)
			material_environment_liner_integrity = max(0, material_environment_liner_integrity - internal_corrosion)
			active = TRUE
	if(elapsed_seconds > 0 && structure && external)
		var/external_corrosion = material_gas_corrosion_load(external) * (100 - structure.corrosion_resistance) / 100 * elapsed_seconds * surface_fraction
		if(external_corrosion > 0)
			material_environment_exterior_integrity = max(0, material_environment_exterior_integrity - external_corrosion)
			active = TRUE
	if((material_environment_liner_integrity <= 0 || material_environment_exterior_integrity <= 0) && !material_environment_leaking)
		material_environment_begin_leak()

	if(!service_owns_heat && external && abs(internal_temperature - external_temperature) > 0.5)
		var/conductance = construction_thermal_conductance(0.25, max(wall_thickness_mm / 1000, 0.001), (internal_temperature + external_temperature) * 0.5)
		if(!isnull(conductance))
			var/internal_capacity = internal.heat_capacity()
			var/external_capacity = external.heat_capacity()
			if(internal_capacity > 0 && external_capacity > 0)
				var/equilibrium_energy = (internal_temperature - external_temperature) / (1 / internal_capacity + 1 / external_capacity)
				var/heat = equilibrium_energy * (1 - 2.718281828 ** (-conductance * elapsed_seconds * (1 / internal_capacity + 1 / external_capacity)))
				internal.add_thermal_energy(-heat)
				external.add_thermal_energy(heat)
				active = abs(heat) > 0.01 || active

	if(!service_owns_heat && structure && max(internal_temperature, external_temperature) >= structure.melting_point)
		take_damage(max(1, (max(internal_temperature, external_temperature) - structure.melting_point) / 100) * elapsed_seconds, BURN)
		active = TRUE
	if(QDELETED(src))
		return FALSE
	if(material_environment_leaking && external && !material_environment_owns_leak())
		var/internal_pressure = internal.return_pressure()
		var/external_pressure = external.return_pressure()
		if(abs(internal_pressure - external_pressure) > 0.1 && elapsed_seconds > 0)
			var/datum/gas_mixture/source = internal_pressure > external_pressure ? internal : external
			var/datum/gas_mixture/destination = internal_pressure > external_pressure ? external : internal
			var/release_ratio = 1 - 2.718281828 ** (-0.04 * elapsed_seconds * sqrt(abs(internal_pressure - external_pressure) / max(internal_pressure, external_pressure, 0.1)))
			var/datum/gas_mixture/leaked = source.remove_ratio(release_ratio)
			destination.merge(leaked)
			qdel(leaked)
			var/turf/open/open_turf = get_turf(src)
			if(istype(open_turf))
				open_turf.air_update_turf(FALSE, FALSE)
			active = TRUE
	return active

/obj/proc/process_material_environment_now(datum/gas_mixture/internal, datum/gas_mixture/external, base_pressure, radius_mm, wall_thickness_mm, allow_pressure = TRUE)
	var/now = world.time
	var/elapsed_seconds = material_environment_last_process ? clamp((now - material_environment_last_process) / 10, 0, 30) : 0
	material_environment_last_process = now
	return process_material_environment(internal, external, elapsed_seconds, base_pressure, radius_mm, wall_thickness_mm, allow_pressure)

/obj/proc/process_material_exterior(datum/gas_mixture/environment, elapsed_seconds)
	if(!environment || elapsed_seconds <= 0)
		return FALSE
	var/datum/material/exterior = material_for_role(MATERIAL_ROLE_JACKET) || material_for_role(MATERIAL_ROLE_INSULATION) || material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	if(!exterior)
		return FALSE
	var/corrosion = material_gas_corrosion_load(environment) * (100 - exterior.corrosion_resistance) / 100 * elapsed_seconds
	if(corrosion <= 0)
		return FALSE
	material_environment_exterior_integrity = max(0, material_environment_exterior_integrity - corrosion)
	if(material_environment_exterior_integrity <= 0)
		if(uses_integrity && max_integrity > 0)
			take_damage(max_integrity, BURN)
		else
			qdel(src)
	return TRUE

/obj/proc/process_material_reagent_liner(datum/reagents/contents, elapsed_seconds = 0)
	var/datum/material/liner = material_for_role(MATERIAL_ROLE_LINER)
	if(!liner || !contents?.total_volume)
		return FALSE
	var/corrosion = 0
	for(var/datum/reagent/reagent in contents.reagent_list)
		corrosion += liner.material_corrosion_rate(reagent.id) * reagent.volume / max(contents.total_volume, 1)
	if(corrosion <= 0)
		return FALSE
	material_environment_liner_integrity = max(0, material_environment_liner_integrity - corrosion * max(elapsed_seconds, 0))
	if(material_environment_liner_integrity <= 0)
		material_environment_begin_leak()
		material_environment_rupture()
	return TRUE

/obj/item/reagent_containers/proc/construction_liner_material()
	return material_for_role(MATERIAL_ROLE_LINER)

/obj/item/reagent_containers/material_reaction_rate_multiplier()
	var/datum/material/material = construction_liner_material()
	return material ? 1 + material.catalytic_activity / 100 : 1

/obj/item/reagent_containers/on_reagent_change()
	. = ..()
	var/datum/material/liner = material_for_role(MATERIAL_ROLE_LINER)
	var/corrosion = 0
	if(liner && reagents?.total_volume)
		for(var/datum/reagent/chemical in reagents.reagent_list)
			corrosion += liner.material_corrosion_rate(chemical.id) * chemical.volume / reagents.total_volume
	material_service_event(MATERIAL_EVENT_CORROSION, corrosion)
	material_service?.contents_changed()

/obj/item/reagent_containers/material_environment_rupture()
	visible_message(span_danger("[src]'s liner perforates and the vessel spills apart!"))
	var/turf/spill_target = get_turf(src)
	if(spill_target)
		reagents?.splash(spill_target, reagents.total_volume)
	qdel(src)

/obj/item/reagent_containers/examine(mob/user)
	. = ..()
	var/datum/material/material = construction_liner_material()
	if(material)
		. += span_notice("Liner integrity [round(material_environment_liner_integrity)]%; catalytic rate [round(material_reaction_rate_multiplier(), 0.01)]x.")
