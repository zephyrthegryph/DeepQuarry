// Auto-generated. 11 variants of /obj/item/clothing/accessory/solgov/rank/marine/enlisted.

GLOBAL_LIST_INIT(dq_variants_accessory_solgov_rank_marine_enlisted, list(
	"e2" = list("name" = "ranks (E-2 private second class)", "desc" = "Insignia denoting the rank of Private Second Class."),
	"e3" = list("name" = "ranks (E-3 private first class)", "desc" = "Insignia denoting the rank of Private First Class."),
	"e4" = list("name" = "ranks (E-4 corporal)", "desc" = "Insignia denoting the rank of Corporal."),
	"e5" = list("name" = "ranks (E-5 sergeant)", "desc" = "Insignia denoting the rank of Sergeant."),
	"e6" = list("name" = "ranks (E-6 staff sergeant)", "desc" = "Insignia denoting the rank of Staff Sergeant."),
	"e7" = list("name" = "ranks (E-7 sergeant first class)", "desc" = "Insignia denoting the rank of Sergeant First Class."),
	"e8" = list("name" = "ranks (E-8 master sergeant)", "desc" = "Insignia denoting the rank of Master Sergeant."),
	"e8_alt" = list("name" = "ranks (E-8 first sergeant)", "desc" = "Insignia denoting the rank of First Sergeant."),
	"e9" = list("name" = "ranks (E-9 sergeant major)", "desc" = "Insignia denoting the rank of Sergeant Major."),
	"e9_alt1" = list("name" = "ranks (E-9 command sergeant major)", "desc" = "Insignia denoting the rank of Command Sergeant Major."),
	"e9_alt2" = list("name" = "ranks (E-9 sergeant major of the marine)", "desc" = "Insignia denoting the rank of Sergeant Major of the marine."),
))

/obj/item/clothing/accessory/solgov/rank/marine/enlisted/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/solgov/rank/marine/enlisted/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_solgov_rank_marine_enlisted[variant]
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
