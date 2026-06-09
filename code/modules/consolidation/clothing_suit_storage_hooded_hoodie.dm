// Auto-generated. 5 variants of /obj/item/clothing/suit/storage/hooded/hoodie.

GLOBAL_LIST_INIT(dq_variants_suit_storage_hooded_hoodie, list(
	"redtrim" = list("name" = "red-trimmed hoodie", "icon_state" = "hoodie_redtrim", "desc" = "A warm jacket, now featuring a hood and a bold red trim!"),
	"bluetrim" = list("name" = "blue-trimmed hoodie", "icon_state" = "hoodie_bluetrim", "desc" = "A warm jacket, now featuring a hood and a cool blue trim!"),
	"greentrim" = list("name" = "green-trimmed hoodie", "icon_state" = "hoodie_greentrim", "desc" = "A warm jacket, now featuring a hood and a chilled green trim!"),
	"purpletrim" = list("name" = "purple-trimmed hoodie", "icon_state" = "hoodie_purpletrim", "desc" = "A warm jacket, now featuring a hood and a smart purple trim!"),
	"yellowtrim" = list("name" = "yellow-trimmed hoodie", "icon_state" = "hoodie_yellowtrim", "desc" = "A warm jacket, now featuring a hood and an eye-catching yellow trim!"),
))

/obj/item/clothing/suit/storage/hooded/hoodie/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/suit/storage/hooded/hoodie/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_suit_storage_hooded_hoodie[variant]
	if(!v)
		return
	if(v["name"])
		name = v["name"]
	if(v["icon_state"])
		icon_state = v["icon_state"]
	if(v["desc"])
		desc = v["desc"]
	if(v["item_state"])
		item_state = v["item_state"]
