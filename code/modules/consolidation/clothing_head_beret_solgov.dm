// Auto-generated. 13 variants of /obj/item/clothing/head/beret/solgov.

GLOBAL_LIST_INIT(dq_variants_head_beret_solgov, list(
	"homeguard" = list("name" = "home guard beret", "desc" = "A red beret denoting service in the Sol Home Guard. For personnel that are more inclined towards style than safety."),
	"gateway" = list("name" = "gateway administration beret", "desc" = "An orange beret denoting service in the Gateway Administration. For personnel that are more inclined towards style than safety."),
	"customs" = list("name" = "customs and trade beret", "desc" = "A purple beret denoting service in the Customs and Trade Bureau. For personnel that are more inclined towards style than safety."),
	"orbital" = list("name" = "orbital assault beret", "desc" = "A blue beret denoting orbital assault training. For helljumpers that are more inclined towards style than safety."),
	"research" = list("name" = "government research beret", "desc" = "A green beret denoting service in the Bureau of Research. For explorers that are more inclined towards style than safety."),
	"health" = list("name" = "health service beret", "icon_state" = "beret_white", "desc" = "A white beret denoting service in the Interstellar Health Service. For medics that are more inclined towards style than safety."),
	"marcom" = list("name" = "\improper MARSCOM beret", "desc" = "A red beret with a gold insignia, denoting service in the USDFDF Mars Central Command. For brass who are more inclined towards style than safety."),
	"stratcom" = list("name" = "\improper STRATCOM beret", "desc" = "A grey beret with a silver insignia, denoting service in the USDFDF Strategic Command. For intelligence personnel who are more inclined towards style than safety."),
	"diplomatic" = list("name" = "diplomatic security beret", "desc" = "A tan beret denoting service in the USDF Marines Diplomatic Security Group. For security personnel who are more inclined towards style than safety."),
	"borderguard" = list("name" = "border security beret", "desc" = "A green beret with a silver emblem, denoting service in the Bureau of Border Security. For border guards who are more inclined towards style than safety."),
	"ttc" = list("name" = "transgressive technologies beret", "icon_state" = "beret_purpleyellow", "desc" = "A purple beret denoting service in the Transgressive Technologies Commission. For g-men that are more inclined towards style than safety."),
	"eio" = list("name" = "intelligence oversight beret", "icon_state" = "beret_blue", "desc" = "A blue beret denoting service in Emergent Intelligent Oversight. For g-men that are more inclined towards style than safety."),
	"inspector" = list("name" = "\improper Solar Inspection Group beret", "icon_state" = "beret_graysilver", "desc" = "A grey beret with a silver insignia, denoting service in the Solar Inspection Group. For Almach-inspection personnel who are more inclined towards style than safety."),
))

/obj/item/clothing/head/beret/solgov/Initialize(mapload)
	apply_variant()
	. = ..()

/obj/item/clothing/head/beret/solgov/apply_variant()
	if(!variant)
		return
	var/list/v = GLOB.dq_variants_head_beret_solgov[variant]
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
