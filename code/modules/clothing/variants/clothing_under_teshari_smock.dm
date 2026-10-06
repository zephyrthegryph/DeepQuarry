// Auto-generated. 12 variants of /obj/item/clothing/under/teshari/smock.

GLOBAL_LIST_INIT(dq_variants_under_teshari_smock, list(
	"white" = list("name" = "small white smock", "icon_state" = "seromi_white"),
	"red" = list("name" = "small Security smock", "icon_state" = "seromi_red"),
	"yellow" = list("name" = "small Engineering smock", "icon_state" = "seromi_yellow"),
	"medical" = list("name" = "small Medical uniform", "icon_state" = "seromi_medical"),
	"science" = list("name" = "small Research uniform", "icon_state" = "teshari_science"),
	"rainbow" = list("name" = "small rainbow smock", "icon_state" = "seromi_rainbow"),
	"uniform" = list("name" = "small command uniform", "icon_state" = "seromi_captain"),
	"formal" = list("name" = "small formal uniform", "icon_state" = "seromi_captain_formal"),
	"blackutilitysmock" = list("name" = "black utility smock", "icon_state" = "teshari_blackutility_com"),
	"greydress" = list("name" = "small grey dress", "icon_state" = "teshari_greydress"),
	"blackutility" = list("name" = "Teshari utility uniform", "icon_state" = "teshari_blackutility"),
	"bluegreydress" = list("name" = "small blue and grey dress", "icon_state" = "teshari_bluegreydress"),
))

CAPABILITIES(/obj/item/clothing/under/teshari/smock)
	variants(nameof(variant), PROC_REF(variant_table))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/teshari/smock/proc/variant_table()
	return GLOB.dq_variants_under_teshari_smock
