/// Compatibility fields retained for save data and older callers. New
/// fabrication records every functional part in the object's material blueprint.
/obj/item
	var/engineered_material_id
	var/engineered_material_profile
	var/material_surgery_cleanliness_bonus = 0
	var/material_tool_quality_bonus = 0
	/// Effective physical values consumed by integrity, throwing, power and examination.
	var/material_effective_density = 0
	var/material_effective_electrical_resistance = 0
	var/material_accuracy_delta = 0
	var/material_recoil_delta = 0

/obj/item/proc/apply_engineered_material(datum/material/material, application_profile)
	if(!istype(material) || !application_profile)
		return FALSE
	var/datum/material_template/template = material_template_for_application(application_profile)
	var/list/choices = list()
	for(var/primary_role in template.roles)
		choices[primary_role] = material.name
		break
	return apply_material_construction(choices, template.type, SHEET_MATERIAL_AMOUNT)

/obj/item/proc/apply_material_role_effects(application_profile)
	var/datum/material/primary = primary_construction_material()
	if(!primary)
		return FALSE
	engineered_material_id = primary.name
	engineered_material_profile = application_profile
	var/total_amount = 0
	var/weighted_density = 0
	var/weighted_dielectric = 0
	var/datum/material_template/template = get_material_template()
	var/list/amounts = template?.role_amounts(get_material_total())
	for(var/role in amounts)
		var/datum/material/part_material = material_for_role(role)
		var/part_amount = amounts[role]
		if(!part_material || part_amount <= 0)
			continue
		total_amount += part_amount
		weighted_density += part_material.density * part_amount
		weighted_dielectric += part_material.dielectric_strength * part_amount
	if(total_amount > 0)
		material_effective_density = weighted_density / total_amount
		material_effective_electrical_resistance = weighted_dielectric / total_amount
		// Density changes the physical handling of every manufactured object;
		// dielectric performance changes its real electrical coupling.
		throw_speed = max(1, round(initial(throw_speed) * clamp(100 / max(material_effective_density, 10), 0.5, 1.5)))
		throw_range = max(1, round(initial(throw_range) * clamp(100 / max(material_effective_density, 10), 0.5, 1.5)))
		siemens_coefficient = clamp(initial(siemens_coefficient) * (1.25 - material_effective_electrical_resistance / 125), 0.05, 2)
	var/datum/material/structure = material_for_role(MATERIAL_ROLE_STRUCTURE) || material_for_role(MATERIAL_ROLE_FRAME) || material_for_role(MATERIAL_ROLE_BODY) || primary
	if(max_integrity > 0 && total_amount > 0)
		var/condition = uses_integrity ? get_integrity() / max_integrity : 1
		var/datum/material_template/reference_template = material_template_for_application(application_profile)
		var/reference_id = MAT_STEEL
		for(var/role in list(MATERIAL_ROLE_STRUCTURE, MATERIAL_ROLE_FRAME, MATERIAL_ROLE_BODY))
			var/default_id = reference_template.default_material(role)
			if(default_id)
				reference_id = default_id
				break
		var/datum/material/reference = get_material_by_name(reference_id)
		var/integrity_factor = clamp(structure.integrity / max(reference.integrity, 1), 0.2, 4)
		max_integrity = max(1, round(initial(max_integrity) * integrity_factor))
		if(uses_integrity)
			update_integrity(max_integrity * condition)
	primary.dq_apply_material_behaviors(src)
	switch(application_profile)
		if(MATERIAL_APPLICATION_TOOL)
			var/datum/material/working = material_for_role(MATERIAL_ROLE_WORKING) || primary
			var/datum/material/grip = material_for_role(MATERIAL_ROLE_GRIP) || primary
			force = max(initial(force), round((working.hardness + working.density) / 18))
			throwforce = max(initial(throwforce), round((working.integrity + working.density) / 28))
			toolspeed = clamp(1.25 - (working.hardness + working.elasticity + grip.elasticity * 0.25) / 245, 0.35, 1.25)
		if(MATERIAL_APPLICATION_SURGICAL)
			var/datum/material/working = material_for_role(MATERIAL_ROLE_WORKING) || primary
			var/datum/material/grip = material_for_role(MATERIAL_ROLE_GRIP) || primary
			force = max(initial(force), round(working.hardness / 8))
			toolspeed = clamp(1.15 - (working.hardness + working.elasticity + working.corrosion_resistance + grip.elasticity * 0.4 + grip.dielectric_strength * 0.2) / 390, 0.3, 1.15)
			material_surgery_cleanliness_bonus = clamp(round((working.corrosion_resistance + working.heat_resistance + working.reactivity * -0.5) / 3), 0, 35)
			material_tool_quality_bonus = clamp(round((working.hardness + working.elasticity + working.purity_equivalent()) / 20), 0, 15)
		if(MATERIAL_APPLICATION_CELL)
			if(istype(src, /obj/item/cell))
				var/obj/item/cell/cell = src
				var/datum/material/electrode = material_for_role(MATERIAL_ROLE_ELECTRODE) || primary
				var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR) || primary
				var/datum/material/insulation = material_for_role(MATERIAL_ROLE_INSULATION)
				var/datum/material/thermal = material_for_role(MATERIAL_ROLE_THERMAL) || conductor
				var/datum/material/casing = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary
				var/datum/material/reference_electrode = get_material_by_name(MAT_COPPER)
				var/reference_capacity = 0.65 + reference_electrode.conductivity / 140 + reference_electrode.heat_resistance / 350
				var/capacity_factor = clamp((0.65 + electrode.conductivity / 140 + electrode.heat_resistance / 350) / reference_capacity, 0.5, 2)
				cell.maxcharge = round(initial(cell.maxcharge) * capacity_factor)
				// Beam-conditioned crystalline electrodes retain deposited field
				// energy as real cell capacity rather than an abstract quality bonus.
				cell.maxcharge += round(electrode.field_energy_capacity)
				cell.charge = min(cell.charge, cell.maxcharge)
				cell.material_emp_resistance = clamp(round((insulation?.dielectric_strength || 0) * 0.5 + conductor.magnetism * 0.2 + casing.heat_resistance * 0.2), 0, 90)
				cell.robot_durability = clamp(round(casing.integrity / 2), 20, 125)
				cell.material_discharge_limit = max(1, round(initial(cell.maxcharge) * clamp((conductor.conductivity + thermal.heat_resistance * 0.5 + thermal.conductivity * (1 - thermal.thermal_insulation / 125) * 0.5) / 150, 0.1, 2)))
		if(MATERIAL_APPLICATION_ARMOR)
			if(istype(src, /obj/item/clothing))
				var/obj/item/clothing/clothing = src
				clothing.set_material(structure.name)
				// The outer layer remains the exposed material for reactions and appearance;
				// the load-bearing layer supplies the actual armor calculation.
				color = material_for_role(MATERIAL_ROLE_JACKET)?.icon_colour || structure.icon_colour
				var/datum/material/liner = material_for_role(MATERIAL_ROLE_LINER) || structure
				clothing.siemens_coefficient = clamp(initial(clothing.siemens_coefficient) * (1.2 - liner.dielectric_strength / 125), 0.05, 2)
				clothing.permeability_coefficient = clamp(initial(clothing.permeability_coefficient) * (1.2 - liner.corrosion_resistance / 125), 0.05, 2)
		if(MATERIAL_APPLICATION_MACHINE_PART, MATERIAL_APPLICATION_CAPACITOR, MATERIAL_APPLICATION_MANIPULATOR, MATERIAL_APPLICATION_MATTER_BIN, MATERIAL_APPLICATION_SCANNER, MATERIAL_APPLICATION_LASER)
			if(istype(src, /obj/item/stock_parts))
				var/obj/item/stock_parts/part = src
				part.material_id = primary.name
				part.rating = part.get_rating()
		if(MATERIAL_APPLICATION_FIREARM)
			if(istype(src, /obj/item/gun))
				var/obj/item/gun/gun = src
				var/datum/material/barrel = material_for_role(MATERIAL_ROLE_BARREL) || primary
				var/datum/material/receiver = material_for_role(MATERIAL_ROLE_STRUCTURE) || primary
				var/datum/material/grip = material_for_role(MATERIAL_ROLE_GRIP) || receiver
				gun.accuracy -= material_accuracy_delta
				gun.recoil -= material_recoil_delta
				material_accuracy_delta = clamp(round((barrel.hardness + barrel.heat_resistance + barrel.fracture_toughness - barrel.brittleness) / 35) - 4, -8, 8)
				material_recoil_delta = clamp(round((receiver.brittleness - receiver.fracture_toughness - grip.elasticity * 0.5) / 35), -3, 3)
				gun.accuracy += material_accuracy_delta
				gun.recoil = max(0, gun.recoil + material_recoil_delta)
		if(MATERIAL_APPLICATION_PROJECTILE)
			var/datum/material/projectile_material = material_for_role(MATERIAL_ROLE_WORKING) || primary
			if(istype(src, /obj/item/ammo_magazine))
				var/obj/item/ammo_magazine/magazine = src
				magazine.set_forged_materials(projectile_material, material_for_role(MATERIAL_ROLE_JACKET), material_for_role(MATERIAL_ROLE_CASING), material_for_role(MATERIAL_ROLE_PRIMER))
			else if(istype(src, /obj/item/ammo_casing))
				var/obj/item/ammo_casing/casing = src
				casing.set_forged_materials(projectile_material, material_for_role(MATERIAL_ROLE_JACKET), material_for_role(MATERIAL_ROLE_CASING), material_for_role(MATERIAL_ROLE_PRIMER))
		if(MATERIAL_APPLICATION_MAGAZINE)
			if(istype(src, /obj/item/ammo_magazine))
				var/obj/item/ammo_magazine/magazine = src
				var/datum/material/projectile_material = material_for_role(MATERIAL_ROLE_WORKING) || primary
				magazine.set_forged_materials(projectile_material, material_for_role(MATERIAL_ROLE_JACKET), material_for_role(MATERIAL_ROLE_CASING), material_for_role(MATERIAL_ROLE_PRIMER))
		if(MATERIAL_APPLICATION_ENERGY_DEVICE)
			if(istype(src, /obj/item/gun))
				var/obj/item/gun/gun = src
				var/datum/material/emitter = material_for_role(MATERIAL_ROLE_EMITTER) || primary
				var/datum/material/optics = material_for_role(MATERIAL_ROLE_OPTICAL) || emitter
				gun.accuracy -= material_accuracy_delta
				material_accuracy_delta = clamp(round((emitter.heat_resistance + optics.purity_equivalent() + optics.hardness - optics.brittleness) / 45) - 4, -8, 8)
				gun.accuracy += material_accuracy_delta
				if(istype(gun, /obj/item/gun/energy))
					var/obj/item/gun/energy/energy_gun = gun
					var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR) || primary
					var/datum/material/thermal = material_for_role(MATERIAL_ROLE_THERMAL) || conductor
					energy_gun.charge_cost = max(1, round(initial(energy_gun.charge_cost) * clamp(1.35 - conductor.conductivity / 200 - thermal.conductivity * (1 - thermal.thermal_insulation / 125) / 500, 0.55, 1.5)))
		if(MATERIAL_APPLICATION_SOFT_GOODS)
			if(istype(src, /obj/item/clothing))
				var/obj/item/clothing/clothing = src
				var/datum/material/fabric = material_for_role(MATERIAL_ROLE_FABRIC) || primary
				clothing.set_material(fabric.name)
				color = fabric.icon_colour
				var/datum/material/reinforcement = material_for_role(MATERIAL_ROLE_STRUCTURE) || fabric
				clothing.permeability_coefficient = clamp(initial(clothing.permeability_coefficient) * (1.15 - reinforcement.corrosion_resistance / 150), 0.05, 2)
		if(MATERIAL_APPLICATION_CABLE)
			var/datum/material/conductor = material_for_role(MATERIAL_ROLE_CONDUCTOR) || primary
			engineered_material_id = conductor.name
		if(MATERIAL_APPLICATION_LIGHT)
			if(istype(src, /obj/item/light))
				var/obj/item/light/light = src
				var/datum/material/emitter = material_for_role(MATERIAL_ROLE_EMITTER) || primary
				var/datum/material/optics = material_for_role(MATERIAL_ROLE_OPTICAL) || emitter
				var/datum/material/contacts = material_for_role(MATERIAL_ROLE_CONTACTS) || primary
				// Glass emitter + glass optics + copper contacts are the ordinary
				// station-light baseline. Material selection modifies that authored
				// output; it must not replace it with an arbitrary absolute scale.
				var/output_factor = clamp((dq_material_luminescence(emitter) * 2 + emitter.conductivity + contacts.conductivity) / 53, 0.35, 2)
				var/optical_factor = clamp((optics.purity_equivalent() + optics.integrity) / 180, 0.5, 1.5)
				light.brightness_power = max(0.2, light.init_brightness_power * output_factor)
				light.brightness_range = max(1, round(light.init_brightness_range * optical_factor))
				light.nightshift_power = max(0.1, light.init_nightshift_power * output_factor)
				light.nightshift_range = max(1, round(light.init_nightshift_range * optical_factor))
	return TRUE

/obj/item/cell
	var/material_discharge_limit = INFINITY

/datum/material/proc/purity_equivalent()
	if(istype(src, /datum/material/processed_alloy))
		var/datum/material/processed_alloy/processed = src
		return processed.batch_template?.purity || 80
	return 80

/obj/item/get_material()
	var/datum/material/constructed = primary_construction_material()
	if(constructed)
		return constructed
	if(engineered_material_id)
		return get_material_by_name(engineered_material_id)
	return ..()

/obj/item/examine(mob/user)
	. = ..()
	if(engineered_material_id && !has_functional_construction())
		var/datum/material/material = get_material_by_name(engineered_material_id)
		if(material)
			. += span_notice("Engineered from <b>[material.display_name]</b> for [engineered_material_profile].")

/obj/machinery/portable_atmospherics/canister
	var/pressure_liner_material_id

/obj/machinery/portable_atmospherics/canister/examine(mob/user)
	. = ..()
	var/datum/material/liner = material_for_role(MATERIAL_ROLE_LINER)
	if(liner)
		. += span_notice("Pressure liner: <b>[liner.display_name]</b> ([round(material_liner_integrity)]% intact); shell rated to [round(effective_maximum_pressure() / ONE_ATMOSPHERE, 0.1)] atmospheres.")

/// Apply the declared blueprint's physical effects (integrity, handling, and family
/// stats such as a cell's discharge limit) to a freshly made item. Stores no lists.
/obj/item/proc/apply_blueprint_effects()
	var/datum/material_template/template = get_material_template()
	if(template && !template.bulk)
		apply_material_role_effects(template.application)
