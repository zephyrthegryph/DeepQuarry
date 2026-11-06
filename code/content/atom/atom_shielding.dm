// How an atom takes hits and shields radiation: the atom_shielding() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(atom_shielding(deflection = 5))), read with shielding_of(A).deflection, written at run time with set_<old var>().
//
//   deflection   damage below this does nothing
//   damage_wear   how a damaged one is described
//   announce_bands   it says so when it crosses a damage band
//   rad_material / rad_thickness_mm   what it shields radiation with, and how thick

STATIC_ENTRY(atom_shielding)

/proc/atom_shielding(deflection = null, damage_wear = null, announce_bands = null, rad_material = null, rad_thickness_mm = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ATOM_SHIELDING, null, list("deflection" = deflection, "damage_wear" = damage_wear, "announce_bands" = announce_bands, "rad_material" = rad_material, "rad_thickness_mm" = rad_thickness_mm))

/datum/type_trait/atom_shielding
	var/deflection = 0
	var/damage_wear = "scrapes and dents"
	var/announce_bands = FALSE
	var/rad_material = null
	var/rad_thickness_mm = 0

/datum/type_trait/atom_shielding/copy_values(datum/type_trait/atom_shielding/into)
	into.deflection = deflection
	into.damage_wear = damage_wear
	into.announce_bands = announce_bands
	into.rad_material = rad_material
	into.rad_thickness_mm = rad_thickness_mm

/datum/entry_engine/type_trait/atom_shielding
	kind = ENTRY_ATOM_SHIELDING
	trait_type = /datum/type_trait/atom_shielding
	publish_key = ATOM_SHIELDING_KEY
	base_type = /atom
	var_names = list("damage_deflection" = "deflection", "damage_wear" = "damage_wear", "announce_damage_bands" = "announce_bands", "rad_shield_material" = "rad_material", "rad_shield_thickness_mm" = "rad_thickness_mm")

/// The holder's atom_shielding values (its own once one was set at run time). Read only.
READS_AS(/proc/shielding_of, ATOM_SHIELDING_KEY)
/proc/shielding_of(atom/holder) as /datum/type_trait/atom_shielding
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ATOM_SHIELDING)

/// What a type declares (no instance): the old initial().
/proc/shielding_of_type(type) as /datum/type_trait/atom_shielding
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ATOM_SHIELDING)

/atom/proc/set_damage_deflection(value)
	return set_trait(src, ENTRY_ATOM_SHIELDING, "deflection", value)

/atom/proc/set_damage_wear(value)
	return set_trait(src, ENTRY_ATOM_SHIELDING, "damage_wear", value)

/atom/proc/set_announce_damage_bands(value)
	return set_trait(src, ENTRY_ATOM_SHIELDING, "announce_bands", value)

/atom/proc/set_rad_shield_material(value)
	return set_trait(src, ENTRY_ATOM_SHIELDING, "rad_material", value)

/atom/proc/set_rad_shield_thickness_mm(value)
	return set_trait(src, ENTRY_ATOM_SHIELDING, "rad_thickness_mm", value)
