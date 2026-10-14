// Auto-generated. 10 variants of /obj/item/clothing/accessory/poncho/roles/cloak/boat.

GLOBAL_LIST_INIT(dq_variants_accessory_poncho_roles_cloak_boat, list(
	"cap" = list("name" = "site manager boat cloak", "icon_state" = "capboatcloak", "item_state" = "capboatcloak"),
	"hop" = list("name" = "head of personnel boat cloak", "icon_state" = "hopboatcloak", "item_state" = "hopboatcloak"),
	"security" = list("name" = "security boat cloak", "icon_state" = "secboatcloak", "item_state" = "secboatcloak"),
	"engineering" = list("name" = "engineering boat cloak", "icon_state" = "engboatcloak", "item_state" = "engboatcloak"),
	"atmos" = list("name" = "atmospherics boat cloak", "icon_state" = "atmosboatcloak", "item_state" = "atmosboatcloak"),
	"medical" = list("name" = "medical boat cloak", "icon_state" = "medboatcloak", "item_state" = "medboatcloak"),
	"service" = list("name" = "service boat cloak", "icon_state" = "botboatcloak", "item_state" = "botboatcloak"),
	"cargo" = list("name" = "cargo boat cloak", "icon_state" = "supboatcloak", "item_state" = "supboatcloak"),
	"mining" = list("name" = "mining boat cloak", "icon_state" = "minboatcloak", "item_state" = "minboatcloak"),
	"science" = list("name" = "research boat cloak", "icon_state" = "sciboatcloak", "item_state" = "sciboatcloak"),
))

CAPABILITIES(/obj/item/clothing/accessory/poncho/roles/cloak/boat)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/poncho/roles/cloak/boat/proc/variant_table()
	return GLOB.dq_variants_accessory_poncho_roles_cloak_boat
