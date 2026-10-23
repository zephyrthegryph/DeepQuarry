// Auto-generated. 6 variants of /obj/item/clothing/accessory/altevian_badge/aquila.

GLOBAL_LIST_INIT(dq_variants_accessory_altevian_badge_aquila, list(
	"silver" = list("icon_state" = "altevian_aquila_silver"),
	"bronze" = list("icon_state" = "altevian_aquila_bronze"),
	"black" = list("icon_state" = "altevian_aquila_black"),
	"exotic" = list("icon_state" = "altevian_aquila_exotic"),
	"phoron" = list("icon_state" = "altevian_aquila_phoron"),
	"hydrogen" = list("icon_state" = "altevian_aquila_hydrogen"),
))

CAPABILITIES(/obj/item/clothing/accessory/altevian_badge/aquila)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/altevian_badge/aquila/proc/variant_table()
	return GLOB.dq_variants_accessory_altevian_badge_aquila
