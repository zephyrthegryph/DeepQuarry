// Auto-generated. 4 variants of /obj/item/clothing/accessory/solgov/rank/ec/officer.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_ec_officer, list(
	"o3" = list("name" = "ranks (O-3 lieutenant)", "icon_state" = "ecrank_o3", "desc" = "Insignia denoting the rank of Lieutenant."),
	"o5" = list("name" = "ranks (O-5 commander)", "icon_state" = "ecrank_o5", "desc" = "Insignia denoting the rank of Commander."),
	"o6" = list("name" = "ranks (O-6 captain)", "icon_state" = "ecrank_o6", "desc" = "Insignia denoting the rank of Captain."),
	"o8" = list("name" = "ranks (O-8 admiral)", "icon_state" = "ecrank_o8", "desc" = "Insignia denoting the rank of Admiral."),
))

/obj/item/clothing/accessory/solgov/rank/ec/officer/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/solgov/rank/ec/officer/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_solgov_rank_ec_officer[variant]
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
