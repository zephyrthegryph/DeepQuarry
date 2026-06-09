// Auto-generated. 5 variants of /obj/item/clothing/suit/captunic/capjacket/altevian_admiral.

GLOBAL_LIST_INIT(dq_variants_suit_captunic_capjacket_altevian_admiral, list(
	"gray" = list("name" = "gray altevian officer's suit", "icon_state" = "altevian-admiral-gray"),
	"white" = list("name" = "white altevian officer's suit", "icon_state" = "altevian-admiral-white"),
	"dark" = list("name" = "dark altevian officer's suit", "icon_state" = "altevian-admiral-dark"),
	"olive" = list("name" = "olive altevian officer's suit", "icon_state" = "altevian-admiral-olive"),
	"yellow" = list("name" = "yellow altevian officer's suit", "icon_state" = "altevian-admiral-yellow"),
))

/obj/item/clothing/suit/captunic/capjacket/altevian_admiral/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/suit/captunic/capjacket/altevian_admiral/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_suit_captunic_capjacket_altevian_admiral[variant]
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
