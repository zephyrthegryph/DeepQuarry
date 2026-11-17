// Variants of /obj/item/clothing/under/corp: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_under_corp, list(
	"aether" = list("name" = "\improper Aether jumpsuit", "desc" = "A jumpsuit belonging to Aether Atmospherics and Recycling, a Trans-Stellar that supplies recycling and atmospheric systems to colonies.", "icon_state" = "aether", "worn_state" = "aether"),
	"centauri" = list("name" = "\improper Centauri Provisions jumpsuit", "desc" = "A jumpsuit belonging to Centauri Provisions, a Trans-Stellar best known for its food and drink products.", "icon_state" = "centauri", "worn_state" = "centauri"),
	"confederacy" = list("name" = "\improper Confederacy uniform", "desc" = "A military uniform belonging to the Confederacy of Man, an independent human government.", "icon_state" = "confed", "worn_state" = "confed"),
	"focal" = list("name" = "\improper Focal Point jumpsuit", "desc" = "A jumpsuit belonging to Focal Point Energistics, an engineering megacorporation.", "icon_state" = "focal", "worn_state" = "focal"),
	"grayson" = list("name" = "\improper Grayson overalls", "desc" = "A set of overalls belonging to Grayson Manufactories, a mining Trans-Stellar.", "icon_state" = "grayson_mech", "worn_state" = "grayson_mech"),
	"grayson_jump" = list("name" = "\improper Grayson jumpsuit", "desc" = "A jumpsuit belonging to Grayson Manufactories, a mining Trans-Stellar.", "icon_state" = "grayson", "worn_state" = "grayson", "rolled_sleeves" = 0),
	"hephaestus" = list("name" = "\improper Hephaestus jumpsuit", "desc" = "A jumpsuit belonging to Hephaestus, a Trans-Stellar best known for high-grade arms manufacturing.", "icon_state" = "heph", "worn_state" = "heph", "rolled_sleeves" = 0),
	"kaleidoscope" = list("name" = "\improper Kaleidoscope uniform", "desc" = "A science uniform belonging to Kaleidoscope Cosmetics, a cosmetic and gene-modification trans-stellar.", "icon_state" = "kaleido", "worn_state" = "kaleido", "rolled_sleeves" = 0),
	"morpheus" = list("name" = "\improper Morpheus jumpsuit", "desc" = "A uniform belonging to Morpheus Cyberkinetics, a positronic-run cybernetics Trans-Stellar.", "icon_state" = "morpheus", "worn_state" = "morpheus"),
	"pcrc" = list("name" = "\improper PCRC uniform", "desc" = "A uniform belonging to Proxima Centauri Risk Control, a private security firm.", "icon_state" = "pcrc", "item_state" = "jensensuit", "worn_state" = "pcrc"),
	"saare" = list("name" = "\improper SAARE uniform", "desc" = "A dress uniform belonging to Stealth Assault Enterprises, a minor private military corporation.", "icon_state" = "saare", "worn_state" = "saare"),
	"veymed" = list("name" = "\improper Vey-Med uniform", "desc" = "A uniform belonging to Vey-Medical, a Skrellian biomedical Trans-Stellar.", "icon_state" = "veymed", "worn_state" = "veymed", "rolled_sleeves" = 0),
	"wardt" = list("name" = "\improper Ward-Takahashi jumpsuit", "desc" = "A jumpsuit belonging to Ward-Takahashi, a Trans-Stellar in the consumer goods market.", "icon_state" = "robotics2", "worn_state" = "robotics2"),
	"wulf" = list("name" = "\improper Wulf jumpsuit", "desc" = "A jumpsuit belonging to Wulf Aeronautics, a ship-building and propulsion systems Trans-Stellar.", "icon_state" = "wulf", "worn_state" = "wulf", "rolled_sleeves" = 0),
	"xion" = list("name" = "\improper Xion jumpsuit", "desc" = "A jumpsuit belonging to Xion Manufacturing, an industrial equipment Trans-Stellar.", "icon_state" = "xion", "worn_state" = "xion", "rolled_sleeves" = 0),
	"zenghu" = list("name" = "\improper Zeng-Hu jumpsuit", "desc" = "A jumpsuit belonging to Zeng-Hu Pharmaceuticals, a Trans-Stellar in the business of exactly what you'd expect..", "icon_state" = "zenghu", "worn_state" = "zenghu", "starting_accessories" = list(VARIANT(/obj/item/clothing/accessory/tie/red)), "rolled_sleeves" = 0),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/corp/proc/own_variant_table()
	return GLOB.dq_variants_under_corp

CAPABILITIES(/obj/item/clothing/under/corp)
	variants(nameof(variant), PROC_REF(own_variant_table)) // its own rows replace the parent family's
