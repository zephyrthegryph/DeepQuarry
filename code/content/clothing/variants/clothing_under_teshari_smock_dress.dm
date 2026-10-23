// Auto-generated. 4 variants of /obj/item/clothing/under/teshari/smock/dress.

GLOBAL_LIST_INIT(dq_variants_under_teshari_smock_dress, list(
	"science" = list("name" = "small research dress", "icon_state" = "tesh_dress_science"),
	"security" = list("name" = "small security dress", "icon_state" = "tesh_dress_security"),
	"engine" = list("name" = "small engineering dress", "icon_state" = "tesh_dress_engine"),
	"medical" = list("name" = "small medical dress", "icon_state" = "tesh_dress_medical"),
))

CAPABILITIES(/obj/item/clothing/under/teshari/smock/dress)
	variants(nameof(variant), PROC_REF(own_variant_table)) // its own rows replace the parent family's

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/teshari/smock/dress/proc/own_variant_table()
	return GLOB.dq_variants_under_teshari_smock_dress
