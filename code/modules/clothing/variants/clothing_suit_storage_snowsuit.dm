// Auto-generated. 6 variants of /obj/item/clothing/suit/storage/snowsuit.

GLOBAL_LIST_INIT(dq_variants_suit_storage_snowsuit, list(
	"command" = list("name" = "command snowsuit", "icon_state" = "snowsuit_command"),
	"security" = list("name" = "security snowsuit", "icon_state" = "snowsuit_security"),
	"medical" = list("name" = "medical snowsuit", "icon_state" = "snowsuit_medical"),
	"engineering" = list("name" = "engineering snowsuit", "icon_state" = "snowsuit_engineering"),
	"cargo" = list("name" = "cargo snowsuit", "icon_state" = "snowsuit_cargo"),
	"science" = list("name" = "science snowsuit", "icon_state" = "snowsuit_science"),
))

CAPABILITIES(/obj/item/clothing/suit/storage/snowsuit)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_GENERIC, POCKET_EMERGENCY), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(covers = CHEST|ARMS, hides = HIDEHOLSTER))
	configure(item_protection(cold_parts = CHEST|ARMS, min_cold = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE))
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/suit/storage/snowsuit/proc/variant_table()
	return GLOB.dq_variants_suit_storage_snowsuit
