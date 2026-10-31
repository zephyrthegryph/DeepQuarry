/obj/item/stack/material/chitin
	name = MAT_CHITIN
	desc = "The by-product of mob grinding."
	icon_state = "chitin"
	default_type = MAT_CHITIN
	no_variants = FALSE
	pass_color = TRUE
	strict_color_stacking = TRUE

CAPABILITIES(/obj/item/stack/material/chitin)
	configure(item_sounds(drop = SFX_ITEMS_DROP_LEATHER, pickup = SFX_ITEMS_PICKUP_LEATHER))

//don't see anywhere else to put these, maybe together they could be used to make the xenos suit?
/obj/item/stack/xenochitin
	name = MAT_ALIENCHITIN
	desc = "A piece of the hide of a terrible creature."
	singular_name = "alien chitin piece"
	icon = 'icons/mob/alien.dmi'
	icon_state = "chitin"
	stacktype = "hide-chitin"

/obj/item/xenos_claw
	name = MAT_ALIENCLAW
	desc = "The claw of a terrible creature."
	icon = 'icons/mob/alien.dmi'
	icon_state = "claw"

/obj/item/weed_extract
	name = MAT_WEEDEXTRACT
	desc = "A piece of slimy, purplish weed."
	icon = 'icons/mob/alien.dmi'
	icon_state = "weed_extract"

/////FUR AND WOOL MATERIALS/////

/datum/material/fur
	name = MAT_FUR
	icon_colour = "#fff2d3"
	display_name = MAT_FUR
	icon_base = "sheet-fabric"
	stack_type = /obj/item/stack/material/fur
	sheet_collective_name = "pile"
	pass_stack_colors = TRUE
	supply_conversion_value = 0.5
	sheet_singular_name = "bundle"
	sheet_plural_name = "bundles"
	ignition_point = T0C+232
	melting_point = T0C+300
	protectiveness = 1
	flags = MATERIAL_PADDING
	conductive = 0
	integrity = 40
	hardness = 5

/datum/material/fur/wool
	name = MAT_WOOL
	display_name = MAT_WOOL
	stack_type = /obj/item/stack/material/fur/wool

/transformation/stack/fur__duster
CAPABILITIES(/transformation/stack/fur__duster)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/clothing/suit/storage/duster/craftable, 1)),
		chosen = chosen(title = "duster",
			subject = /datum/material/fur,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF,
			replaces = TRUE)))

/transformation/stack/fur__bedsheet
CAPABILITIES(/transformation/stack/fur__bedsheet)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/bedsheet/craftable, 1)),
		chosen = chosen(title = "bedsheet",
			subject = /datum/material/fur,
			build_time = 30 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__jumpsuit
CAPABILITIES(/transformation/stack/fur__jumpsuit)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/color/white/craftable, 1)),
		chosen = chosen(title = "jumpsuit",
			subject = /datum/material/fur,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__foot_wraps
CAPABILITIES(/transformation/stack/fur__foot_wraps)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/shoes/footwraps/craftable, 1)),
		chosen = chosen(title = "foot wraps",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__gloves
CAPABILITIES(/transformation/stack/fur__gloves)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/gloves/white/craftable, 1)),
		chosen = chosen(title = "gloves",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__wig
CAPABILITIES(/transformation/stack/fur__wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/head/powdered_wig, 1)),
		chosen = chosen(title = "wig",
			subject = /datum/material/fur,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__philosopher_s_wig
CAPABILITIES(/transformation/stack/fur__philosopher_s_wig)
	configure(transformation(takes = list(stack_term(STACK_SELF, 50)), makes = list(item_term(/obj/item/clothing/head/philosopher_wig, 1)),
		chosen = chosen(title = "philosopher's wig",
			subject = /datum/material/fur,
			build_time = 2 MINUTES,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__taqiyah
CAPABILITIES(/transformation/stack/fur__taqiyah)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/taqiyah/craftable, 1)),
		chosen = chosen(title = "taqiyah",
			subject = /datum/material/fur,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__turban
CAPABILITIES(/transformation/stack/fur__turban)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/turban/craftable, 1)),
		chosen = chosen(title = "turban",
			subject = /datum/material/fur,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__hijab
CAPABILITIES(/transformation/stack/fur__hijab)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/hijab/craftable, 1)),
		chosen = chosen(title = "hijab",
			subject = /datum/material/fur,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__kippa
CAPABILITIES(/transformation/stack/fur__kippa)
	configure(transformation(takes = list(stack_term(STACK_SELF, 3)), makes = list(item_term(/obj/item/clothing/head/kippa/craftable, 1)),
		chosen = chosen(title = "kippa",
			subject = /datum/material/fur,
			build_time = 6 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__scarf
CAPABILITIES(/transformation/stack/fur__scarf)
	configure(transformation(takes = list(stack_term(STACK_SELF, 4)), makes = list(item_term(/obj/item/clothing/accessory/scarf/white/craftable, 1)),
		chosen = chosen(title = "scarf",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__baggy_pants
CAPABILITIES(/transformation/stack/fur__baggy_pants)
	configure(transformation(takes = list(stack_term(STACK_SELF, 8)), makes = list(item_term(/obj/item/clothing/under/pants/baggy/white/craftable, 1)),
		chosen = chosen(title = "baggy pants",
			subject = /datum/material/fur,
			build_time = 10 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__belt_pouch
CAPABILITIES(/transformation/stack/fur__belt_pouch)
	configure(transformation(takes = list(stack_term(STACK_SELF, 25)), makes = list(item_term(/obj/item/storage/belt/fannypack/white/craftable, 1)),
		chosen = chosen(title = "belt pouch",
			subject = /datum/material/fur,
			build_time = 1 MINUTE,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__pouch_small
CAPABILITIES(/transformation/stack/fur__pouch_small)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/small, 1)),
		chosen = chosen(title = "pouch, small",
			subject = /datum/material/fur,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__pouch_ammo
CAPABILITIES(/transformation/stack/fur__pouch_ammo)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/ammo, 1)),
		chosen = chosen(title = "pouch, ammo",
			subject = /datum/material/fur,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__pouch_tools
CAPABILITIES(/transformation/stack/fur__pouch_tools)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/eng_tool, 1)),
		chosen = chosen(title = "pouch, tools",
			subject = /datum/material/fur,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__pouch_parts
CAPABILITIES(/transformation/stack/fur__pouch_parts)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/eng_parts, 1)),
		chosen = chosen(title = "pouch, parts",
			subject = /datum/material/fur,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__pouch_supplies
CAPABILITIES(/transformation/stack/fur__pouch_supplies)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/eng_supply, 1)),
		chosen = chosen(title = "pouch, supplies",
			subject = /datum/material/fur,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__pouch_medical
CAPABILITIES(/transformation/stack/fur__pouch_medical)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/medical, 1)),
		chosen = chosen(title = "pouch, medical",
			subject = /datum/material/fur,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__pouch_flare
CAPABILITIES(/transformation/stack/fur__pouch_flare)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/storage/pouch/flares, 1)),
		chosen = chosen(title = "pouch, flare",
			subject = /datum/material/fur,
			build_time = 20 SECONDS,
			pass_color = FALSE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__crude_bandage
CAPABILITIES(/transformation/stack/fur__crude_bandage)
	configure(transformation(takes = list(stack_term(STACK_SELF, 1)), makes = list(item_term(/obj/item/stack/medical/crude_pack, 1)),
		chosen = chosen(title = "crude bandage",
			subject = /datum/material/fur,
			build_time = 2 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__empty_sandbag
CAPABILITIES(/transformation/stack/fur__empty_sandbag)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/stack/emptysandbag, 1)),
		chosen = chosen(title = "empty sandbag",
			subject = /datum/material/fur,
			build_time = 2 SECONDS,
			material = STACK_MATERIAL_SELF,
			pass_color = TRUE)))

/transformation/stack/fur__satchel
CAPABILITIES(/transformation/stack/fur__satchel)
	configure(transformation(takes = list(stack_term(STACK_SELF, 30)), makes = list(item_term(/obj/item/storage/backpack/satchel/craftable, 1)),
		chosen = chosen(title = "satchel",
			subject = /datum/material/fur,
			build_time = 1 MINUTE,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__backpack
CAPABILITIES(/transformation/stack/fur__backpack)
	configure(transformation(takes = list(stack_term(STACK_SELF, 30)), makes = list(item_term(/obj/item/storage/backpack/craftable, 1)),
		chosen = chosen(title = "backpack",
			subject = /datum/material/fur,
			build_time = 1 MINUTE,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__cloak
CAPABILITIES(/transformation/stack/fur__cloak)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/clothing/accessory/poncho/roles/cloak/custom, 1)),
		chosen = chosen(title = "cloak",
			subject = /datum/material/fur,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__teshari_cloak
CAPABILITIES(/transformation/stack/fur__teshari_cloak)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/clothing/under/teshari/smock/white/craftable, 1)),
		chosen = chosen(title = "teshari cloak",
			subject = /datum/material/fur,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__teshari_beltcloak
CAPABILITIES(/transformation/stack/fur__teshari_beltcloak)
	configure(transformation(takes = list(stack_term(STACK_SELF, 10)), makes = list(item_term(/obj/item/clothing/suit/storage/teshari/beltcloak/standard/black_white/craftable, 1)),
		chosen = chosen(title = "teshari beltcloak",
			subject = /datum/material/fur,
			build_time = 15 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__bandana
CAPABILITIES(/transformation/stack/fur__bandana)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/clothing/head/bandana/craftable, 1)),
		chosen = chosen(title = "bandana",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__headband
CAPABILITIES(/transformation/stack/fur__headband)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/clothing/head/fluff/headbando/craftable, 1)),
		chosen = chosen(title = "headband",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__armband
CAPABILITIES(/transformation/stack/fur__armband)
	configure(transformation(takes = list(stack_term(STACK_SELF, 5)), makes = list(item_term(/obj/item/clothing/accessory/armband/med/color/craftable, 1)),
		chosen = chosen(title = "armband",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__collar
CAPABILITIES(/transformation/stack/fur__collar)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/accessory/collar/craftable, 1)),
		chosen = chosen(title = "collar",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/transformation/stack/fur__blindfold
CAPABILITIES(/transformation/stack/fur__blindfold)
	configure(transformation(takes = list(stack_term(STACK_SELF, 2)), makes = list(item_term(/obj/item/clothing/glasses/sunglasses/blindfold/whiteblindfold/craftable, 1)),
		chosen = chosen(title = "blindfold",
			subject = /datum/material/fur,
			build_time = 5 SECONDS,
			pass_color = TRUE,
			recycle = STACK_MATERIAL_SELF)))

/obj/item/stack/material/fur
	name = MAT_FUR
	icon_state = "sheet-fabric"
	default_type = MAT_FUR
	strict_color_stacking = TRUE
	apply_colour = 1
	no_variants = FALSE
	pass_color = TRUE
	apply_colour = TRUE

CAPABILITIES(/obj/item/stack/material/fur)
	configure(item_sounds(drop = SFX_ITEMS_DROP_CLOTHING, pickup = SFX_ITEMS_PICKUP_CLOTHING))

/obj/item/stack/material/fur/wool
	name = MAT_WOOL
	default_type = MAT_WOOL

/obj/item/clothing/suit/storage/duster/craftable
	name = "handmade duster"
/obj/item/bedsheet/craftable
	name = "handmade bedsheet"
/obj/item/clothing/under/color/white/craftable
	name = "handmade jumpsuit"
/obj/item/clothing/shoes/footwraps/craftable
	name = "handmade footwraps"
/obj/item/clothing/gloves/white/craftable
	name = "handmade gloves"
/obj/item/clothing/head/taqiyah/craftable
	name = "handmade taqiyah"
/obj/item/clothing/head/turban/craftable
	name = "handmade turban"
/obj/item/clothing/head/hijab/craftable
	name = "handmade hijab"
/obj/item/clothing/head/kippa/craftable
	name = "handmade kippa"
/obj/item/clothing/accessory/scarf/white/craftable
	name = "handmade scarf"
/obj/item/clothing/under/pants/baggy/white/craftable
	name = "handmade pants"
/obj/item/storage/belt/fannypack/white/craftable
	name = "handmade fannypack"
/obj/item/storage/backpack/satchel/craftable
	name = "handmade satchel"
	icon_state = "satchel_white"
	desc = "A handmade satchel, made for holding your things!"
/obj/item/storage/backpack/craftable
	name = "handmade backpack"
	icon_state = "backpack_white"
/obj/item/clothing/under/teshari/smock/white/craftable
	name = "handmade smock"
/obj/item/clothing/suit/storage/teshari/cloak/standard/white/craftable
	name = "handmade teshari cloak"
/obj/item/clothing/suit/storage/teshari/beltcloak/standard/black_white/craftable
	name = "handmade teshari beltcloak"
/obj/item/clothing/head/bandana/craftable
	name = "handmade bandana"
	icon_state = "bandana-pirate-white"
/obj/item/clothing/head/fluff/headbando/craftable
	name = "handmade bandana"
/obj/item/clothing/accessory/armband/med/color/craftable
	name = "handmade armband"
/obj/item/clothing/accessory/collar/craftable
	name = "handmade collar"
	desc = "A collar made out of pliable material."
	icon_state = "collar_handmade"
	var/given_name
	special_handling = TRUE
/obj/item/clothing/glasses/sunglasses/blindfold/whiteblindfold/craftable
	name = "handmade blindfold"
	desc = "A handmade blindfold that covers the eyes, preventing sight."

CAPABILITIES(/obj/item/clothing/accessory/collar/craftable)
	op("craftable_collar_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 2), label("Label"),
		asks(/datum/prompt/text/collar_tag/craftable_label, fields = list("captured_item" = computed(PROC_REF(craftable_collar_held)), "item_expected" = TRUE), step = "label"),
		then(PROC_REF(craftable_collar_self)))

/// The item the self-use came from (the collar), which the label question keeps (captured_item).
/obj/item/clothing/accessory/collar/craftable/proc/craftable_collar_held(datum/act/op/A)
	return A.held

/// Old attack_self after the collar's own tag handling (the parent op declines or the tag is already engraved): the typed label becomes the given name.
/obj/item/clothing/accessory/collar/craftable/proc/craftable_collar_self(datum/act/op/A)
	var/label = A.step_value("label")
	if(isnull(label))
		return OP_OK
	given_name = sanitizeSafe(label, MAX_NAME_LEN)
	SStgui.update_uis(src)
	return OP_OK

/// The existing collar prompt's relation views keep the exact original self-action arguments.
/datum/prompt/text/collar_tag/craftable_label
	question = "What would you like to label the collar?"
	title = "Collar Labelling"
	encode = FALSE
	recheck_on_open = TRUE

/datum/prompt/text/collar_tag/craftable_label/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null

/datum/prompt/text/collar_tag/craftable_label/refusal(value)
	return null

/datum/prompt/text/collar_tag/craftable_label/recheck_extra()
	return !owner || QDELETED(owner) || captures_gone() ? "gone" : null
