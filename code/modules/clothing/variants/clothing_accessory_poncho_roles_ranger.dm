// Auto-generated. 8 variants of /obj/item/clothing/accessory/poncho/roles/ranger.

GLOBAL_LIST_INIT(dq_variants_accessory_poncho_roles_ranger, list(
	"tan" = list("name" = "tan ranger poncho", "icon_state" = "rangerponcho_tan", "item_state" = "rangerponcho_tan"),
	"gray" = list("name" = "gray ranger poncho", "icon_state" = "rangerponcho_gray", "item_state" = "rangerponcho_gray"),
	"green" = list("name" = "green ranger poncho", "icon_state" = "rangerponcho_green", "item_state" = "rangerponcho_green"),
	"blue" = list("name" = "blue ranger poncho", "icon_state" = "rangerponcho_blue", "item_state" = "rangerponcho_blue"),
	"purple" = list("name" = "purple ranger poncho", "icon_state" = "rangerponcho_purple", "item_state" = "rangerponcho_purple"),
	"orange" = list("name" = "orange ranger poncho", "icon_state" = "rangerponcho_orange", "item_state" = "rangerponcho_orange"),
	"charcoal" = list("name" = "charcoal ranger poncho", "icon_state" = "rangerponcho_charcoal", "item_state" = "rangerponcho_charcoal"),
	"snow" = list("name" = "white ranger poncho", "icon_state" = "rangerponcho_snow", "item_state" = "rangerponcho_snow"),
))

/obj/item/clothing/accessory/poncho/roles/ranger/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/poncho/roles/ranger/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_poncho_roles_ranger[variant]
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
