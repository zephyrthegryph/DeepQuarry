/// Constitutive material physics used by every construction role. Layered
/// "composite stock" no longer exists; finished objects keep their materials
/// separate and call these functions for the relevant part.

/atom/proc/material_reaction_rate_multiplier()
	return 1

/// Emitted on GLOB.om_world when a material's physical vars change after facts were read from
/// it (material_facts_changed()). Shared caches of material-derived facts clear on it. A state-invalidation
/// signal ("recompute"), emitted in bursts: only the latest matters, so it coalesces.
/datum/om/event/material_facts_changed
	coalesce = TRUE

/// A material's stable cache identity (MATERIAL_CACHE_ID()): its registry id when it is the
/// registered material of that name (every static material, and processed alloys, whose
/// registry id is a hash of their defining batch), otherwise a never-reused SHARED_CACHE_UID.
/// Never a ref: a recycled ref could hand a new material another one's facts.
/proc/material_cache_id(datum/material/M)
	if(M.name && GLOB.name_to_material[M.name] == M)
		M.shared_cache_uid = "m:[M.name]"
		return M.shared_cache_uid
	return shared_cache_assign_uid(M)

/// A material's physical vars changed after facts were read from it: every shared cache of
/// material-derived facts clears (SC_ON_EVENT; changes are rare). A material that was not yet
/// registered when it got its cache id takes its registry id from now on.
/datum/material/proc/material_facts_changed()
	shared_cache_uid = null
	OM_EMIT_WORLD(/datum/om/event/material_facts_changed)

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
	for(var/datum/gas/gas_type as anything in GLOBAL_TABLE_GET(material_corrosive_gases))
		if(temperature < initial(gas_type.material_corrosion_temperature))
			continue
		var/partial_pressure = mixture.get_moles(gas_type) * R_IDEAL_GAS_EQUATION * temperature / max(mixture.return_volume(), 1)
		load += initial(gas_type.material_corrosivity) * partial_pressure / ONE_ATMOSPHERE
	mixture.material_corrosion_cache = load * max(0.25, 1 + (temperature - T20C) / 600)
	return mixture.material_corrosion_cache

// Generic environmental state shared by pipes, vessels, cables, and machines is the object's
// /datum/material_assembly (material_state.dm): liner and exterior integrity, fatigue, a leak.

/obj/proc/material_environment_pressure_limit(base_pressure, radius_mm, wall_thickness_mm, temperature)
	var/selected_limit = construction_pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/reference_limit = steel?.pressure_limit(radius_mm, wall_thickness_mm, T20C)
	return (!isnull(selected_limit) && reference_limit) ? base_pressure * selected_limit / reference_limit : base_pressure

/obj/proc/material_environment_begin_leak()
	material_assembly(src).leaking = TRUE
	material_service_of(src)?.schedule(0)

/obj/proc/material_environment_repaired()
	return

/obj/proc/material_environment_owns_leak()
	return FALSE

/obj/proc/material_environment_rupture()
	if(uses_integrity && max_integrity > 0)
		take_damage(max_integrity, BRUTE)
	else
		spent(src)

/// Applies conserved heat exchange, differential-pressure fatigue, and both
/// wetted- and exterior-surface corrosion. Returns TRUE while another sample
/// is physically required.
/obj/proc/process_material_environment(datum/gas_mixture/internal, datum/gas_mixture/external, elapsed_seconds, base_pressure, radius_mm, wall_thickness_mm, allow_pressure = TRUE, service_owns_heat = FALSE, surface_fraction = 1)
	if(!internal || QDELETED(src))
		return FALSE
	var/datum/material_assembly/wear = material_assembly(src)
	elapsed_seconds = max(elapsed_seconds, 0)
	var/internal_temperature = internal.return_temperature()
	var/external_temperature = external?.return_temperature() || TCMB
	var/datum/material/structure = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	var/datum/material/liner = material_for_role(MATERIAL_ROLE_LINER) || structure
	var/active = FALSE

	if(allow_pressure && base_pressure > 0)
		var/pressure_delta = abs(internal.return_pressure() - (external?.return_pressure() || 0))
		var/pressure_limit = material_environment_pressure_limit(base_pressure, radius_mm, wall_thickness_mm, service_owns_heat ? wear.service.temperature() : internal_temperature)
		var/load_ratio = pressure_delta / max(pressure_limit, ONE_ATMOSPHERE)
		if(load_ratio >= MATERIAL_PRESSURE_BURST_RATIO)
			material_environment_rupture()
			return TRUE
		if(load_ratio > MATERIAL_PRESSURE_FATIGUE_RATIO)
			wear.fatigue = min(100, wear.fatigue + (load_ratio - MATERIAL_PRESSURE_FATIGUE_RATIO) * MATERIAL_PRESSURE_FATIGUE_RATE * elapsed_seconds)
			active = TRUE
		else if(load_ratio < MATERIAL_PRESSURE_RECOVERY_RATIO && wear.fatigue > 0)
			wear.fatigue = max(0, wear.fatigue - MATERIAL_PRESSURE_RECOVERY_RATE * elapsed_seconds)
			active = wear.fatigue > 0
		if(wear.fatigue >= 100 && !wear.leaking)
			material_environment_begin_leak()

	if(elapsed_seconds > 0 && liner)
		var/internal_corrosion = material_gas_corrosion_load(internal) * (100 - liner.corrosion_resistance) / 100 * elapsed_seconds * surface_fraction
		if(internal_corrosion > 0)
			wear.liner_integrity = max(0, wear.liner_integrity - internal_corrosion)
			active = TRUE
	if(elapsed_seconds > 0 && structure && external)
		var/external_corrosion = material_gas_corrosion_load(external) * (100 - structure.corrosion_resistance) / 100 * elapsed_seconds * surface_fraction
		if(external_corrosion > 0)
			wear.exterior_integrity = max(0, wear.exterior_integrity - external_corrosion)
			active = TRUE
	if((wear.liner_integrity <= 0 || wear.exterior_integrity <= 0) && !wear.leaking)
		material_environment_begin_leak()

	if(!service_owns_heat && external && abs(internal_temperature - external_temperature) > 0.5)
		var/conductance = construction_thermal_conductance(0.25, max(wall_thickness_mm / 1000, 0.001), (internal_temperature + external_temperature) * 0.5)
		if(conductance > 0)
			var/heat = heat_conduct(internal, external, conductance, elapsed_seconds) // the exact pair solution, in Rust
			active = abs(heat) > 0.01 || active

	if(!service_owns_heat && structure && max(internal_temperature, external_temperature) >= structure.melting_point)
		take_damage(max(1, (max(internal_temperature, external_temperature) - structure.melting_point) / 100) * elapsed_seconds, BURN)
		active = TRUE
	if(QDELETED(src))
		return FALSE
	if(wear.leaking && external && !material_environment_owns_leak())
		var/internal_pressure = internal.return_pressure()
		var/external_pressure = external.return_pressure()
		if(abs(internal_pressure - external_pressure) > 0.1 && elapsed_seconds > 0)
			var/datum/gas_mixture/source = internal_pressure > external_pressure ? internal : external
			var/datum/gas_mixture/destination = internal_pressure > external_pressure ? external : internal
			var/release_ratio = 1 - 2.718281828 ** (-0.04 * elapsed_seconds * sqrt(abs(internal_pressure - external_pressure) / max(internal_pressure, external_pressure, 0.1)))
			var/datum/gas_mixture/leaked = source.remove_ratio(release_ratio)
			destination.merge(leaked)
			spent(leaked)
			var/turf/open/open_turf = get_turf(src)
			if(istype(open_turf))
				open_turf.air_update_turf(FALSE, FALSE)
			active = TRUE
	return active

/obj/proc/process_material_environment_now(datum/gas_mixture/internal, datum/gas_mixture/external, base_pressure, radius_mm, wall_thickness_mm, allow_pressure = TRUE)
	var/datum/material_assembly/wear = material_assembly(src)
	var/now = world.time
	var/elapsed_seconds = wear.last_process ? clamp((now - wear.last_process) / 10, 0, 30) : 0
	wear.last_process = now
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
	var/datum/material_assembly/wear = material_assembly(src)
	wear.exterior_integrity = max(0, wear.exterior_integrity - corrosion)
	if(wear.exterior_integrity <= 0)
		if(uses_integrity && max_integrity > 0)
			take_damage(max_integrity, BURN)
		else
			spent(src)
	return TRUE

/obj/proc/process_material_reagent_liner(datum/reagents/contents, elapsed_seconds = 0)
	var/datum/material/liner = material_for_role(MATERIAL_ROLE_LINER)
	if(!liner || !contents?.total_volume)
		return FALSE
	var/corrosion = 0
	for(var/datum/reagent/reagent in contents.reagent_list)
		corrosion += liner.corrosion_rate(reagent.id) * reagent.volume / max(contents.total_volume, 1)
	if(corrosion <= 0)
		return FALSE
	var/datum/material_assembly/wear = material_assembly(src)
	wear.liner_integrity = max(0, wear.liner_integrity - corrosion * max(elapsed_seconds, 0))
	if(wear.liner_integrity <= 0)
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
			corrosion += liner.corrosion_rate(chemical.id) * chemical.volume / reagents.total_volume
	material_service_event(MATERIAL_EVENT_CORROSION, corrosion)
	material_service_of(src)?.contents_changed()

/obj/item/reagent_containers/material_environment_rupture()
	visible_message(span_danger("[src]'s liner perforates and the vessel spills apart!"))
	var/turf/spill_target = get_turf(src)
	if(spill_target)
		reagents?.splash(spill_target, reagents.total_volume)
	destroyed(src, null, BRUTE)

/obj/item/reagent_containers/examine(mob/user)
	. = ..()
	var/datum/material/material = construction_liner_material()
	if(material)
		. += span_notice("Liner integrity [round(material_assembly_view(src).liner_integrity)]%; catalytic rate [round(material_reaction_rate_multiplier(), 0.01)]x.")
