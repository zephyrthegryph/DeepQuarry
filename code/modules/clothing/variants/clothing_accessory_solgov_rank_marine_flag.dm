// Auto-generated. 4 variants of /obj/item/clothing/accessory/solgov/rank/marine/flag.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_marine_flag, list(
	"o8" = list("name" = "ranks (O-8 major general)", "desc" = "Insignia denoting the rank of Major General."),
	"o9" = list("name" = "ranks (O-9 lieutenant general)", "desc" = "Insignia denoting the rank of lieutenant general."),
	"o10" = list("name" = "ranks (O-10 general)", "desc" = "Insignia denoting the rank of General."),
	"o10_alt" = list("name" = "ranks (O-10 field marshal)", "desc" = "Insignia denoting the rank of Field Marshal."),
))

CAPABILITIES(/obj/item/clothing/accessory/solgov/rank/marine/flag)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/solgov/rank/marine/flag/proc/variant_table()
	return GLOB.dq_variants_accessory_solgov_rank_marine_flag
