// Auto-generated. 4 variants of /obj/item/clothing/accessory/solgov/rank/ec/officer.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_ec_officer, list(
	"o3" = list("name" = "ranks (O-3 lieutenant)", "icon_state" = "ecrank_o3", "desc" = "Insignia denoting the rank of Lieutenant."),
	"o5" = list("name" = "ranks (O-5 commander)", "icon_state" = "ecrank_o5", "desc" = "Insignia denoting the rank of Commander."),
	"o6" = list("name" = "ranks (O-6 captain)", "icon_state" = "ecrank_o6", "desc" = "Insignia denoting the rank of Captain."),
	"o8" = list("name" = "ranks (O-8 admiral)", "icon_state" = "ecrank_o8", "desc" = "Insignia denoting the rank of Admiral."),
))

CAPABILITIES(/obj/item/clothing/accessory/solgov/rank/ec/officer)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/solgov/rank/ec/officer/proc/variant_table()
	return GLOB.dq_variants_accessory_solgov_rank_ec_officer
