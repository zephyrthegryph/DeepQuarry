// Variant tables readable by type, for the property registry
// (code/datums/properties/). Each consolidated family (README.md) maps its
// parent type to the name of its GLOB table. Only tables keyed by var name
// belong here; the positional crayon and marker tables do not.
// A family added without an entry here still works in game, but the
// registry cannot see its per-variant overrides.
GLOBAL_LIST_INIT(dq_variant_tables, list(
	/obj/item/clothing/accessory/altevian_badge/aquila = "dq_variants_accessory_altevian_badge_aquila",
	/obj/item/clothing/accessory/gaiter = "dq_variants_accessory_gaiter",
	/obj/item/clothing/accessory/poncho/roles/cloak/boat = "dq_variants_accessory_poncho_roles_cloak_boat",
	/obj/item/clothing/accessory/poncho/roles/cloak/crop_jacket = "dq_variants_accessory_poncho_roles_cloak_crop_jacket",
	/obj/item/clothing/accessory/poncho/roles/cloak/mantle = "dq_variants_accessory_poncho_roles_cloak_mantle",
	/obj/item/clothing/accessory/poncho/roles/cloak/shroud = "dq_variants_accessory_poncho_roles_cloak_shroud",
	/obj/item/clothing/accessory/poncho/roles/ranger = "dq_variants_accessory_poncho_roles_ranger",
	/obj/item/clothing/accessory/replika = "dq_variants_accessory_replika",
	/obj/item/clothing/accessory/solgov/rank/ec/officer = "dq_variants_accessory_solgov_rank_ec_officer",
	/obj/item/clothing/accessory/solgov/rank/fleet/enlisted = "dq_variants_accessory_solgov_rank_fleet_enlisted",
	/obj/item/clothing/accessory/solgov/rank/fleet/flag = "dq_variants_accessory_solgov_rank_fleet_flag",
	/obj/item/clothing/accessory/solgov/rank/fleet/officer = "dq_variants_accessory_solgov_rank_fleet_officer",
	/obj/item/clothing/accessory/solgov/rank/marine/enlisted = "dq_variants_accessory_solgov_rank_marine_enlisted",
	/obj/item/clothing/accessory/solgov/rank/marine/flag = "dq_variants_accessory_solgov_rank_marine_flag",
	/obj/item/clothing/accessory/solgov/rank/marine/officer = "dq_variants_accessory_solgov_rank_marine_officer",
	/obj/item/clothing/head/beret/solgov = "dq_variants_head_beret_solgov",
	/obj/item/clothing/head/tesh_hood/standard = "dq_variants_head_tesh_hood_standard",
	/obj/item/clothing/suit/captunic/capjacket/altevian_admiral = "dq_variants_suit_captunic_capjacket_altevian_admiral",
	/obj/item/clothing/suit/storage/hooded/hoodie = "dq_variants_suit_storage_hooded_hoodie",
	/obj/item/clothing/suit/storage/snowsuit = "dq_variants_suit_storage_snowsuit",
	/obj/item/clothing/suit/storage/teshari/beltcloak/standard = "dq_variants_suit_storage_teshari_beltcloak_standard",
	/obj/item/clothing/under/cohesion = "dq_variants_under_cohesion",
	/obj/item/clothing/under/explorer/utility = "dq_variants_under_explorer_utility",
	/obj/item/clothing/under/teshari/smock = "dq_variants_under_teshari_smock",
	/obj/item/clothing/under/teshari/smock/dress = "dq_variants_under_teshari_smock_dress",
	/obj/item/clothing/under/teshari/undercoat/standard/worksuit = "dq_variants_under_teshari_undercoat_standard_worksuit",
	/obj/item/clothing/under/turtlebaggy = "dq_variants_under_turtlebaggy",
))

/// The variant table for `path`, searching up the parents: variant key -> list(var name = value).
/proc/dq_variant_table(path)
	var/list/tables = GLOB.dq_variant_tables
	while(path)
		var/glob_name = tables[path]
		if(glob_name)
			return GLOB.vars[glob_name]
		if(path == /datum)
			return null
		path = type2parent(path)
	return null

/// The var overrides of variant `key` on `path`, or null.
/proc/dq_variant_vars(path, key)
	if(isnull(key))
		return null
	var/list/table = dq_variant_table(path)
	return table?[key]
