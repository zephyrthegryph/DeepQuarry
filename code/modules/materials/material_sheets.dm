// /obj/item/stack/material/exotic_dynamic — shared sheet stack subtype
// for round-rolled materials.
//
// Each rolled /datum/material/dynamic registers its `name` in
// GLOB.name_to_material ("exotic_mat_<id>"). A single stack subtype here
// covers all of them — the per-stack material is set at spawn time via
// the material_name constructor arg, and the upstream stack pipeline
// picks up the right /datum/material instance via get_material_by_name.

/obj/item/stack/material/exotic_dynamic
	icon = 'icons/obj/mining.dmi'
	icon_state = "ore_diamond"
	// Placeholder material for a bare-instantiated stack (e.g. unit-test
	// subtype enumeration). Real exotic spawns pass _material_name, which
	// overrides this in Initialize(). Must be a registered material so a
	// bare stack doesn't runtime — "exotic_mat_0" is never registered.
	default_type = MAT_STEEL
	no_variants = TRUE
	pass_color = TRUE
	strict_color_stacking = TRUE
	drop_sound = 'sound/items/drop/axe.ogg'
	pickup_sound = 'sound/items/pickup/axe.ogg'

/obj/item/stack/material/exotic_dynamic/Initialize(mapload, _amount, _material_name)
	if(_material_name)
		default_type = _material_name
	. = ..(mapload, _amount)
	if(material)
		color = material.icon_colour


/// Spawn an exotic sheet stack at a turf, tagged with the given
/// round-rolled material id.
/proc/dq_spawn_exotic_sheet(turf/T, material_id, amount = 1)
	if(!T || !material_id || amount <= 0)
		return null
	var/datum/material/M = GLOB.name_to_material["exotic_mat_[material_id]"]
	if(!M)
		return null
	var/obj/item/stack/material/exotic_dynamic/S = new(T, amount, "exotic_mat_[material_id]")
	return S
