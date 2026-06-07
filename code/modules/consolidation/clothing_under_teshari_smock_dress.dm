// Auto-generated. 4 variants of /obj/item/clothing/under/teshari/smock/dress.

GLOBAL_LIST_INIT(dq_variants_under_teshari_smock_dress, list(
	"science" = list("name" = "small research dress", "icon_state" = "tesh_dress_science"),
	"security" = list("name" = "small security dress", "icon_state" = "tesh_dress_security"),
	"engine" = list("name" = "small engineering dress", "icon_state" = "tesh_dress_engine"),
	"medical" = list("name" = "small medical dress", "icon_state" = "tesh_dress_medical"),
))

/obj/item/clothing/under/teshari/smock/dress/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/under/teshari/smock/dress/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_under_teshari_smock_dress[variant]
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
