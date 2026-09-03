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
	var/aggression = 1
	if(reagent_id in list(REAGENT_ID_SACID, REAGENT_ID_PACID))
		aggression = 8
	else if(reagent_id == REAGENT_ID_PHORON)
		aggression = 3
	var/temperature_factor = max(0.25, 1 + (temperature - T20C) / 300)
	return max(0, aggression * temperature_factor * (100 - corrosion_resistance) / 100)

/datum/material/proc/material_radiation_transmission(thickness_mm)
	var/attenuation = max(0, radiation_resistance + density / 8) * max(thickness_mm, 0) / 100
	return clamp(2.718281828 ** (-attenuation), 0, 1)

/obj/item/reagent_containers
	var/material_liner_integrity = 100

/obj/item/reagent_containers/proc/construction_liner_material()
	return material_for_role(MATERIAL_ROLE_LINER)

/obj/item/reagent_containers/material_reaction_rate_multiplier()
	var/datum/material/material = construction_liner_material()
	return material ? 1 + material.catalytic_activity / 100 : 1

/obj/item/reagent_containers/on_reagent_change()
	. = ..()
	var/datum/material/material = construction_liner_material()
	if(!material || !reagents?.total_volume)
		return
	var/corrosion = 0
	for(var/datum/reagent/reagent in reagents.reagent_list)
		corrosion += material.material_corrosion_rate(reagent.id) * reagent.volume / max(reagents.total_volume, 1)
	material_liner_integrity = max(0, material_liner_integrity - corrosion)
	if(material_liner_integrity <= 0)
		visible_message(span_danger("[src]'s liner perforates and the vessel spills apart!"))
		reagents.splash(get_turf(src), reagents.total_volume)
		qdel(src)

/obj/item/reagent_containers/examine(mob/user)
	. = ..()
	var/datum/material/material = construction_liner_material()
	if(material)
		. += span_notice("Liner integrity [round(material_liner_integrity)]%; catalytic rate [round(material_reaction_rate_multiplier(), 0.01)]x.")
