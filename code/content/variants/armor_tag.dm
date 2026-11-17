// Variants of /obj/item/clothing/accessory/armor/tag: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_armor_tag, list(
	"abneg" = list("name" = "\improper AB- blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as AB NEGATIVE.", "icon_state" = "abnegtag"),
	"abpos" = list("name" = "\improper AB+ blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as AB POSITIVE.", "icon_state" = "abpostag"),
	"aneg" = list("name" = "\improper A- blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as A NEGATIVE.", "icon_state" = "anegtag"),
	"apos" = list("name" = "\improper A+ blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as A POSITIVE.", "icon_state" = "apostag"),
	"bneg" = list("name" = "\improper B- blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as B NEGATIVE.", "icon_state" = "bnegtag"),
	"bpos" = list("name" = "\improper B+ blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as B POSITIVE.", "icon_state" = "bpostag"),
	"com" = list("name" = "\improper SCG tag", "desc" = "An armor tag with the words SOLAR CONFEDERATE GOVERNMENT printed in gold lettering on it.", "icon_state" = "comtag"),
	"hedberg" = list("name" = "\improper HEDBERG-HAMMARSTROM tag", "desc" = "An armor tag with the name HEDBERG-HAMMARSTROM printed in olive-green lettering on it.", "icon_state" = "saaretag"),
	"nt" = list("name" = "\improper NANOTRASEN tag", "desc" = "An armor tag with the word NANOTRASEN printed in red lettering on it and an accompanying company logo.", "icon_state" = "nanotag"),
	"ntwhite" = list("name" = "White NANOTRASEN tag", "desc" = "An armor tag with the word NANOTRASEN printed in red-and-white lettering on it and an accompanying company logo.", "icon_state" = "nanotag_white"),
	"oneg" = list("name" = "\improper O- blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as O NEGATIVE.", "icon_state" = "onegtag"),
	"opos" = list("name" = "\improper O+ blood patch", "desc" = "An embroidered patch indicating the wearer's blood type as O POSITIVE.", "icon_state" = "opostag"),
	"pcrc" = list("name" = "\improper PCRC tag", "desc" = "An armor tag with the words PROXIMA CENTAURI RISK CONTROL printed in cyan lettering on it.", "icon_state" = "pcrctag"),
	"sec" = list("name" = "\improper POLICE tag", "desc" = "An armor tag with the word POLICE printed in silver lettering on it.", "icon_state" = "sectag"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/armor/tag/proc/variant_table()
	return GLOB.dq_variants_armor_tag

CAPABILITIES(/obj/item/clothing/accessory/armor/tag)
	variants(nameof(variant), PROC_REF(variant_table))
