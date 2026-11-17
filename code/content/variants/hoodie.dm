// Variants of /obj/item/clothing/suit/storage/toggle/hoodie: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_hoodie, list(
	"black" = list("name" = "black hoodie", "desc" = "A warm, black sweatshirt.", "icon_state" = "black_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_black", slot_l_hand_str = "suit_black")),
	"blue" = list("name" = "blue hoodie", "desc" = "A warm, blue sweatshirt.", "icon_state" = "blue_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_blue", slot_l_hand_str = "suit_blue")),
	"cti" = list("name" = "CTI hoodie", "desc" = "A warm, black sweatshirt.  It bears the letters CTI on the back, a lettering to the prestigious university in Tau Ceti, Ceti Technical Institute.  There is a blue supernova embroidered on the front, the emblem of CTI.", "icon_state" = "cti_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_black", slot_l_hand_str = "suit_black")),
	"green" = list("name" = "green hoodie", "desc" = "A warm, green sweatshirt.", "icon_state" = "green_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_olive", slot_l_hand_str = "suit_olive")),
	"mu" = list("name" = "mojave university hoodie", "desc" = "A warm, gray sweatshirt.  It bears the letters MU on the front, a lettering to the well-known public college, Mojave University.", "icon_state" = "mu_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_grey", slot_l_hand_str = "suit_grey")),
	"nrti" = list("name" = "New Reykjavik Technical Institute hoodie", "desc" = "A warm, gray sweatshirt. It bears the letters NRT on the back, in reference to Sif's premiere technical institute.", "icon_state" = "nrti_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_grey", slot_l_hand_str = "suit_grey")),
	"nt" = list("name" = "NT hoodie", "desc" = "A warm, blue sweatshirt.  It proudly bears the silver NanoTrasen insignia lettering on the back.  The edges are trimmed with silver.", "icon_state" = "nt_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_blue", slot_l_hand_str = "suit_blue")),
	"orange" = list("name" = "orange hoodie", "desc" = "A warm, orange sweatshirt.", "icon_state" = "orange_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_orange", slot_l_hand_str = "suit_orange")),
	"red" = list("name" = "red hoodie", "desc" = "A warm, red sweatshirt.", "icon_state" = "red_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_red", slot_l_hand_str = "suit_red")),
	"smw" = list("name" = "Space Mountain Wind hoodie", "desc" = "A warm, black sweatshirt.  It has the logo for the popular softdrink Space Mountain Wind on both the front and the back.", "icon_state" = "smw_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_black", slot_l_hand_str = "suit_black")),
	"talon" = list("name" = "Talon hoodie", "desc" = "A warm, blue sweatshirt bearing ITV Talon markings.", "icon_state" = "talonhoodie", "item_state_slots" = list(slot_r_hand_str = "suit_blue", slot_l_hand_str = "suit_blue")),
	"yellow" = list("name" = "yellow hoodie", "desc" = "A warm, yellow sweatshirt.", "icon_state" = "yellow_hoodie", "item_state_slots" = list(slot_r_hand_str = "suit_yellow", slot_l_hand_str = "suit_yellow")),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/suit/storage/toggle/hoodie/proc/variant_table()
	return GLOB.dq_variants_hoodie
