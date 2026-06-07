// Auto-generated. 4 variants of /obj/item/clothing/under/explorer/utility.

GLOBAL_LIST_INIT(dq_variants_under_explorer_utility, list(
	"supply" = list("name" = "\improper explorer supply uniform", "icon_state" = "blackutility_sup", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and brown blazes."),
	"medical" = list("name" = "\improper explorer medical uniform", "icon_state" = "blackutility_med", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and blue blazes."),
	"security" = list("name" = "\improper explorer security uniform", "icon_state" = "blackutility_sec", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and red blazes."),
	"engineering" = list("name" = "\improper explorer engineering uniform", "icon_state" = "blackutility_eng", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and organge blazes."),
))

/obj/item/clothing/under/explorer/utility/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/under/explorer/utility/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_under_explorer_utility[variant]
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
