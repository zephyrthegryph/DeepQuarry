// Material-selectable ammunition uses the same concrete mechanical properties
// as every other manufactured form. There is no separate payload/infusion layer.

/obj/item/ammo_casing
	var/datum/material/forged_material

/obj/item/ammo_casing/proc/set_forged_material(datum/material/material)
	if(!istype(material))
		return
	forged_material = material
	name = "[material.display_name] [initial(name)]"
	color = material.icon_colour
	if(BB)
		BB.damage = max(1, round(BB.damage * clamp(0.75 + material.density / 240 + material.hardness / 400, 0.75, 1.25)))
		BB.armor_penetration = max(0, BB.armor_penetration + round((material.hardness - material.brittleness * 0.35) / 12))
	material.dq_apply_material_behaviors(BB)

/obj/item/ammo_casing/proc/set_forged_materials(datum/material/core, datum/material/jacket, datum/material/case_material, datum/material/primer)
	set_forged_material(core)
	if(!BB)
		return
	if(jacket)
		BB.armor_penetration += clamp(round((jacket.hardness + jacket.fracture_toughness - jacket.brittleness) / 20) - 5, -5, 12)
	if(case_material)
		BB.accuracy += clamp(round((case_material.elasticity + case_material.heat_resistance - case_material.brittleness) / 25) - 3, -6, 6)
	if(primer)
		BB.accuracy += clamp(round((primer.reactivity + primer.purity_equivalent()) / 30) - 3, -4, 5)

/obj/item/ammo_magazine
	var/datum/material/forged_material

/obj/item/ammo_magazine/proc/set_forged_material(datum/material/material)
	if(!istype(material))
		return
	forged_material = material
	name = "[material.display_name] [initial(name)]"
	for(var/obj/item/ammo_casing/casing in stored_ammo)
		casing.set_forged_material(material)

/obj/item/ammo_magazine/proc/set_forged_materials(datum/material/core, datum/material/jacket, datum/material/case_material, datum/material/primer)
	if(!istype(core))
		return
	forged_material = core
	name = "[core.display_name] [initial(name)]"
	for(var/obj/item/ammo_casing/casing in stored_ammo)
		casing.set_forged_materials(core, jacket, case_material, primer)

/proc/material_round_examine(datum/material/forged, list/examine_text)
	if(!istype(forged))
		return
	if(istype(forged, /datum/material/processed_alloy))
		var/datum/material/processed_alloy/processed = forged
		examine_text += span_notice("Forged projectile stock: hardness [processed.hardness], density [processed.density], brittleness [processed.brittleness].")
