// Auto-generated. 4 variants of /obj/item/clothing/under/cohesion.

GLOBAL_LIST_INIT(dq_variants_under_cohesion, list(
	"striped" = list("name" = "red striped cohesion suit", "icon_state" = "cohesionsuit_striped", "desc" = "A black cohesion suit with red stripes intended to assist Prometheans in maintaining their form and prevent direct skin exposure."),
	"decal" = list("name" = "purple decaled cohesion suit", "icon_state" = "cohesionsuit_decal", "desc" = "A white cohesion suit with purple decals intended to assist Prometheans in maintaining their form and prevent direct skin exposure."),
	"pattern" = list("name" = "blue patterned cohesion suit", "icon_state" = "cohesionsuit_pattern", "desc" = "A white cohesion suit with blue patterns intended to assist Prometheans in maintaining their form and prevent direct skin exposure."),
	"hazard" = list("name" = "hazard cohesion suit", "icon_state" = "cohesionsuit_hazard", "desc" = "An orange cohesion suit with yellow hazard stripes intended to assist Prometheans in maintaining their form and prevent direct skin exposure."),
))

CAPABILITIES(/obj/item/clothing/under/cohesion)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/cohesion/proc/variant_table()
	return GLOB.dq_variants_under_cohesion
