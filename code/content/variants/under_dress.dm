// Variants of /obj/item/clothing/under/dress: one row per type that only set data (doc/rewrite/variant_census.md). The old path, parent + "/" + key, still resolves
// for maps and saves (variant_alias_of()). Started by tools/ci/variant_collapse.py.

GLOBAL_LIST_INIT(dq_variants_under_dress, list(
	"alpine" = list("name" = "alpine dress", "desc" = "A green and white dress that makes you want to yodel.", "icon_state" = "corsetdress"),
	"bluedress" = list("name" = "blue dress", "desc" = "A plain blue dress with a white belt.", "icon_state" = "bluedress"),
	"cbridesmaid" = list("name" = "fancy dress", "desc" = "A cute, flirty dress. Good for weddings and fancy parties, or if you just want to look fashionable. Perfect for recoloring!", "icon_state" = "cbridesmaid"),
	"cdress_fire" = list("name" = "flame dress", "desc" = "A small black dress with a flames print on it. Perfect for recoloring!", "icon_state" = "cflame_dress"),
	"countess" = list("name" = "countess dress", "desc" = "A red and black dress fit for a countess.", "icon_state" = "countess"),
	"cropdress" = list("name" = "crop dress", "desc" = "A red skirt and longsleeved button-up crop top.", "icon_state" = "cropdress"),
	"cswoopdress" = list("name" = "swoop dress", "desc" = "A fancy gown for those who like to show leg. Perfect for recoloring!", "icon_state" = "cswoopdress"),
	"darkred" = list("name" = "fancy dark red dress", "desc" = "A short, red dress with a black belt. Fancy.", "icon_state" = "darkreddress"),
	"dress_fire" = list("name" = "flame dress", "desc" = "A small black dress with blue flames print on it.", "icon_state" = "dress_fire"),
	"dress_green" = list("name" = "green dress", "desc" = "A simple, tight fitting green dress.", "icon_state" = "dress_green"),
	"dress_orange" = list("name" = "orange dress", "desc" = "A fancy orange gown for those who like to show leg.", "icon_state" = "dress_orange"),
	"dress_pink" = list("name" = "pink dress", "desc" = "A simple, tight fitting pink dress.", "icon_state" = "dress_pink"),
	"dress_saloon" = list("name" = "saloon girl dress", "desc" = "A old western inspired gown for the girl who likes to drink.", "icon_state" = "dress_saloon", "item_state_slots" = list(slot_r_hand_str = "dress_white", slot_l_hand_str = "dress_white")),
	"dress_yellow" = list("name" = "yellow dress", "desc" = "A flirty, little yellow dress.", "icon_state" = "dress_yellow"),
	"flamenco" = list("name" = "flamenco dress", "desc" = "A Mexican flamenco dress.", "icon_state" = "flamenco"),
	"goldwrap" = list("name" = "golden dress", "desc" = "A dress so ostentatious that you feel poorer just looking at it.", "icon_state" = "golddress"),
	"gothic2" = list("name" = "lacey gothic dress", "desc" = "An elegant gothic dress with lace decorations.", "icon_state" = "gothic2"),
	"hightrousers" = list("name" = "high-waisted trousers", "desc" = "A waistline this high is just made for ripping bodices, swashing buckles, or - just occasionally - sucking blood.", "icon_state" = "gayvampire"),
	"lilacdress" = list("name" = "lilac dress", "desc" = "A simple black dress adorned in fake purple lilacs.", "icon_state" = "lilacdress"),
	"pentagram" = list("name" = "pentagram dress", "desc" = "A black dress with straps over the chest in the shape of a pentagram.", "icon_state" = "pentagram"),
	"redeveninggown" = list("name" = "red evening gown", "desc" = "Fancy dress for space bar singers.", "icon_state" = "red_evening_gown"),
	"sailordress" = list("name" = "sailor dress", "desc" = "Formal wear for a leading lady.", "icon_state" = "sailor_dress"),
	"stripeddress" = list("name" = "striped dress", "desc" = "Fashion in space.", "icon_state" = "striped_dress"),
	"verglasdress" = list("name" = "verglas dress", "desc" = "The modern twist on a forgotten pattern, the Verglas style utilizes comfortable velvet and silver white satin to create an otherworldly effect evocative of winter, or the void.", "icon_state" = "verglas_dress"),
	"vneck" = list("name" = "v-neck dress", "desc" = "A black v-neck dress with an exaggerated neckline covered in a sheer mesh.", "icon_state" = "vneckdress"),
	"wench" = list("name" = "wench's dress", "desc" = "A white dress styled like a Ye Old Barmaid. Saucy!", "icon_state" = "wench"),
	"westernbustle" = list("name" = "western bustle", "desc" = "A western bustle dress from Earth's late 1800's.", "icon_state" = "westernbustle"),
	"white3" = list("name" = "short dress", "desc" = "A short, plain dress.", "icon_state" = "whitedress3", "addblends" = "whitedress3_a"),
	"yellowswoop" = list("name" = "yellow swooped dress", "desc" = "A yellow dress that swoops to the side.", "icon_state" = "yellowswoop"),
))

/// The variant rows (variants(), code/engine/lifeforms/variants.dm).
/obj/item/clothing/under/dress/proc/own_variant_table()
	return GLOB.dq_variants_under_dress
