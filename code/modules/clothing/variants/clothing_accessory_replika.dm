// Auto-generated. 4 variants of /obj/item/clothing/accessory/replika.

GLOBAL_LIST_INIT(dq_variants_accessory_replika, list(
	"klbr" = list("name" = "controller replikant chestplate", "icon_state" = "klbr", "desc" = "A sloped titanium-composite chest plate fitted for use by 2nd generation biosynthetics. The right shoulder has been painted an imposing shade of red."),
	"lstr" = list("name" = "combat-engineer replikant chestplate", "icon_state" = "lstr", "desc" = "A sloped titanium-composite chest plate fitted for use by 2nd generation biosynthetics. This plain-white version is a staple of biosynths assinged to combat-engineering duties."),
	"stcr" = list("name" = "security-controller replikant chestplate", "icon_state" = "stcr", "desc" = "A sloped titanium-composite chest plate fitted for use by 2nd generation biosynthetics. This version sports multiple red adjustable straps and a lack of shoulder pads."),
	"star" = list("name" = "security-technician replikant chestplate", "icon_state" = "star", "desc" = "A sloped titanium-composite chest plate with a matte black finish, fitted for use by 2nd generation biosynthetics. Comes with red adjustable straps."),
))

CAPABILITIES(/obj/item/clothing/accessory/replika)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/replika/proc/variant_table()
	return GLOB.dq_variants_accessory_replika
