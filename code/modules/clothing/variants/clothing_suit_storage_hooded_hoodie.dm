// Auto-generated. 5 variants of /obj/item/clothing/suit/storage/hooded/hoodie.

GLOBAL_LIST_INIT(dq_variants_suit_storage_hooded_hoodie, list(
	"redtrim" = list("name" = "red-trimmed hoodie", "icon_state" = "hoodie_redtrim", "desc" = "A warm jacket, now featuring a hood and a bold red trim!"),
	"bluetrim" = list("name" = "blue-trimmed hoodie", "icon_state" = "hoodie_bluetrim", "desc" = "A warm jacket, now featuring a hood and a cool blue trim!"),
	"greentrim" = list("name" = "green-trimmed hoodie", "icon_state" = "hoodie_greentrim", "desc" = "A warm jacket, now featuring a hood and a chilled green trim!"),
	"purpletrim" = list("name" = "purple-trimmed hoodie", "icon_state" = "hoodie_purpletrim", "desc" = "A warm jacket, now featuring a hood and a smart purple trim!"),
	"yellowtrim" = list("name" = "yellow-trimmed hoodie", "icon_state" = "hoodie_yellowtrim", "desc" = "A warm jacket, now featuring a hood and an eye-catching yellow trim!"),
))

CAPABILITIES(/obj/item/clothing/suit/storage/hooded/hoodie)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/suit/storage/hooded/hoodie/proc/variant_table()
	return GLOB.dq_variants_suit_storage_hooded_hoodie
