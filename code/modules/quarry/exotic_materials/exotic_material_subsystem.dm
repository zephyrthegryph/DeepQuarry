// SSquarry extensions for the dynamic-material system.
//
// Materials are round-rolled lazily: the first time any depth in a band
// generates, the band's three /datum/material/dynamic instances are
// created and registered in GLOB.name_to_material (the upstream material
// registry). Each gets a corresponding /datum/ore/exotic_material in
// GLOB.ore_data so the existing wall-placement pipeline can drop them.
//
// State lives on the SSquarry singleton (see quarry_controller.dm). We
// re-open the subsystem here purely to add fields and procs.

/datum/controller/subsystem/quarry
	/// "[band]" -> list(/datum/material/dynamic, ...). Lazy-populated.
	var/list/dynamic_materials_by_band
	/// Round-monotonic counter for material ids. Drives the registry
	/// key "exotic_mat_<id>" so two bands never collide.
	var/dynamic_material_id_counter = 0
	/// id -> /datum/material/dynamic. Flat lookup for sample items,
	/// which only know their id.
	var/list/dynamic_materials_by_id


/// Convert a depth into a band index. Depths 1-5 -> band 1, 6-10 -> 2, etc.
/// Surface (depth 0) returns 0 — no exotic materials on the surface.
/proc/dq_band_for_depth(depth)
	if(depth <= 0)
		return 0
	return CEILING(depth, 5) / 5


/// Fetch the materials rolled for a given depth's band, rolling them on
/// demand if this is the first access. Returns a (possibly empty) list of
/// /datum/material/dynamic.
/datum/controller/subsystem/quarry/proc/get_exotic_materials_for_depth(depth)
	var/band = dq_band_for_depth(depth)
	if(band <= 0)
		return list()
	if(!dynamic_materials_by_band)
		dynamic_materials_by_band = list()
	var/key = "[band]"
	if(!dynamic_materials_by_band[key])
		dynamic_materials_by_band[key] = _roll_exotic_band(band)
	return dynamic_materials_by_band[key]


/// Roll a single band's materials. Three by default.
/datum/controller/subsystem/quarry/proc/_roll_exotic_band(band)
	var/list/result = list()
	if(!dynamic_materials_by_id)
		dynamic_materials_by_id = list()

	for(var/i in 1 to 3)
		dynamic_material_id_counter++
		var/datum/material/dynamic/M = dq_roll_dynamic_material(band, dynamic_material_id_counter)
		// Override slotted rarity: the per-band common/uncommon/rare
		// pattern is more interesting than a flat per-band rarity.
		switch(i)
			if(1)
				M.rarity = max(1, M.rarity)
			if(2)
				M.rarity = clamp(M.rarity + 0, 1, 3)
			else
				M.rarity = clamp(M.rarity + 1, 1, 3)
		result += M
		dynamic_materials_by_id["[dynamic_material_id_counter]"] = M
		GLOB.name_to_material[lowertext(M.name)] = M
		_register_exotic_ore(M, dynamic_material_id_counter)

	return result


/// Register one exotic material as a /datum/ore subtype in GLOB.ore_data
/// so the existing wall-placement pipeline can drop it. The ore datum's
/// `name` is what feature/ore_contributions list, and what UpdateMineral
/// keys off.
/datum/controller/subsystem/quarry/proc/_register_exotic_ore(datum/material/dynamic/M, id)
	var/datum/ore/exotic_material/OD = new
	OD.name = "exotic_mat_[id]"
	OD.display_name = M.pretty_name
	OD.material_id = id
	OD.scan_icon = M.scan_icon_for_rarity()
	OD.result_amount = 2
	OD.spread_chance = 8
	OD.ore = /obj/item/exotic_material_sample
	GLOB.ore_data[OD.name] = OD


/// Lookup a material by its round-id. Sample items carry just the id;
/// this is how they find the live datum.
/datum/controller/subsystem/quarry/proc/get_exotic_material(id)
	if(!dynamic_materials_by_id || !id)
		return null
	return dynamic_materials_by_id["[id]"]
