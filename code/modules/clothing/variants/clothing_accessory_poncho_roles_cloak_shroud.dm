// Auto-generated. 10 variants of /obj/item/clothing/accessory/poncho/roles/cloak/shroud.

GLOBAL_LIST_INIT(dq_variants_accessory_poncho_roles_cloak_shroud, list(
	"cap" = list("name" = "site manager shroud", "icon_state" = "capshroud", "item_state" = "capshroud"),
	"hop" = list("name" = "head of personnel shroud", "icon_state" = "hopshroud", "item_state" = "hopshroud"),
	"security" = list("name" = "security shroud", "icon_state" = "secshroud", "item_state" = "secshroud"),
	"engineering" = list("name" = "engineering shroud", "icon_state" = "engshroud", "item_state" = "engshroud"),
	"atmos" = list("name" = "atmospherics shroud", "icon_state" = "atmosshroud", "item_state" = "atmosshroud"),
	"medical" = list("name" = "medical shroud", "icon_state" = "medshroud", "item_state" = "medshroud"),
	"service" = list("name" = "service shroud", "icon_state" = "botshroud", "item_state" = "botshroud"),
	"cargo" = list("name" = "cargo shroud", "icon_state" = "supshroud", "item_state" = "supshroud"),
	"mining" = list("name" = "mining shroud", "icon_state" = "minshroud", "item_state" = "minshroud"),
	"science" = list("name" = "research shroud", "icon_state" = "scishroud", "item_state" = "scishroud"),
))

CAPABILITIES(/obj/item/clothing/accessory/poncho/roles/cloak/shroud)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/poncho/roles/cloak/shroud/proc/variant_table()
	return GLOB.dq_variants_accessory_poncho_roles_cloak_shroud
