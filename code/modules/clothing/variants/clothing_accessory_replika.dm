// Auto-generated. 4 variants of /obj/item/clothing/accessory/replika.

GLOBAL_LIST_INIT(dq_variants_accessory_replika, list(
	"klbr" = list("name" = "controller replikant chestplate", "icon_state" = "klbr", "desc" = "A sloped titanium-composite chest plate fitted for use by 2nd generation biosynthetics. The right shoulder has been painted an imposing shade of red."),
	"lstr" = list("name" = "combat-engineer replikant chestplate", "icon_state" = "lstr", "desc" = "A sloped titanium-composite chest plate fitted for use by 2nd generation biosynthetics. This plain-white version is a staple of biosynths assinged to combat-engineering duties."),
	"stcr" = list("name" = "security-controller replikant chestplate", "icon_state" = "stcr", "desc" = "A sloped titanium-composite chest plate fitted for use by 2nd generation biosynthetics. This version sports multiple red adjustable straps and a lack of shoulder pads."),
	"star" = list("name" = "security-technician replikant chestplate", "icon_state" = "star", "desc" = "A sloped titanium-composite chest plate with a matte black finish, fitted for use by 2nd generation biosynthetics. Comes with red adjustable straps."),
))

/obj/item/clothing/accessory/replika/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/accessory/replika/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_accessory_replika[variant]
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
