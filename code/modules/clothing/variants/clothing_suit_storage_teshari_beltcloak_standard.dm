// Auto-generated. 25 variants of /obj/item/clothing/suit/storage/teshari/beltcloak/standard.

GLOBAL_LIST_INIT(dq_variants_suit_storage_teshari_beltcloak_standard, list(
	"black_orange" = list("name" = "black belted cloak (orange)", "icon_state" = "tesh_beltcloak_bo"),
	"black_grey" = list("name" = "black belted cloak", "icon_state" = "tesh_beltcloak_bg"),
	"black_midgrey" = list("name" = "black belted cloak (medium grey)", "icon_state" = "tesh_beltcloak_bmg"),
	"black_lightgrey" = list("name" = "black belted cloak (light grey)", "icon_state" = "tesh_beltcloak_blg"),
	"black_white" = list("name" = "black belted cloak (white)", "icon_state" = "tesh_beltcloak_bw"),
	"black_red" = list("name" = "black belted cloak (red)", "icon_state" = "tesh_beltcloak_br"),
	"black" = list("name" = "black simple belted cloak", "icon_state" = "tesh_beltcloak_bn"),
	"black_yellow" = list("name" = "black belted cloak (yellow)", "icon_state" = "tesh_beltcloak_by"),
	"black_green" = list("name" = "black belted cloak (green)", "icon_state" = "tesh_beltcloak_bgr"),
	"black_blue" = list("name" = "black belted cloak (blue)", "icon_state" = "tesh_beltcloak_bbl"),
	"black_purple" = list("name" = "black belted cloak (purple)", "icon_state" = "tesh_beltcloak_bp"),
	"black_pink" = list("name" = "black belted cloak (pink)", "icon_state" = "tesh_beltcloak_bpi"),
	"black_brown" = list("name" = "black belted cloak (brown)", "icon_state" = "tesh_beltcloak_bbr"),
	"orange_grey" = list("name" = "orange belted cloak", "icon_state" = "tesh_beltcloak_og"),
	"rainbow" = list("name" = "rainbow belted cloak", "icon_state" = "tesh_beltcloak_rainbow"),
	"lightgrey_grey" = list("name" = "light grey belted cloak", "icon_state" = "tesh_beltcloak_lgg"),
	"white_grey" = list("name" = "white belted cloak", "icon_state" = "tesh_beltcloak_wg"),
	"red_grey" = list("name" = "red belted cloak", "icon_state" = "tesh_beltcloak_rg"),
	"orange" = list("name" = "orange simple belted cloak", "icon_state" = "tesh_beltcloak_on"),
	"yellow_grey" = list("name" = "yellow belted cloak", "icon_state" = "tesh_beltcloak_yg"),
	"green_grey" = list("name" = "green belted cloak", "icon_state" = "tesh_beltcloak_gg"),
	"blue_grey" = list("name" = "blue belted cloak", "icon_state" = "tesh_beltcloak_blug"),
	"purple_grey" = list("name" = "purple belted cloak", "icon_state" = "tesh_beltcloak_pg"),
	"pink_grey" = list("name" = "pink belted cloak", "icon_state" = "tesh_beltcloak_pig"),
	"brown_grey" = list("name" = "brown belted cloak", "icon_state" = "tesh_beltcloak_brg"),
))

/obj/item/clothing/suit/storage/teshari/beltcloak/standard/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/suit/storage/teshari/beltcloak/standard/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_suit_storage_teshari_beltcloak_standard[variant]
	if(!v)
		return
	if(v["name"])
		name = v["name"]
	if(v["icon_state"])
		icon_state = v["icon_state"]
	if(v["desc"])
		desc = v["desc"]
	if(v["item_state"])
		item_state = v["item_state"]
