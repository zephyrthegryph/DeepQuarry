// Auto-generated. 6 variants of /obj/item/clothing/suit/storage/snowsuit.

GLOBAL_LIST_INIT(dq_variants_suit_storage_snowsuit, list(
	"command" = list("name" = "command snowsuit", "icon_state" = "snowsuit_command"),
	"security" = list("name" = "security snowsuit", "icon_state" = "snowsuit_security"),
	"medical" = list("name" = "medical snowsuit", "icon_state" = "snowsuit_medical"),
	"engineering" = list("name" = "engineering snowsuit", "icon_state" = "snowsuit_engineering"),
	"cargo" = list("name" = "cargo snowsuit", "icon_state" = "snowsuit_cargo"),
	"science" = list("name" = "science snowsuit", "icon_state" = "snowsuit_science"),
))

/obj/item/clothing/suit/storage/snowsuit/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/suit/storage/snowsuit/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_suit_storage_snowsuit[variant]
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
