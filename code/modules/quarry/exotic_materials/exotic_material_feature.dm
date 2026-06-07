// Quarry feature that places a vein of dynamic materials.
//
// At setup time pulls the band's rolled /datum/material/dynamic
// instances from SSquarry and writes their registered names into
// ore_contributions; the placer then drops a vein of those walls.

/datum/quarry_feature/exotic_vein
	name = "Exotic Vein"
	description = "An unfamiliar mineral signature, rare enough that geology hasn't catalogued it."
	vein_count = 4
	vein_size = 12

/datum/quarry_feature/exotic_vein/on_layer_setup(datum/quarry_layer/L)
	if(!L || !SSquarry)
		return
	var/list/materials = SSquarry.get_exotic_materials_for_depth(L.depth)
	if(!length(materials))
		return
	ore_contributions = list()
	// Weight by inverse rarity — common materials show up more often,
	// rare ones are sparse even when this feature rolls.
	for(var/datum/material/dynamic/M as anything in materials)
		var/weight = 10
		switch(M.rarity)
			if(1)
				weight = 10
			if(2)
				weight = 6
			else
				weight = 3
		ore_contributions["exotic_mat_[_dq_id_for_material(M)]"] = weight


/// Resolve a dynamic material back to its round-id. SSquarry's
/// dynamic_materials_by_id is keyed by stringified id; we walk it.
/proc/_dq_id_for_material(datum/material/dynamic/M)
	if(!SSquarry?.dynamic_materials_by_id)
		return 0
	for(var/key in SSquarry.dynamic_materials_by_id)
		if(SSquarry.dynamic_materials_by_id[key] == M)
			return text2num(key)
	return 0
