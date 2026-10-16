STATIC_ENTRY(shielding_config)

/proc/shielding_config(rad_shield_material = null, rad_shield_thickness_mm = null)
	return entry_make(ENTRY_SHIELDING_CONFIG, null, list("rad_shield_material" = rad_shield_material, "rad_shield_thickness_mm" = rad_shield_thickness_mm))

/datum/type_trait/shielding_config
	var/rad_shield_material = null
	var/rad_shield_thickness_mm = 0

/datum/type_trait/shielding_config/copy_values(datum/type_trait/shielding_config/into)
	into.rad_shield_material = rad_shield_material
	into.rad_shield_thickness_mm = rad_shield_thickness_mm

/datum/entry_engine/type_trait/shielding_config
	kind = ENTRY_SHIELDING_CONFIG
	trait_type = /datum/type_trait/shielding_config
	publish_key = SHIELDING_CONFIG_KEY
	base_type = /atom
	var_names = list("rad_shield_material" = "rad_shield_material", "rad_shield_thickness_mm" = "rad_shield_thickness_mm")

READS_AS(/proc/shielding_config_of, SHIELDING_CONFIG_KEY)
/proc/shielding_config_of(atom/holder) as /datum/type_trait/shielding_config
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_SHIELDING_CONFIG)

/proc/shielding_config_of_type(path) as /datum/type_trait/shielding_config
	READS_FROM()
	return type_trait_of_type(path, ENTRY_SHIELDING_CONFIG)
