// Variants of /obj/item/clothing/suit/storage/toggle/labcoat: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_labcoat, list(
	"blue" = list("name" = "blue labcoat", "desc" = "A suit that protects against minor chemical spills. This one is blue.", "icon_state" = "blue_labcoat", "item_state_slots" = list(slot_r_hand_str = "blue_labcoat", slot_l_hand_str = "blue_labcoat")),
	"blue_edge" = list("name" = "blue-edged labcoat", "desc" = "A suit that protects against minor chemical spills. This one has blue trim.", "icon_state" = "blue_edge_labcoat"),
	"chemist" = list("name" = JOB_CHEMIST + " labcoat", "desc" = "A suit that protects against minor chemical spills. Has an orange stripe on the shoulder.", "icon_state" = "labcoat_chem", "item_state_slots" = list(slot_r_hand_str = "chemist_labcoat", slot_l_hand_str = "chemist_labcoat")),
	"cmo" = list("name" = "chief medical officer's labcoat", "desc" = "Bluer than the standard model.", "icon_state" = "labcoat_cmo", "item_state_slots" = list(slot_r_hand_str = "cmo_labcoat", slot_l_hand_str = "cmo_labcoat")),
	"cmoalt" = list("name" = "chief medical officer's labcoat", "desc" = "A labcoat with command blue highlights.", "icon_state" = "labcoat_cmoalt", "item_state_slots" = list(slot_r_hand_str = "cmo_labcoat", slot_l_hand_str = "cmo_labcoat")),
	"emt" = list("name" = "EMT's labcoat", "desc" = "A dark blue labcoat with reflective strips for emergency medical technicians.", "icon_state" = "labcoat_emt", "item_state_slots" = list(slot_r_hand_str = "emt_labcoat", slot_l_hand_str = "emt_labcoat")),
	"genetics" = list("name" = JOB_GENETICIST + " labcoat", "desc" = "A suit that protects against minor chemical spills. Has a blue stripe on the shoulder.", "icon_state" = "labcoat_gen", "item_state_slots" = list(slot_r_hand_str = "genetics_labcoat", slot_l_hand_str = "genetics_labcoat")),
	"green" = list("name" = "green labcoat", "desc" = "A suit that protects against minor chemical spills. This one is green.", "icon_state" = "green_labcoat", "item_state_slots" = list(slot_r_hand_str = "green_labcoat", slot_l_hand_str = "green_labcoat")),
	"mad" = list("name" = "The Mad's labcoat", "desc" = "It makes you look capable of konking someone on the noggin and shooting them into space.", "icon_state" = "green_labcoat", "item_state_slots" = list(slot_r_hand_str = "green_labcoat", slot_l_hand_str = "green_labcoat")),
	"neo_blueemt" = list("name" = "dark blue EMT jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_blueemt", "item_state_slots" = list(slot_r_hand_str = "emt_labcoat", slot_l_hand_str = "emt_labcoat")),
	"neo_bluemed" = list("name" = "paramedic's jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_bluemed"),
	"neo_bodyguard_dep" = list("name" = "bodyguard's jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_bodyguard_dep"),
	"neo_cargo_dep" = list("name" = "cargo department jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_cargo_dep"),
	"neo_civ_dep" = list("name" = "off-duty department jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_civ_dep"),
	"neo_emt" = list("name" = "EMT jacket", "desc" = "A dark blue labcoat with reflective strips for emergency medical technicians.", "icon_state" = "neo_emt", "item_state_slots" = list(slot_r_hand_str = "emt_labcoat", slot_l_hand_str = "emt_labcoat")),
	"neo_engi_dep" = list("name" = "engineer's department jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_engi_dep"),
	"neo_highvis" = list("name" = "high visibility jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_coat_highvis", "item_state_slots" = list(slot_r_hand_str = "emt_labcoat", slot_l_hand_str = "emt_labcoat")),
	"neo_hopformal" = list("name" = "hop's formal jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_hopformal"),
	"neo_hos_parade" = list("name" = "head of security's parade jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_hos_parade"),
	"neo_hosformal_blue" = list("name" = "head of security's blue formal jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_hosformal_blue"),
	"neo_labcoat" = list("name" = "long labcoat", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_labcoat"),
	"neo_leather" = list("name" = "leather hoodie", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_leather"),
	"neo_med_dep" = list("name" = "medical department jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_med_dep"),
	"neo_police" = list("name" = "traffic officer's jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_police"),
	"neo_ranger" = list("name" = "ranger's cloak", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_leather"),
	"neo_redemt" = list("name" = "red EMT jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_redemt", "item_state_slots" = list(slot_r_hand_str = "emt_labcoat", slot_l_hand_str = "emt_labcoat")),
	"neo_robo_coat" = list("name" = "robotics labcoat", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_robo_coat"),
	"neo_sci_dep" = list("name" = "science department jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_sci_dep"),
	"neo_sec_blue_dep" = list("name" = "blue security department jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_sec_blue_dep"),
	"neo_sec_red_dep" = list("name" = "red security department jacket", "desc" = "it bears a tag that says 'Product of Total Gear & Co.'", "icon_state" = "neo_sec_red_dep"),
	"orange" = list("name" = "orange labcoat", "desc" = "A suit that protects against minor chemical spills. This one is orange.", "icon_state" = "orange_labcoat", "item_state_slots" = list(slot_r_hand_str = "orange_labcoat", slot_l_hand_str = "orange_labcoat")),
	"pink" = list("name" = "pink labcoat", "desc" = "A suit that protects against minor chemical spills. This one is pink.", "icon_state" = "pink_labcoat", "item_state_slots" = list(slot_r_hand_str = "pink_labcoat", slot_l_hand_str = "pink_labcoat")),
	"plaguedoctor" = list("name" = "golden plague doctor suit", "desc" = "If it worked then, it works now. This classic design comes in gold.", "icon_state" = "plaguedoctor2"),
	"purple" = list("name" = "purple labcoat", "desc" = "A suit that protects against minor chemical spills. This one is purple.", "icon_state" = "purple_labcoat", "item_state_slots" = list(slot_r_hand_str = "purple_labcoat", slot_l_hand_str = "purple_labcoat")),
	"rd" = list("name" = "research director's labcoat", "desc" = "A flashy labcoat with purple markings. It belongs to the " + JOB_RESEARCH_DIRECTOR + ".", "icon_state" = "labcoat_rd", "item_state_slots" = list(slot_r_hand_str = "science_labcoat", slot_l_hand_str = "science_labcoat")),
	"red" = list("name" = "red labcoat", "desc" = "A suit that protects against minor chemical spills. This one is red.", "icon_state" = "red_labcoat", "item_state_slots" = list(slot_r_hand_str = "red_labcoat", slot_l_hand_str = "red_labcoat")),
	"roboticist" = list("name" = JOB_ROBOTICIST + " labcoat", "desc" = "More like an eccentric coat than a labcoat. Helps pass off bloodstains as part of the aesthetic. Comes with red shoulder pads.", "icon_state" = "labcoat_robo", "item_state_slots" = list(slot_r_hand_str = "labcoat", slot_l_hand_str = "labcoat")),
	"science" = list("name" = JOB_SCIENTIST + " labcoat", "desc" = "A suit that protects against minor chemical spills. Has a purple stripe on the shoulder.", "icon_state" = "labcoat_tox", "item_state_slots" = list(slot_r_hand_str = "science_labcoat", slot_l_hand_str = "science_labcoat")),
	"yellow" = list("name" = "yellow labcoat", "desc" = "A suit that protects against minor chemical spills. This one is yellow.", "icon_state" = "yellow_labcoat", "item_state_slots" = list(slot_r_hand_str = "yellow_labcoat", slot_l_hand_str = "yellow_labcoat")),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/suit/storage/toggle/labcoat/proc/variant_table()
	return GLOB.dq_variants_labcoat
