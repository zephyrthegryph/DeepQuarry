// Auto-generated. 7 variants of /obj/item/clothing/accessory/poncho/roles/cloak/mantle.

GLOBAL_LIST_INIT(dq_variants_accessory_poncho_roles_cloak_mantle, list(
	"cargo" = list("name" = "cargo mantle", "icon_state" = "qmmantle", "desc" = "A shoulder mantle bearing the colors of the Supply department, with a gold lapel emblazoned upon the front.", "item_state" = "qmmantle"),
	"security" = list("name" = "security mantle", "icon_state" = "hosmantle", "desc" = "A shoulder mantle bearing the colors of the Security department, featuring rugged molding around the collar.", "item_state" = "hosmantle"),
	"engineering" = list("name" = "engineering mantle", "icon_state" = "cemantle", "desc" = "A shoulder mantle bearing the colors of the Engineering department, accenting the pristine white fabric.", "item_state" = "cemantle"),
	"research" = list("name" = "research mantle", "icon_state" = "rdmantle", "desc" = "A shoulder mantle bearing the colors of the Research department, the material slick and hydrophobic.", "item_state" = "rdmantle"),
	"medical" = list("name" = "medical mantle", "icon_state" = "cmomantle", "desc" = "A shoulder mantle bearing the general colors of the Medical department, dyed a sterile nitrile cyan.", "item_state" = "cmomantle"),
	"hop" = list("name" = "head of personnel mantle", "icon_state" = "hopmantle", "desc" = "A shoulder mantle bearing the colors of the " + JOB_HEAD_OF_PERSONNEL + "'s uniform, featuring the typical royal blue contrasted by authoritative red.", "item_state" = "hopmantle"),
	"cap" = list("name" = "site manager mantle", "icon_state" = "capmantle", "desc" = "A shoulder mantle bearing the colors usually found on a " + JOB_SITE_MANAGER + ", a commanding blue with regal gold inlay.", "item_state" = "capmantle"),
))

CAPABILITIES(/obj/item/clothing/accessory/poncho/roles/cloak/mantle)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/poncho/roles/cloak/mantle/proc/variant_table()
	return GLOB.dq_variants_accessory_poncho_roles_cloak_mantle
