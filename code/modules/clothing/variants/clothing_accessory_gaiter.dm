// Auto-generated. 8 variants of /obj/item/clothing/accessory/gaiter.

GLOBAL_LIST_INIT(dq_variants_accessory_gaiter, list(
	"tan" = list("name" = "tan neck gaiter", "icon_state" = "gaiter_tan"),
	"gray" = list("name" = "gray neck gaiter", "icon_state" = "gaiter_gray"),
	"green" = list("name" = "green neck gaiter", "icon_state" = "gaiter_green"),
	"blue" = list("name" = "blue neck gaiter", "icon_state" = "gaiter_blue"),
	"purple" = list("name" = "purple neck gaiter", "icon_state" = "gaiter_purple"),
	"orange" = list("name" = "orange neck gaiter", "icon_state" = "gaiter_orange"),
	"charcoal" = list("name" = "charcoal neck gaiter", "icon_state" = "gaiter_charcoal"),
	"snow" = list("name" = "white neck gaiter", "icon_state" = "gaiter_snow"),
))

/obj/item/clothing/accessory/gaiter/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/gaiter/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_gaiter[variant]
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
