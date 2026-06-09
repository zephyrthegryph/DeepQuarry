// Auto-generated. 8 variants of /obj/item/clothing/accessory/poncho/roles/cloak/crop_jacket.

GLOBAL_LIST_INIT(dq_variants_accessory_poncho_roles_cloak_crop_jacket, list(
	"blue" = list("name" = "blue crop jacket", "icon_state" = "cropjacket_blue", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. Let everyone know who's in control of the situation around here.", "item_state" = "cropjacket_blue"),
	"red" = list("name" = "red crop jacket", "icon_state" = "cropjacket_red", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. You could probably hide a holster under this without too much trouble.", "item_state" = "cropjacket_red"),
	"green" = list("name" = "green crop jacket", "icon_state" = "cropjacket_green", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. The faded green tones bring to mind the smell of antiseptics.", "item_state" = "cropjacket_green"),
	"purple" = list("name" = "purple crop jacket", "icon_state" = "cropjacket_purple", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. This doesn't seem like very practical labwear.", "item_state" = "cropjacket_purple"),
	"orange" = list("name" = "orange crop jacket", "icon_state" = "cropjacket_orange", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. Perfect for keeping cool whilst showing off your gains from shifting crates.", "item_state" = "cropjacket_orange"),
	"charcoal" = list("name" = "charcoal crop jacket", "icon_state" = "cropjacket_charcoal", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. Dark and slightly edgy, just like its wearer.", "item_state" = "cropjacket_charcoal"),
	"marine" = list("name" = "faded reflec crop jacket", "icon_state" = "cropjacket_marine", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. Seems to be made of a semi-reflective material, like an EMT's jacket.", "item_state" = "cropjacket_marine"),
	"drab" = list("name" = "drab crop jacket", "icon_state" = "cropjacket_drab", "desc" = "A cut down jacket that looks like it's light enough to wear on top of some other clothes. This one's a sort of olive-drab kind of colour.", "item_state" = "cropjacket_drab"),
))

/obj/item/clothing/accessory/poncho/roles/cloak/crop_jacket/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/poncho/roles/cloak/crop_jacket/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_poncho_roles_cloak_crop_jacket[variant]
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
