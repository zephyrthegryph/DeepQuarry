// Auto-generated. 5 variants of /obj/item/clothing/suit/captunic/capjacket/altevian_admiral.

GLOBAL_LIST_INIT(dq_variants_suit_captunic_capjacket_altevian_admiral, list(
	"gray" = list("name" = "gray altevian officer's suit", "icon_state" = "altevian-admiral-gray"),
	"white" = list("name" = "white altevian officer's suit", "icon_state" = "altevian-admiral-white"),
	"dark" = list("name" = "dark altevian officer's suit", "icon_state" = "altevian-admiral-dark"),
	"olive" = list("name" = "olive altevian officer's suit", "icon_state" = "altevian-admiral-olive"),
	"yellow" = list("name" = "yellow altevian officer's suit", "icon_state" = "altevian-admiral-yellow"),
))

CAPABILITIES(/obj/item/clothing/suit/captunic/capjacket/altevian_admiral)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/suit/captunic/capjacket/altevian_admiral/proc/variant_table()
	return GLOB.dq_variants_suit_captunic_capjacket_altevian_admiral
