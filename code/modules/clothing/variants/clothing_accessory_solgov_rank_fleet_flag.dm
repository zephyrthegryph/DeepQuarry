// Auto-generated. 4 variants of /obj/item/clothing/accessory/solgov/rank/fleet/flag.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_fleet_flag, list(
	"o8" = list("name" = "ranks (O-8 rear admiral)", "desc" = "Insignia denoting the rank of Rear Admiral."),
	"o9" = list("name" = "ranks (O-9 vice admiral)", "desc" = "Insignia denoting the rank of Vice Admiral."),
	"o10" = list("name" = "ranks (O-10 admiral)", "desc" = "Insignia denoting the rank of Admiral."),
	"o10_alt" = list("name" = "ranks (O-10 fleet admiral)", "desc" = "Insignia denoting the rank of Fleet Admiral."),
))

/obj/item/clothing/accessory/solgov/rank/fleet/flag/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/solgov/rank/fleet/flag/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_solgov_rank_fleet_flag[variant]
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
