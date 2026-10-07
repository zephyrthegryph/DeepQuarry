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

CAPABILITIES(/obj/item/clothing/accessory/gaiter)
	variants(nameof(variant), PROC_REF(variant_table))
	op("gaiter_tuck_mask_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Gaiter tuck mask item"), then(PROC_REF(gaiter_tuck_mask_item)))
	op("gaiter_remove_mask_alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Gaiter remove mask alt"), then(PROC_REF(gaiter_remove_mask_alt)))
	op("gaiter_adjust_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Adjust"), then(PROC_REF(gaiter_adjust_self)))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/gaiter/proc/variant_table()
	return GLOB.dq_variants_accessory_gaiter
