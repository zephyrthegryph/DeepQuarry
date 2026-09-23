/// Generic material construction shared by lathes, hand crafting, and objects.
/// Blueprints are material template singletons (material_templates.dm). Objects
/// declare a template and a total on their type and store per instance only the
/// roles whose material differs from the template default.

/proc/material_slot_choice_valid(list/spec, material_id)
	if(!islist(spec))
		return FALSE
	if(!material_id)
		return !!spec["optional"]
	var/datum/material/material = get_material_by_name(material_id)
	if(!material)
		return FALSE
	return TRUE

/// Scores continuous physical properties for the job a part performs. This is
/// used only to choose and rank defaults; every solid stack remains selectable.
/proc/material_role_score(datum/material/material, role)
	if(!istype(material))
		return -INFINITY
	switch(role)
		if(MATERIAL_ROLE_CONDUCTOR, MATERIAL_ROLE_CONTACTS, MATERIAL_ROLE_ACTUATOR)
			return material.conductivity * 2 + material.corrosion_resistance + material.critical_current_density * 0.02 - material.electrical_resistivity
		if(MATERIAL_ROLE_INSULATION, MATERIAL_ROLE_GRIP, MATERIAL_ROLE_SUBSTRATE, MATERIAL_ROLE_DIELECTRIC)
			return material.dielectric_strength + material.thermal_insulation + material.integrity * 0.2 - material.conductivity
		if(MATERIAL_ROLE_WORKING, MATERIAL_ROLE_BARREL, MATERIAL_ROLE_BEARINGS, MATERIAL_ROLE_FEED, MATERIAL_ROLE_SPRING)
			return material.hardness + material.heat_resistance + material.fracture_toughness * 0.5 - material.brittleness
		if(MATERIAL_ROLE_SENSOR, MATERIAL_ROLE_EMITTER, MATERIAL_ROLE_OPTICAL)
			return material.purity_equivalent() + material.heat_resistance + material.conductivity * 0.5 - material.reactivity
		if(MATERIAL_ROLE_THERMAL)
			return material.specific_heat * 0.05 + material.heat_resistance + material.phase_change_capacity * 0.1
		if(MATERIAL_ROLE_LINER, MATERIAL_ROLE_JACKET)
			return material.corrosion_resistance + material.heat_resistance * 0.5 + material.biocompatibility - material.reactivity - material.toxicity
	return material.integrity + material.yield_strength * 0.2 + material.fracture_toughness - material.brittleness * 0.5 - material.density * 0.05

/// TGUI rows for a blueprint's configurable roles.
/proc/material_slots_tgui(datum/material_template/template, total)
	var/list/out = list()
	if(!template)
		return out
	var/list/amounts = template.role_amounts(total)
	for(var/role in template.roles)
		var/list/spec = template.roles[role]
		out += list(list(
			"role" = role,
			"label" = spec["label"],
			"amount" = amounts[role],
			"defaultMaterial" = spec["default"],
			"optional" = !!spec["optional"],
			"description" = spec["description"],
		))
	return out

/obj
	/// Blueprint of this object's composition (a /datum/material_template path).
	/// Declared per type; an instance only changes it when it is rebuilt to a
	/// different blueprint (a lathe or crafting recipe).
	var/material_template
	/// Total material units in this object; the template splits it between roles.
	var/material_total = 0
	/// Material of the single-role bulk template (MATERIAL_BULK).
	var/material_bulk_material
	/// Role -> material id for the roles that differ from the template default.
	/// Null for an unmodified object. Interned and shared: write through
	/// set_construction_material(), never in place.
	var/list/material_overrides

/// Interned override lists keyed by their contents. Thousands of pipes, cables and
/// machines carry identical overrides, so they share one list. Shared lists are read-only.
/proc/material_overrides_intern(list/overrides)
	var/static/list/interned = list()
	if(!length(overrides))
		return null
	var/key = ""
	for(var/role in overrides)
		key += "[role]=[overrides[role]];"
	. = interned[key]
	if(!.)
		. = overrides.Copy()
		interned[key] = .

/// Override hook for MATERIAL_MIX; returns this type's declared mix template.
/obj/proc/declared_material_mix()
	return null

/// This object's blueprint singleton, or null if it has no material composition.
/obj/proc/get_material_template() as /datum/material_template
	if(!material_template)
		return null
	if(material_template == /datum/material_template/mix)
		return declared_material_mix()
	return material_template_singleton(material_template)

/// Total material units, split between the template's roles.
/obj/proc/get_material_total()
	if(material_template == /datum/material_template/mix)
		var/datum/material_template/mix/mix = declared_material_mix()
		return mix?.total || 0
	return material_total

/// Material id filling `role`: this object's override, else the template default.
/obj/proc/material_id_for_role(role)
	var/material_id = material_overrides?[role]
	if(material_id)
		return material_id
	if(role == MATERIAL_ROLE_BULK && material_template == /datum/material_template/bulk)
		return material_bulk_material
	var/datum/material_template/template = get_material_template()
	return template?.default_material(role)

/obj/proc/material_for_role(role) as /datum/material
	var/datum/material_template/template = get_material_template()
	if(!template || !(role in template.roles))
		return null
	var/material_id = material_id_for_role(role)
	return material_id ? get_material_by_name(material_id) : null

/// The roles of this object's blueprint, in order. Read-only.
/obj/proc/material_roles()
	RETURN_TYPE(/list)
	var/datum/material_template/template = get_material_template()
	return template?.roles

/// Material units in one role: the template's fraction of this object's total.
/obj/proc/role_amount(role)
	var/datum/material_template/template = get_material_template()
	return template ? template.role_amount(role, get_material_total()) : 0

/// Material id -> units, summed over roles. Derived on demand; the caller owns the list.
/obj/proc/material_totals()
	RETURN_TYPE(/list)
	. = list()
	var/datum/material_template/template = get_material_template()
	if(!template)
		return .
	var/list/amounts = template.role_amounts(get_material_total())
	for(var/role in amounts)
		var/material_id = material_id_for_role(role)
		if(material_id && amounts[role])
			.[material_id] = (.[material_id] || 0) + amounts[role]

/// Whether this object has functional construction roles (not just plain bulk material).
/obj/proc/has_functional_construction()
	var/datum/material_template/template = get_material_template()
	return template && !template.bulk && length(template.roles)

/// The only supported way to change one functional part after construction.
/// Copy-on-write: the object's interned overrides are replaced, never edited.
/obj/proc/set_construction_material(role, material_id)
	var/list/overrides = material_overrides ? material_overrides.Copy() : list()
	var/datum/material_template/template = get_material_template()
	var/default_id
	if(role == MATERIAL_ROLE_BULK && material_template == /datum/material_template/bulk)
		default_id = material_bulk_material
	else
		default_id = template?.default_material(role)
	if(!material_id || material_id == default_id)
		overrides -= role
	else
		overrides[role] = material_id
	material_overrides = material_overrides_intern(overrides)

/// Rebuild this object to another blueprint: template, total and chosen materials.
/obj/proc/set_material_blueprint(template_path, total, list/materials_by_role)
	material_template = template_path
	material_total = total
	var/datum/material_template/template = get_material_template()
	var/list/overrides = list()
	for(var/role in materials_by_role)
		var/material_id = materials_by_role[role]
		if(material_id && material_id != template?.default_material(role))
			overrides[role] = material_id
	material_overrides = material_overrides_intern(overrides)

/// Make this object of one plain material, or of nothing with a null material.
/obj/proc/set_bulk_material(material_id, total)
	material_template = material_id ? /datum/material_template/bulk : null
	material_bulk_material = material_id
	material_total = material_id ? total : 0
	material_overrides = null

/obj/proc/primary_construction_material() as /datum/material
	var/static/list/primary_roles = list(MATERIAL_ROLE_WORKING, MATERIAL_ROLE_CONDUCTOR, MATERIAL_ROLE_STRUCTURE, MATERIAL_ROLE_FRAME, MATERIAL_ROLE_EMITTER, MATERIAL_ROLE_FABRIC, MATERIAL_ROLE_BODY, MATERIAL_ROLE_JACKET)
	for(var/role in primary_roles)
		var/datum/material/material = material_for_role(role)
		if(material)
			return material
	return null

/// Build to a blueprint with the user's material choices (lathes, crafting, tests).
/obj/proc/apply_material_construction(list/materials_by_role, template_path, total, customized = TRUE)
	var/datum/material_template/template = material_template_singleton(template_path)
	var/list/resolved = template?.resolve(materials_by_role)
	if(!length(resolved))
		return FALSE
	material_custom_assembly = customized
	set_material_blueprint(template_path, total, resolved)
	if(isitem(src))
		var/obj/item/item = src
		item.apply_material_role_effects(template.application)
	material_service_changed()
	return TRUE

/// Preserve the complete functional assembly when an item becomes an installed
/// object (or is taken apart again).  Copying only the visually dominant
/// material silently discarded liners, insulation, contacts, and similar parts.
/obj/proc/copy_material_construction_from(obj/source)
	if(!source)
		return FALSE
	if(source.material_template == /datum/material_template/mix)
		var/datum/material_template/mix/mix = source.declared_material_mix()
		material_template = null
		material_total = 0
		if(mix)
			// A mix is per type; carry the dominant material as plain bulk.
			var/dominant
			for(var/material_id in mix.amounts)
				if(!dominant || mix.amounts[material_id] > mix.amounts[dominant])
					dominant = material_id
			set_bulk_material(dominant, mix.total)
	else
		material_template = source.material_template
		material_total = source.material_total
		material_bulk_material = source.material_bulk_material
		material_overrides = source.material_overrides
	material_environment_liner_integrity = source.material_environment_liner_integrity
	material_environment_exterior_integrity = source.material_environment_exterior_integrity
	material_environment_fatigue = source.material_environment_fatigue
	material_environment_leaking = source.material_environment_leaking
	material_custom_assembly = source.material_custom_assembly
	if(!istype(source, /obj/item/stack) && source.material_assembly_id)
		material_assembly_id = source.material_assembly_id
	material_service_changed()
	if(source.material_service && material_service)
		material_service.set_temperature(source.material_service.current_temperature())
	return has_functional_construction()

/obj/proc/construction_summary()
	var/list/summary = list()
	if(!has_functional_construction())
		return summary
	for(var/role in material_roles())
		var/datum/material/material = material_for_role(role)
		if(material)
			summary += "[role]: [material.display_name]"
	return summary

/// Role-aware constitutive APIs. Systems consume the part that physically
/// performs the job instead of averaging an item into one magic material.
/obj/proc/construction_electrical_resistance(length_m, area_mm2, temperature, current_density = 0)
	var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR) || primary_construction_material()
	return conductor ? conductor.material_electrical_resistance(length_m, area_mm2, temperature, current_density) : null

/obj/proc/construction_thermal_conductance(area_m2, thickness_m, temperature)
	var/datum/material/thermal = material_for_role(MATERIAL_ROLE_THERMAL) || material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	var/conductance = thermal ? thermal.material_thermal_conductance(area_m2, thickness_m, temperature) : null
	if(!isnull(conductance) && thermal?.thermal_switch_temperature)
		var/switch_fraction = clamp((temperature - thermal.thermal_switch_temperature) / 20, 0, 1)
		conductance *= 1 + (thermal.thermal_switch_ratio - 1) * switch_fraction
	var/datum/material/insulator = material_for_role(MATERIAL_ROLE_INSULATION)
	if(!isnull(conductance) && insulator)
		var/insulation_conductance = insulator.material_thermal_conductance(area_m2, thickness_m, temperature)
		conductance = 1 / (1 / conductance + 1 / insulation_conductance)
	return conductance

/obj/proc/construction_pressure_limit(radius_mm, wall_thickness_mm, temperature)
	var/datum/material/structure = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	return structure ? structure.material_pressure_limit(radius_mm, wall_thickness_mm, temperature) : null

/obj/proc/construction_radiation_transmission(thickness_mm)
	var/datum/material/jacket = material_for_role(MATERIAL_ROLE_JACKET) || material_for_role(MATERIAL_ROLE_STRUCTURE) || primary_construction_material()
	return jacket ? jacket.material_radiation_transmission(thickness_mm) : 1

/obj/examine(mob/user)
	. = ..()
	if(has_functional_construction())
		. += span_notice("Construction: [jointext(construction_summary(), "; ")].")

// ---- Bulk material holders ----
// Debris from recyclers and digestion, random scrap and custom-material objects hold
// an arbitrary mix. That mix is genuine per-instance state, kept as one real list.

/obj/item
	/// Material id -> units for an object whose mix is arbitrary. Null for everything
	/// else, whose composition is its blueprint. Private to this instance.
	var/list/material_mix

/obj/item/material_totals()
	if(material_mix)
		return material_mix.Copy()
	return ..()

/// Replace this item's composition with an arbitrary mix (material id -> units).
/// Takes ownership of the list; an empty or null mix means made of nothing.
/obj/item/proc/set_material_mix(list/mix)
	material_template = null
	material_overrides = null
	material_mix = length(mix) ? mix : null

/// Add units of materials to this item's mix, starting from its current composition.
/obj/item/proc/add_materials(list/added)
	if(!material_mix)
		material_mix = material_totals()
	for(var/material_id in added)
		material_mix[material_id] = (material_mix[material_id] || 0) + added[material_id]

/// Scale every amount in this item's composition (lathe efficiency).
/obj/item/proc/scale_materials(factor)
	if(material_mix || material_template == /datum/material_template/mix)
		var/list/scaled = material_totals()
		for(var/material_id in scaled)
			scaled[material_id] = CEILING(scaled[material_id] * factor, 1)
		set_material_mix(scaled)
		return
	material_total = CEILING(material_total * factor, 1)

/// A type's material totals (material id -> units) from its declared blueprint,
/// read without an instance. Null if the type has no composition.
/proc/dq_type_material_totals(path)
	RETURN_TYPE(/list)
	var/obj/declared = path
	var/template_path = initial(declared.material_template)
	if(!template_path)
		return null
	var/datum/material_template/template
	var/total
	if(template_path == /datum/material_template/mix)
		var/datum/material_template/mix/mix = dq_type_material_mix(path)
		template = mix
		total = mix?.total
	else
		template = material_template_singleton(template_path)
		total = initial(declared.material_total)
	if(!template)
		return null
	. = list()
	var/list/amounts = template.role_amounts(total)
	for(var/role in amounts)
		var/material_id
		if(role == MATERIAL_ROLE_BULK && template_path == /datum/material_template/bulk)
			material_id = initial(declared.material_bulk_material)
		else
			material_id = template.default_material(role)
		if(material_id && amounts[role])
			.[material_id] = (.[material_id] || 0) + amounts[role]

/// Make this item of `amount` units of one material (a stack recipe's product). A
/// functional blueprint keeps its parts and takes the new total.
/obj/item/proc/set_single_material(material_id, amount)
	material_mix = null
	if(has_functional_construction())
		material_total = amount
		return
	set_bulk_material(material_id, amount)
