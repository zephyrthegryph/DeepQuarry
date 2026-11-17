// Variants of /obj/item/clothing/accessory/poncho/roles/cloak: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_poncho_cloak, list(
	"antediluvian" = list("name" = "antediluvian cloak", "desc" = "A regal looking cloak of white with specks of gold woven into the fabric.", "icon_state" = "antediluvian_cloak", "item_state" = "antediluvian_cloak"),
	"atmos" = list("name" = "yellow cloak", "desc" = "A trimmed yellow and blue cloak.", "icon_state" = "atmoscloak", "item_state" = "atmoscloak"),
	"captain" = list("name" = "site manager's cloak", "desc" = "An elaborate cloak meant to be worn by the site manager.", "icon_state" = "capcloak", "item_state" = "capcloak"),
	"cargo" = list("name" = "brown cloak", "desc" = "A simple brown and black cloak.", "icon_state" = "cargocloak", "item_state" = "cargocloak"),
	"ce" = list("name" = "chief engineer's cloak", "desc" = "An elaborate cloak worn by the chief engineer.", "icon_state" = "cecloak", "item_state" = "cecloak"),
	"cmo" = list("name" = "chief medical officer's cloak", "desc" = "An elaborate cloak meant to be worn by the chief medical officer.", "icon_state" = "cmocloak", "item_state" = "cmocloak"),
	"engineer" = list("name" = "gold cloak", "desc" = "A simple gold and brown cloak.", "icon_state" = "engicloak", "item_state" = "engicloak"),
	"hos" = list("name" = "head of security's cloak", "desc" = "An elaborate cloak meant to be worn by the head of security.", "icon_state" = "hoscloak", "item_state" = "hoscloak"),
	"medical" = list("name" = "blue cloak", "desc" = "A simple blue and white cloak.", "icon_state" = "medcloak", "item_state" = "medcloak"),
	"mining" = list("name" = "trimmed purple cloak", "desc" = "A trimmed purple and brown cloak.", "icon_state" = "miningcloak", "item_state" = "miningcloak"),
	"neo_pcloak" = list("name" = "\improper Nanotrasen flowing cloak", "desc" = "A heavy cloak, decorated with red-and-golden embellishments.", "icon_state" = "neo_pcloak", "item_state" = "neo_pcloak"),
	"qm" = list("name" = "quartermaster's cloak", "desc" = "An elaborate cloak meant to be worn by the quartermaster.", "icon_state" = "qmcloak", "item_state" = "qmcloak"),
	"rd" = list("name" = "research director's cloak", "desc" = "An elaborate cloak meant to be worn by the research director.", "icon_state" = "rdcloak", "item_state" = "rdcloak"),
	"research" = list("name" = "purple cloak", "desc" = "A simple purple and white cloak.", "icon_state" = "scicloak", "item_state" = "scicloak"),
	"security" = list("name" = "red cloak", "desc" = "A simple red and black cloak.", "icon_state" = "seccloak", "item_state" = "seccloak"),
	"service" = list("name" = "green cloak", "desc" = "A simple green and blue cloak.", "icon_state" = "servicecloak", "item_state" = "servicecloak"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/accessory/poncho/roles/cloak/proc/variant_table()
	return GLOB.dq_variants_poncho_cloak
