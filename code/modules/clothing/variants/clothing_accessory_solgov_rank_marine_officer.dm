// Auto-generated. 5 variants of /obj/item/clothing/accessory/solgov/rank/marine/officer.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_marine_officer, list(
	"o2" = list("name" = "ranks (O-2 first lieutenant)", "desc" = "Insignia denoting the rank of First Lieutenant."),
	"o3" = list("name" = "ranks (O-3 captain)", "desc" = "Insignia denoting the rank of Captain."),
	"o4" = list("name" = "ranks (O-4 major)", "desc" = "Insignia denoting the rank of Major."),
	"o5" = list("name" = "ranks (O-5 lieutenant colonel)", "desc" = "Insignia denoting the rank of Lieutenant Colonel."),
	"o6" = list("name" = "ranks (O-6 colonel)", "desc" = "Insignia denoting the rank of Colonel."),
))

CAPABILITIES(/obj/item/clothing/accessory/solgov/rank/marine/officer)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/solgov/rank/marine/officer/proc/variant_table()
	return GLOB.dq_variants_accessory_solgov_rank_marine_officer
