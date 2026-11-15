/// The one reader family for /datum/material's derived physical properties. Every
/// consumer asks these; the stored card and traits live in material.dm. Nothing here is
/// stored: each number is a formula over the card (strength, toughness, heat resistance,
/// conductivity, corrosion resistance, weight) or over one trait's strength.

/// The strength (0-100) of trait `id`, 0 when the material lacks it.
/datum/material/proc/trait(id)
	return LAZYACCESS(traits, id) || 0

/// Melting point, K: 250 plus 40 per point of heat resistance (steel 38.75 is 1800 K).
/datum/material/proc/melting_point()
	return 250 + heat_resistance * 40

/// Whether the material conducts at all (an item of it carries NOCONDUCT otherwise).
/datum/material/proc/conductive()
	return conductivity >= 8

/// Ohm-scale resistivity: the inverse of conductivity.
/datum/material/proc/electrical_resistivity()
	return 100 / max(conductivity, 0.1)

/// Breakdown field strength: an insulator's, 10 for anything that conducts.
/datum/material/proc/dielectric_strength()
	return conductive() ? 10 : max(25, 110 - conductivity)

/// Specific heat, J/kg/K: heat-resistant stock holds more heat per mass.
/datum/material/proc/specific_heat()
	return clamp(250 + heat_resistance * 5, 200, 1200)

/// Fracture toughness: how much of its toughness stands between a crack and a break (steel, 75, is 22.5).
/datum/material/proc/fracture_toughness()
	return toughness * 0.3

/// Yield strength: what the card's strength resists before it deforms.
/datum/material/proc/yield_strength()
	return max(strength * 5, 25)

/// How far strength outruns toughness: 0 for a tough material, up to 100 for a glass-like one.
/datum/material/proc/brittleness()
	return clamp(strength - toughness, 0, 100)

/// Armour value: toughness and strength, diminishing returns applied by the armour.
/datum/material/proc/protectiveness()
	return clamp((toughness * 0.48 + strength * 0.28) * 0.2, 1, 30)

/// Blast resistance of a wall or girder of this material.
/datum/material/proc/explosion_resistance()
	return clamp((toughness / 8 + strength / 14) * 0.5, 1, 40)

/// Critical temperature of a superconducting material, K (it superconducts below it).
/datum/material/proc/critical_temperature()
	var/s = trait(MT_SUPERCONDUCTING)
	return s > 0 ? 40 + s * 2.6 : 0

/// The current density a superconducting material carries before it quenches.
/datum/material/proc/critical_current_density()
	return trait(MT_SUPERCONDUCTING) * 15

/// Joules a buffer material (thermal or cryogenic) soaks up on its plateau.
/datum/material/proc/phase_change_capacity()
	return (trait(MT_THERMAL_BUFFER) + trait(MT_CRYO_BUFFER)) * 1000

/// The temperature of a buffer material's plateau, K: 0 when it has none.
/datum/material/proc/phase_change_temperature()
	if(trait(MT_CRYO_BUFFER) > 0)
		return MATERIAL_CRYO_BUFFER_TEMPERATURE
	return trait(MT_THERMAL_BUFFER) > 0 ? MATERIAL_THERMAL_BUFFER_TEMPERATURE : 0

/// Temperature above which a thermal-switch material becomes an efficient conductor, K.
/datum/material/proc/thermal_switch_temperature()
	var/s = trait(MT_THERMAL_SWITCH)
	return s > 0 ? T0C + 40 + s : 0

/// How much better a thermal-switch material conducts once switched.
/datum/material/proc/thermal_switch_ratio()
	return 1 + trait(MT_THERMAL_SWITCH) / 15

/// Joules a reactive material layer stores to absorb hits.
/datum/material/proc/reactive_energy_capacity()
	return trait(MT_REACTIVE) * 50

/// Moles of gas a sorbent material adsorbs (a pipe, a filter).
/datum/material/proc/sorbed_gas()
	return trait(MT_SORBENT) / 4

/// Units of reagent a sorbent material holds in its pores.
/datum/material/proc/sorbed_volume()
	return trait(MT_SORBENT) / 4

/datum/material/proc/electrical_resistance(length_m, area_mm2, temperature, current_density = 0)
	var/effective_resistivity = max(electrical_resistivity(), 0.0001)
	var/critical = critical_temperature()
	if(critical > 0 && temperature < critical && current_density <= critical_current_density())
		effective_resistivity = 0.0001
	else if(temperature > T20C)
		effective_resistivity *= 1 + (temperature - T20C) / max(heat_resistance * 35, 500)
	return effective_resistivity * max(length_m, 0.01) / max(area_mm2, 0.1)

/datum/material/proc/thermal_conductance(area_m2, thickness_m, temperature)
	var/effective_conductivity = max(conductivity, 1)
	if(temperature > melting_point())
		effective_conductivity *= 1.5
	return max(0.001, effective_conductivity * max(area_m2, 0.001) / max(thickness_m, 0.0001))

/datum/material/proc/pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/melting = melting_point()
	var/temperature_factor = clamp((melting - temperature) / max(melting - T20C, 1), 0.08, 1)
	var/effective_strength = yield_strength() * temperature_factor
	var/fracture_factor = clamp(fracture_toughness() / 50, 0.25, 1.5)
	return max(ONE_ATMOSPHERE, effective_strength * max(wall_thickness_mm, 0.1) / max(radius_mm, 1) * fracture_factor * ONE_ATMOSPHERE)

/datum/material/proc/corrosion_rate(reagent_id, temperature = T20C)
	var/datum/reagent/chemical = SSchemistry.ready().chemical_reagents[reagent_id]
	var/aggression = chemical?.material_corrosivity || 0
	var/temperature_factor = max(0.25, 1 + (temperature - T20C) / 300)
	return max(0, aggression * temperature_factor * (100 - corrosion_resistance) / 100)

/// Weapons handle applying a divisor for this value locally.
/datum/material/proc/blunt_damage()
	return weight

/datum/material/proc/edge_damage()
	return strength

/// Radiation transmission through `thickness_mm` of this material. Shared per (material,
/// thickness) (doc/rewrite/init_and_turfs.md sec 3.1): every wall, window, girder, door and item
/// of a material asks the same question of the same (usually singleton) material.
/datum/material/proc/radiation_transmission(thickness_mm)
	return CACHED_KEY(material_radiation_transmission, "[MATERIAL_CACHE_ID(src)]|[thickness_mm]", src, thickness_mm)

/proc/build_material_radiation_transmission(datum/material/M, thickness_mm)
	var/attenuation = max(0, M.radiation_resistance + M.weight / 8) * max(thickness_mm, 0) / 100
	return clamp(2.718281828 ** (-attenuation), 0, 1)

DECLARE_SHARED_CACHE_EX(material_radiation_transmission, GLOBAL_PROC_REF(build_material_radiation_transmission), SC_ON_NOTICE(/datum/notice/material_facts_changed), 4096, 0)
