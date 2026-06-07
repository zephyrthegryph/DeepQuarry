// Auto-generated. 6 variants of /obj/item/clothing/accessory/altevian_badge/aquila.

GLOBAL_LIST_INIT(dq_variants_accessory_altevian_badge_aquila, list(
	"silver" = list("icon_state" = "altevian_aquila_silver"),
	"bronze" = list("icon_state" = "altevian_aquila_bronze"),
	"black" = list("icon_state" = "altevian_aquila_black"),
	"exotic" = list("icon_state" = "altevian_aquila_exotic"),
	"phoron" = list("icon_state" = "altevian_aquila_phoron"),
	"hydrogen" = list("icon_state" = "altevian_aquila_hydrogen"),
))

/obj/item/clothing/accessory/altevian_badge/aquila/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/altevian_badge/aquila/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_altevian_badge_aquila[variant]
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
