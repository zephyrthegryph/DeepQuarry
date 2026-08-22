GLOBAL_LIST_EMPTY(composite_material_dedup)

/atom/proc/material_reaction_rate_multiplier()
	return 1

/// Material behavior is expressed as constitutive functions. Consumers provide
/// geometry and operating state; they never ask whether a named "capability" exists.
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

/datum/material/composite
	stack_type = /obj/item/stack/material/composite
	var/core_material_id
	var/functional_material_id
	var/liner_material_id
	var/jacket_material_id
	var/core_fraction = MATERIAL_COMPOSITE_DEFAULT_CORE_FRACTION
	var/functional_fraction = MATERIAL_COMPOSITE_DEFAULT_FUNCTIONAL_FRACTION
	var/liner_fraction = MATERIAL_COMPOSITE_DEFAULT_LINER_FRACTION
	var/jacket_fraction = MATERIAL_COMPOSITE_DEFAULT_JACKET_FRACTION
	var/thermal_buffer_capacity = 0
	var/thermal_buffer_temperature = 0

/datum/material/composite/proc/layer_material(material_id) as /datum/material
	return material_id ? get_material_by_name(material_id) : null

/datum/material/composite/proc/core_material() as /datum/material
	return layer_material(core_material_id)

/datum/material/composite/proc/functional_material() as /datum/material
	return layer_material(functional_material_id)

/datum/material/composite/proc/liner_material() as /datum/material
	return layer_material(liner_material_id)

/datum/material/composite/proc/jacket_material() as /datum/material
	return layer_material(jacket_material_id)

/datum/material/composite/material_electrical_resistance(length_m, area_mm2, temperature, current_density = 0)
	var/datum/material/core = core_material()
	var/datum/material/functional = functional_material()
	if(!core)
		return ..()
	var/core_area = area_mm2 * max(core_fraction, 0.1)
	var/core_resistance = core.material_electrical_resistance(length_m, core_area, temperature, current_density)
	if(!functional || functional.conductivity < 10)
		return core_resistance
	var/functional_area = area_mm2 * max(functional_fraction, 0.05)
	var/functional_resistance = functional.material_electrical_resistance(length_m, functional_area, temperature, current_density)
	return 1 / max((1 / max(core_resistance, 0.0001)) + (1 / max(functional_resistance, 0.0001)), 0.0001)

/datum/material/composite/material_thermal_conductance(area_m2, thickness_m, temperature)
	var/total_resistance = 0
	var/list/layers = list()
	if(core_material_id)
		layers[core_material_id] = (layers[core_material_id] || 0) + core_fraction
	if(functional_material_id)
		layers[functional_material_id] = (layers[functional_material_id] || 0) + functional_fraction
	if(liner_material_id)
		layers[liner_material_id] = (layers[liner_material_id] || 0) + liner_fraction
	if(jacket_material_id)
		layers[jacket_material_id] = (layers[jacket_material_id] || 0) + jacket_fraction
	for(var/material_id in layers)
		if(!material_id)
			continue
		var/datum/material/layer = get_material_by_name(material_id)
		if(!layer)
			continue
		var/layer_thickness = thickness_m * layers[material_id]
		total_resistance += 1 / max(layer.material_thermal_conductance(area_m2, layer_thickness, temperature), 0.0001)
	return 1 / max(total_resistance, 0.0001)

/datum/material/composite/material_pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/datum/material/core = core_material()
	var/datum/material/jacket = jacket_material()
	var/core_limit = core ? core.material_pressure_limit(radius_mm, wall_thickness_mm * core_fraction, temperature) : 0
	var/jacket_limit = jacket ? jacket.material_pressure_limit(radius_mm, wall_thickness_mm * jacket_fraction, temperature) : 0
	return max(ONE_ATMOSPHERE, core_limit + jacket_limit)

/datum/material/composite/material_corrosion_rate(reagent_id, temperature = T20C)
	var/datum/material/exposed = liner_material() || jacket_material() || core_material()
	return exposed ? exposed.material_corrosion_rate(reagent_id, temperature) : ..()

/datum/material/composite/material_radiation_transmission(thickness_mm)
	var/transmission = 1
	var/list/layers = list()
	if(core_material_id)
		layers[core_material_id] = (layers[core_material_id] || 0) + core_fraction
	if(functional_material_id)
		layers[functional_material_id] = (layers[functional_material_id] || 0) + functional_fraction
	if(liner_material_id)
		layers[liner_material_id] = (layers[liner_material_id] || 0) + liner_fraction
	if(jacket_material_id)
		layers[jacket_material_id] = (layers[jacket_material_id] || 0) + jacket_fraction
	for(var/material_id in layers)
		if(!material_id)
			continue
		var/datum/material/layer = get_material_by_name(material_id)
		if(layer)
			transmission *= layer.material_radiation_transmission(thickness_mm * layers[material_id])
	return clamp(transmission, 0, 1)

/proc/register_composite_material(core_id, functional_id, liner_id, jacket_id)
	var/datum/material/core = get_material_by_name(core_id)
	if(!core)
		return null
	var/fingerprint = md5("[core_id]|[functional_id]|[liner_id]|[jacket_id]")
	var/existing = GLOB.composite_material_dedup[fingerprint]
	if(existing && GLOB.name_to_material[existing])
		return existing
	var/datum/material/functional = functional_id ? get_material_by_name(functional_id) : null
	var/datum/material/liner = liner_id ? get_material_by_name(liner_id) : null
	var/datum/material/jacket = jacket_id ? get_material_by_name(jacket_id) : null
	var/key = "composite_[copytext(fingerprint, 1, 13)]"
	var/datum/material/composite/composite = new
	composite.name = key
	composite.display_name = "[core.display_name]-[functional?.display_name || "passive"] layered composite"
	composite.use_name = composite.display_name
	composite.core_material_id = core_id
	composite.functional_material_id = functional_id
	composite.liner_material_id = liner_id
	composite.jacket_material_id = jacket_id
	var/list/bulk_materials = list()
	bulk_materials[core] = MATERIAL_COMPOSITE_DEFAULT_CORE_FRACTION
	if(functional)
		bulk_materials[functional] = MATERIAL_COMPOSITE_DEFAULT_FUNCTIONAL_FRACTION
	composite.hardness = 0
	composite.integrity = 0
	composite.elasticity = 0
	composite.brittleness = 0
	composite.density = 0
	composite.heat_resistance = 0
	composite.conductivity = 0
	composite.specific_heat = 0
	composite.yield_strength = 0
	composite.fracture_toughness = 0
	composite.radiation_resistance = 0
	var/bulk_total = 0
	for(var/datum/material/bulk in bulk_materials)
		bulk_total += bulk_materials[bulk]
	for(var/datum/material/bulk in bulk_materials)
		var/share = bulk_materials[bulk] / max(bulk_total, 0.01)
		composite.hardness += bulk.hardness * share
		composite.integrity += bulk.integrity * share
		composite.elasticity += bulk.elasticity * share
		composite.brittleness += bulk.brittleness * share
		composite.density += bulk.density * share
		composite.heat_resistance += bulk.heat_resistance * share
		composite.conductivity += bulk.conductivity * share
		composite.specific_heat += bulk.specific_heat * share
		composite.yield_strength += bulk.yield_strength * share
		composite.fracture_toughness += bulk.fracture_toughness * share
		composite.radiation_resistance += bulk.radiation_resistance * share
	composite.melting_point = core.melting_point
	composite.critical_temperature = core.critical_temperature
	composite.critical_current_density = core.critical_current_density
	composite.electrical_resistivity = core.electrical_resistivity
	var/datum/material/exposed_material = liner || jacket || core
	composite.corrosion_resistance = exposed_material.corrosion_resistance
	composite.reactivity = exposed_material.reactivity
	composite.catalytic_activity = exposed_material.catalytic_activity
	composite.thermal_insulation = jacket ? clamp(jacket.thermal_insulation + (100 - jacket.conductivity) * 0.5, 0, 100) : core.thermal_insulation
	composite.dielectric_strength = jacket ? max(jacket.dielectric_strength, 100 - jacket.conductivity) : core.dielectric_strength
	composite.thermal_buffer_capacity = functional ? functional.phase_change_capacity + functional.specific_heat * 10 : 0
	composite.thermal_buffer_temperature = functional?.phase_change_temperature || 0
	composite.phase_change_capacity = composite.thermal_buffer_capacity
	composite.phase_change_temperature = composite.thermal_buffer_temperature
	composite.icon_colour = jacket?.icon_colour || core.icon_colour
	composite.material_class = core.material_class
	composite.composite_material = list()
	var/list/layer_fractions = list()
	layer_fractions[core_id] = composite.core_fraction
	if(functional_id)
		layer_fractions[functional_id] = (layer_fractions[functional_id] || 0) + composite.functional_fraction
	if(liner_id)
		layer_fractions[liner_id] = (layer_fractions[liner_id] || 0) + composite.liner_fraction
	if(jacket_id)
		layer_fractions[jacket_id] = (layer_fractions[jacket_id] || 0) + composite.jacket_fraction
	var/present_fraction = 0
	for(var/material_id in layer_fractions)
		present_fraction += layer_fractions[material_id]
	for(var/material_id in layer_fractions)
		composite.composite_material[material_id] = round(SHEET_MATERIAL_AMOUNT * layer_fractions[material_id] / max(present_fraction, 0.01))
	composite.supply_conversion_value = max(0.01, core.supply_conversion_value * composite.core_fraction + (functional?.supply_conversion_value || 0) * composite.functional_fraction + (liner?.supply_conversion_value || 0) * composite.liner_fraction + (jacket?.supply_conversion_value || 0) * composite.jacket_fraction)
	GLOB.name_to_material[key] = composite
	GLOB.composite_material_dedup[fingerprint] = key
	return key

/obj/item/stack/material/composite
	name = "layered composite stock"
	desc = "A consolidated stock whose core, functional layer, liner, and jacket remain physically distinct."
	icon = 'icons/obj/mining.dmi'
	icon_state = "sheet-plastic"
	default_type = MAT_STEEL
	no_variants = TRUE
	pass_color = TRUE
	strict_color_stacking = TRUE
	exotic_no_autolathe_reprint = TRUE

/obj/item/stack/material/composite/Initialize(mapload, _amount, _material_name)
	if(_material_name)
		default_type = _material_name
	. = ..(mapload, _amount)
	if(material)
		color = material.icon_colour

/obj/item/stack/material/composite/examine(mob/user)
	. = ..()
	if(!istype(material, /datum/material/composite))
		return
	var/datum/material/composite/composite = material
	. += span_notice("Core: [composite.core_material()?.display_name || "none"].")
	. += span_notice("Functional layer: [composite.functional_material()?.display_name || "none"]; liner: [composite.liner_material()?.display_name || "none"]; jacket: [composite.jacket_material()?.display_name || "none"].")
	. += span_notice("The layers are not averaged away: electrical load follows the core, heat crosses every layer, pressure loads the core and jacket, and chemicals meet the liner first.")
	if(composite.critical_temperature > 0)
		. += span_notice("Critical envelope: below [round(composite.critical_temperature, 0.1)] K and [round(composite.critical_current_density)] relative current density.")
	if(composite.phase_change_capacity > 0)
		. += span_notice("Functional thermal buffer: [round(composite.phase_change_capacity)] J centered at [round(composite.phase_change_temperature, 0.1)] K.")

/obj/structure/material_composite_press
	name = "composite layup press"
	desc = "A physical layup press. Add sheets in order: core, functional buffer, internal liner, then external jacket. Wrench it to consolidate the loaded layers."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "separator-AO1"
	anchored = TRUE
	density = TRUE
	var/core_material_id
	var/functional_material_id
	var/liner_material_id
	var/jacket_material_id

/obj/structure/material_composite_press/examine(mob/user)
	. = ..()
	var/datum/material/core = core_material_id ? get_material_by_name(core_material_id) : null
	var/datum/material/functional = functional_material_id ? get_material_by_name(functional_material_id) : null
	var/datum/material/liner = liner_material_id ? get_material_by_name(liner_material_id) : null
	var/datum/material/jacket = jacket_material_id ? get_material_by_name(jacket_material_id) : null
	. += span_notice("Core: [core?.display_name || "empty"].")
	. += span_notice("Functional layer: [functional?.display_name || "empty"].")
	. += span_notice("Liner: [liner?.display_name || "empty"]. Jacket: [jacket?.display_name || "empty"].")

/obj/structure/material_composite_press/attackby(obj/item/item, mob/user)
	if(item.has_tool_quality(TOOL_WRENCH))
		finish_layup(user)
		return
	if(!istype(item, /obj/item/stack/material))
		return ..()
	var/obj/item/stack/material/stock = item
	if(stock.get_amount() < 1 || !stock.material)
		return
	var/role
	if(!core_material_id)
		core_material_id = stock.material.name
		role = MATERIAL_LAYER_CORE
	else if(!functional_material_id)
		functional_material_id = stock.material.name
		role = MATERIAL_LAYER_FUNCTIONAL
	else if(!liner_material_id)
		liner_material_id = stock.material.name
		role = MATERIAL_LAYER_LINER
	else if(!jacket_material_id)
		jacket_material_id = stock.material.name
		role = MATERIAL_LAYER_JACKET
	else
		to_chat(user, span_warning("All four physical layer positions are occupied."))
		return
	var/material_name = stock.material.display_name
	stock.use(1)
	visible_message(span_notice("[user] lays a sheet of [material_name] into [src] as the [role]."))

/obj/structure/material_composite_press/proc/finish_layup(mob/user)
	if(!core_material_id || !functional_material_id)
		to_chat(user, span_warning("A composite requires at least a core and a functional layer."))
		return FALSE
	var/composite_key = register_composite_material(core_material_id, functional_material_id, liner_material_id, jacket_material_id)
	if(!composite_key)
		to_chat(user, span_warning("The loaded layers cannot be consolidated."))
		return FALSE
	var/output_amount = 2 + !!liner_material_id + !!jacket_material_id
	var/obj/item/stack/material/composite/output = new(get_turf(src), output_amount, composite_key)
	visible_message(span_notice("[user] wrenches [src] through a full cycle; it ejects [output] with every layer visibly bonded but physically distinct."))
	playsound(src, 'sound/machines/hiss.ogg', 45, TRUE)
	core_material_id = null
	functional_material_id = null
	liner_material_id = null
	jacket_material_id = null
	return output

/obj/item/reagent_containers/glass/beaker/composite
	name = "composite reaction vessel"
	desc = "A reusable vessel fabricated from a selected material. Reagents contact its exposed liner, so corrosion and catalysis are physical surface effects."
	volume = 120
	amount_per_transfer_from_this = 10
	max_transfer_amount = 120
	flags = OPENCONTAINER
	rating = 3
	var/material_integrity = 100

/obj/item/reagent_containers/glass/beaker/composite/Initialize(mapload, material_id)
	engineered_material_id = material_id
	. = ..()
	var/datum/material/material = engineered_material()
	if(material)
		name = "[material.display_name] reaction vessel"
		color = material.icon_colour

/obj/item/reagent_containers/glass/beaker/composite/proc/engineered_material()
	return engineered_material_id ? get_material_by_name(engineered_material_id) : null

/obj/item/reagent_containers/glass/beaker/composite/material_reaction_rate_multiplier()
	var/datum/material/material = engineered_material()
	return material ? 1 + material.catalytic_activity / 100 : 1

/obj/item/reagent_containers/glass/beaker/composite/on_reagent_change()
	..()
	var/datum/material/material = engineered_material()
	if(!material || !reagents?.total_volume)
		return
	var/corrosion = 0
	for(var/datum/reagent/reagent in reagents.reagent_list)
		corrosion += material.material_corrosion_rate(reagent.id) * reagent.volume / max(reagents.total_volume, 1)
	if(corrosion <= 0)
		return
	material_integrity = max(0, material_integrity - corrosion)
	if(material_integrity <= 0)
		visible_message(span_danger("[src]'s exposed liner perforates and the vessel spills apart!"))
		reagents.splash(get_turf(src), reagents.total_volume)
		qdel(src)

/obj/item/reagent_containers/glass/beaker/composite/examine(mob/user)
	. = ..()
	var/datum/material/material = engineered_material()
	if(material)
		. += span_notice("Construction: [material.display_name]; liner integrity [round(material_integrity)]%.")
		. += span_notice("Catalytic rate multiplier: [round(material_reaction_rate_multiplier(), 0.01)]x. This changes reaction kinetics, not stoichiometric yield.")
