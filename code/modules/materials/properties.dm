/// The one reader family for /datum/material's derived physical properties. Every
/// consumer asks these; the raw property vars live in material.dm.

/datum/material/proc/electrical_resistance(length_m, area_mm2, temperature, current_density = 0)
	var/effective_resistivity = max(electrical_resistivity, 0.0001)
	if(critical_temperature > 0 && temperature < critical_temperature && current_density <= critical_current_density)
		effective_resistivity = 0.0001
	else if(temperature > T20C)
		effective_resistivity *= 1 + (temperature - T20C) / max(heat_resistance * 35, 500)
	return effective_resistivity * max(length_m, 0.01) / max(area_mm2, 0.1)

/datum/material/proc/thermal_conductance(area_m2, thickness_m, temperature)
	var/effective_conductivity = max(conductivity, 1) * (1 - thermal_insulation / 125)
	if(temperature > melting_point)
		effective_conductivity *= 1.5
	return max(0.001, effective_conductivity * max(area_m2, 0.001) / max(thickness_m, 0.0001))

/datum/material/proc/pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/temperature_factor = clamp((melting_point - temperature) / max(melting_point - T20C, 1), 0.08, 1)
	var/effective_strength = max(yield_strength, hardness * 5, 25) * temperature_factor
	var/fracture_factor = clamp(fracture_toughness / 50, 0.25, 1.5)
	return max(ONE_ATMOSPHERE, effective_strength * max(wall_thickness_mm, 0.1) / max(radius_mm, 1) * fracture_factor * ONE_ATMOSPHERE)

/datum/material/proc/corrosion_rate(reagent_id, temperature = T20C)
	var/datum/reagent/chemical = SSchemistry.ready().chemical_reagents[reagent_id]
	var/aggression = chemical?.material_corrosivity || 0
	var/temperature_factor = max(0.25, 1 + (temperature - T20C) / 300)
	return max(0, aggression * temperature_factor * (100 - corrosion_resistance) / 100)

/// Weapons handle applying a divisor for this value locally.
/datum/material/proc/blunt_damage()
	return density

/datum/material/proc/edge_damage()
	return hardness

/// Radiation transmission through `thickness_mm` of this material. Shared per (material,
/// thickness) (doc/rewrite/init_and_turfs.md sec 3.1): every wall, window, girder, door and item
/// of a material asks the same question of the same (usually singleton) material.
/datum/material/proc/radiation_transmission(thickness_mm)
	return CACHED_KEY(material_radiation_transmission, "[MATERIAL_CACHE_ID(src)]|[thickness_mm]", src, thickness_mm)

/proc/build_material_radiation_transmission(datum/material/M, thickness_mm)
	var/attenuation = max(0, M.radiation_resistance + M.density / 8) * max(thickness_mm, 0) / 100
	return clamp(2.718281828 ** (-attenuation), 0, 1)

DECLARE_SHARED_CACHE_EX(material_radiation_transmission, GLOBAL_PROC_REF(build_material_radiation_transmission), SC_ON_NOTICE(/datum/notice/material_facts_changed), 4096, 0)
