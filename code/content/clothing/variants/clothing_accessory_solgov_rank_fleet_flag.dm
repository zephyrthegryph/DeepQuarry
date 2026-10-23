// Auto-generated. 4 variants of /obj/item/clothing/accessory/solgov/rank/fleet/flag.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_fleet_flag, list(
	"o8" = list("name" = "ranks (O-8 rear admiral)", "desc" = "Insignia denoting the rank of Rear Admiral."),
	"o9" = list("name" = "ranks (O-9 vice admiral)", "desc" = "Insignia denoting the rank of Vice Admiral."),
	"o10" = list("name" = "ranks (O-10 admiral)", "desc" = "Insignia denoting the rank of Admiral."),
	"o10_alt" = list("name" = "ranks (O-10 fleet admiral)", "desc" = "Insignia denoting the rank of Fleet Admiral."),
))

CAPABILITIES(/obj/item/clothing/accessory/solgov/rank/fleet/flag)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/solgov/rank/fleet/flag/proc/variant_table()
	return GLOB.dq_variants_accessory_solgov_rank_fleet_flag
