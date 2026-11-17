// Variants of /obj/item/clothing/head: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_head, list(
	"buckethat" = list("name" = "bucket hat", "desc" = "Turns out these are actually called 'gatsby caps' but telling people you wear a bucket is slightly more interesting, so that's what it's called.", "icon_state" = "buckethat"),
	"chefhat" = list("name" = "chef's hat", "desc" = "It's a hat used by chefs to keep hair out of your food. Judging by the food in the mess, they don't work.", "icon_state" = "chefhat"),
	"eulrhat" = list("name" = "sleek side cap", "desc" = "A simple wedge cap with red accents, popular with biosynthetic personnel.", "icon_state" = "eulrhat"),
	"fancy_crown" = list("name" = "fancy crown", "desc" = "How extraordinarily regal!", "icon_state" = "fancycrown"),
	"fez" = list("name" = "fez", "icon_state" = "fez", "desc" = "You should wear a fez. Fezzes are cool."),
	"hairnet" = list("name" = "hairnet", "desc" = "A hairnet used to keep the hair out of the way and out of the food.", "icon_state" = "hairnet", "sprite_sheets" = list( SPECIES_TAJARAN = 'icons/inventory/head/mob_tajaran.dmi' )),
	"mailman2" = list("name" = "mailman hat", "desc" = "A hat used by the mailman to show who's the delivery person here.", "icon_state" = "mailman2"),
	"neo_irs" = list("name" = "IRS cap", "desc" = "a blue cap with the letters 'IRS' emblazoned on the front.", "icon" = 'icons/inventory/head/item.dmi', "icon_state" = "neo_irs"),
	"nonla" = list("name" = "non la", "desc" = "A conical hat typically woven from leaves, good for keeping the sun AND rain off your head, in case it happens to be sunny while raining.", "icon_state" = "nonla"),
	"papakha" = list("name" = "Papakha", "desc" = "an old beat-up Papakha.", "icon" = 'icons/inventory/head/item.dmi', "icon_state" = "neo_papakha"),
	"papakha_white" = list("name" = "White Papakha", "desc" = "an old beat-up white papakha.", "icon" = 'icons/inventory/head/item.dmi', "icon_state" = "neo_papakha_white"),
	"pizzaguy" = list("name" = "pizza delivery visor", "desc" = "A fancy visor showing alignment to pizza delivery service. Extremely risky career choice.", "icon_state" = "pizzadelivery", "item_state" = "pizzadelivery"),
	"powdered_wig" = list("name" = "powdered wig", "desc" = "A powdered wig.", "icon_state" = "pwig"),
	"tinytophat" = list("name" = "tiny tophat", "desc" = "A tophat that is far too small to properly sit on someone's head!", "icon_state" = "tiny_tophat"),
	"wedding" = list("name" = "wedding veil", "desc" = "A lace veil worn over the face, typically by a bride during their wedding.", "icon_state" = "weddingveil"),
	"wheat" = list("name" = "straw hat", "desc" = "It's a hat made from synthetic straw. Brought to you by \"Country Girls LLC.\" the choice brand for the galaxy's working class.", "icon_state" = "wheat"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/head/proc/variant_table()
	return GLOB.dq_variants_head
