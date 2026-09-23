// Auto-generated. 4 variants of /obj/item/clothing/accessory/solgov/rank/marine/flag.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_marine_flag, list(
	"o8" = list("name" = "ranks (O-8 major general)", "desc" = "Insignia denoting the rank of Major General."),
	"o9" = list("name" = "ranks (O-9 lieutenant general)", "desc" = "Insignia denoting the rank of lieutenant general."),
	"o10" = list("name" = "ranks (O-10 general)", "desc" = "Insignia denoting the rank of General."),
	"o10_alt" = list("name" = "ranks (O-10 field marshal)", "desc" = "Insignia denoting the rank of Field Marshal."),
))

/obj/item/clothing/accessory/solgov/rank/marine/flag/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/solgov/rank/marine/flag/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_solgov_rank_marine_flag[variant]
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
