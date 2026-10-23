// Auto-generated. 4 variants of /obj/item/clothing/under/explorer/utility.

GLOBAL_LIST_INIT(dq_variants_under_explorer_utility, list(
	"supply" = list("name" = "\improper explorer supply uniform", "icon_state" = "blackutility_sup", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and brown blazes."),
	"medical" = list("name" = "\improper explorer medical uniform", "icon_state" = "blackutility_med", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and blue blazes."),
	"security" = list("name" = "\improper explorer security uniform", "icon_state" = "blackutility_sec", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and red blazes."),
	"engineering" = list("name" = "\improper explorer engineering uniform", "icon_state" = "blackutility_eng", "desc" = "The utility uniform of the Explorer's association, made from biohazard resistant material. This one has silver trim and organge blazes."),
))

CAPABILITIES(/obj/item/clothing/under/explorer/utility)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/explorer/utility/proc/variant_table()
	return GLOB.dq_variants_under_explorer_utility
