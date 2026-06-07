// /datum/material/dynamic — round-rolled material instantiated by
// SSquarry. Sits alongside the upstream static /datum/material subtypes
// in the same GLOB.name_to_material registry; anything that reads a
// material by name works without caring whether it was authored at
// compile time or rolled this round.
//
// Lifecycle:
//   - SSquarry rolls a band's worth at first access (see
//     get_exotic_materials_for_depth in exotic_material_subsystem.dm).
//   - Each material gets a unique generated `name` ("exotic_mat_<id>")
//     used as both the GLOB.name_to_material key and the
//     /datum/ore/exotic_material registration key.
//   - dq_roll_dynamic_material picks a class, rolls every core stat
//     from the per-class range table, and rolls a chance to attach 0-3
//     behavior components.

/datum/material/dynamic
	// Display name shown to players ("Caesirite"). Distinct from `name`,
	// which is the registry key ("exotic_mat_5").
	var/pretty_name = "Unknown Material"
	// Hex color string used to tint items / sheets / UI badges.
	var/color = "#888888"
	// Depth band this material was rolled for (1 = depths 1-5, etc).
	var/band = 1
	// Rarity tier (1 common, 2 uncommon, 3 rare). Drives the wall scan
	// icon and placement weight inside /datum/quarry_feature/exotic_vein.
	var/rarity = 1


/// Lookup helper used by sample items / analyzer / etc. Returns the
/// /datum/material/dynamic for a given round-rolled id, or null.
/proc/dq_get_dynamic_material(id)
	if(!id)
		return null
	return GLOB.name_to_material["exotic_mat_[id]"]


/// Build a fresh /datum/material/dynamic for the given band. Generates
/// name + color, picks a class, rolls all eleven core stats and 0-3
/// behavior components. The caller is responsible for registering the
/// instance in GLOB.name_to_material.
/proc/dq_roll_dynamic_material(band, id)
	var/datum/material/dynamic/M = new
	M.name = "exotic_mat_[id]"
	M.pretty_name = _dq_generate_material_name()
	M.display_name = M.pretty_name
	M.use_name = M.pretty_name
	M.color = _dq_generate_material_color()
	M.icon_colour = M.color
	M.band = band
	M.rarity = _dq_rarity_for_band(band)
	M.material_class = _dq_roll_material_class(band)
	M.stack_type = /obj/item/stack/material/exotic_dynamic
	// Mechanical
	M.hardness             = dq_roll_core_stat("hardness", M.material_class)
	M.density              = dq_roll_core_stat("density", M.material_class)
	M.integrity            = dq_roll_core_stat("integrity", M.material_class)
	M.elasticity           = dq_roll_core_stat("elasticity", M.material_class)
	M.brittleness          = dq_roll_core_stat("brittleness", M.material_class)
	// Thermal
	M.heat_resistance      = dq_roll_core_stat("heat_resistance", M.material_class)
	M.thermal_insulation   = dq_roll_core_stat("thermal_insulation", M.material_class)
	// Electrical / magnetic
	M.conductivity         = dq_roll_core_stat("conductivity", M.material_class)
	M.magnetism            = dq_roll_core_stat("magnetism", M.material_class)
	// Chemical
	M.reactivity           = dq_roll_core_stat("reactivity", M.material_class)
	M.corrosion_resistance = dq_roll_core_stat("corrosion_resistance", M.material_class)
	// Behavior components (independent per-class rolls).
	dq_roll_behavior_components(M)
	// Traits (35% chance, weighted by class).
	dq_roll_material_traits(M)
	return M


/// Per-band rarity. Each band's three materials are common / uncommon /
/// rare in slot order; this proc supplies a baseline that the SSquarry
/// roller then bumps by slot index.
/proc/_dq_rarity_for_band(band)
	if(band >= 5)
		return 3
	if(band >= 3)
		return 2
	return 1


/// Pick a material class for this band's roll. Currently uniform across
/// all four classes; could be skewed per band later (e.g. metals more
/// common at shallow depths, crystals at depth).
/proc/_dq_roll_material_class(band)
	var/static/list/pool = list(
		MATCLASS_METAL,
		MATCLASS_CRYSTAL,
		MATCLASS_ORGANIC,
		MATCLASS_CERAMIC,
	)
	return pick(pool)


/// Scan-icon hint used by the ore datum.
/datum/material/dynamic/proc/scan_icon_for_rarity()
	switch(rarity)
		if(1)
			return "mineral_common"
		if(2)
			return "mineral_uncommon"
		else
			return "mineral_rare"
