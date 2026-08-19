/// Generic bridge between a processed material and ordinary game items that were
/// never part of the legacy /obj/item/material hierarchy.
/obj/item
	var/engineered_material_id
	var/engineered_material_profile
	var/material_surgery_cleanliness_bonus = 0
	var/material_tool_quality_bonus = 0

/obj/item/proc/apply_engineered_material(datum/material/material, application_profile)
	if(!istype(material) || !application_profile)
		return FALSE
	engineered_material_id = material.name
	engineered_material_profile = application_profile
	name = "[material.display_name] [initial(name)]"
	color = material.icon_colour
	matter = material.get_matter()
	material.dq_apply_material_behaviors(src)
	switch(application_profile)
		if(MATERIAL_APPLICATION_TOOL)
			force = max(initial(force), round((material.hardness + material.density) / 18))
			throwforce = max(initial(throwforce), round((material.integrity + material.density) / 28))
			toolspeed = clamp(1.25 - (material.hardness + material.elasticity) / 220, 0.35, 1.25)
		if(MATERIAL_APPLICATION_SURGICAL)
			force = max(initial(force), round(material.hardness / 8))
			toolspeed = clamp(1.15 - (material.hardness + material.elasticity + material.corrosion_resistance) / 330, 0.3, 1.15)
			material_surgery_cleanliness_bonus = clamp(round((material.corrosion_resistance + material.heat_resistance + material.reactivity * -0.5) / 3), 0, 35)
			material_tool_quality_bonus = clamp(round((material.hardness + material.elasticity + material.purity_equivalent()) / 20), 0, 15)
		if(MATERIAL_APPLICATION_CELL)
			if(istype(src, /obj/item/cell))
				var/obj/item/cell/cell = src
				var/capacity_factor = clamp(0.65 + material.conductivity / 90 + material.heat_resistance / 250, 0.75, 2.25)
				cell.maxcharge = round(initial(cell.maxcharge) * capacity_factor)
				cell.charge = cell.maxcharge
				cell.material_emp_resistance = clamp(round(material.magnetism * 0.45 + material.heat_resistance * 0.35 + material.purity_equivalent() * 0.2), 0, 90)
				cell.robot_durability = clamp(round(material.integrity / 2), 20, 125)
	return TRUE

/datum/material/proc/purity_equivalent()
	if(istype(src, /datum/material/processed_alloy))
		var/datum/material/processed_alloy/processed = src
		return processed.batch_template.purity
	return 80

/obj/item/get_material()
	if(engineered_material_id)
		return get_material_by_name(engineered_material_id)
	return ..()

/obj/item/examine(mob/user)
	. = ..()
	if(engineered_material_id)
		var/datum/material/material = get_material_by_name(engineered_material_id)
		if(material)
			. += span_notice("Engineered from <b>[material.display_name]</b> for [engineered_material_profile].")

/obj/machinery/portable_atmospherics/canister
	var/pressure_liner_material_id

/obj/machinery/portable_atmospherics/canister/examine(mob/user)
	. = ..()
	if(pressure_liner_material_id)
		var/datum/material/material = get_material_by_name(pressure_liner_material_id)
		. += span_notice("Pressure liner: <b>[material?.display_name || pressure_liner_material_id]</b>; rated to [round(pressure_resistance / ONE_ATMOSPHERE, 0.1)] atmospheres and [round(temperature_resistance)] K.")
