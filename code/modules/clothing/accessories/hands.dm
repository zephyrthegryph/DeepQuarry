/obj/item/clothing/accessory/knuckledusters
	name = "knuckle dusters"
	desc = "A pair of brass knuckles. Generally used to enhance the user's punches."
	icon_state = "knuckledusters"
	slot = ACCESSORY_SLOT_RING
	slot_flags = SLOT_GLOVES
	MATERIAL_BULK(MAT_STEEL, 500)
	attack_verb = list("punched", "beaten", "struck")
	siemens_coefficient = 1
	force = 10	//base punch strength is 5
	punch_force = 5	//added to base punch strength when added as a glove accessory
	icon = 'icons/inventory/hands/item.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_gloves.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_gloves.dmi',
		)
	drop_sound = SFX_ITEMS_DROP_METALBOOTS
	pickup_sound = SFX_ITEMS_PICKUP_TOOLBOX

//bracelets

/obj/item/clothing/accessory/bracelet
	name = "bracelet"
	desc = "A simple silver bracelet with a clasp."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "bracelet"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_GLOVES | SLOT_TIE
	slot = ACCESSORY_SLOT_WRIST

/obj/item/clothing/accessory/bracelet/friendship
	name = "friendship bracelet"
	desc = "A beautiful friendship bracelet in all the colors of the rainbow."
	icon_state = "friendbracelet"

EXTEND_INTERACTIONS(/obj/item/clothing/accessory/bracelet/friendship, \
	INTERACT_VERB("Dedicate Bracelet", PROC_REF(friendship_dedicate_bracelet_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Dedicate Bracelet".
/obj/item/clothing/accessory/bracelet/friendship/proc/friendship_dedicate_bracelet_verb(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/M = user
	if(!M.mind)
		return 0

	open_request(src, /datum/prompt/text, PROC_REF(friendship_dedication_entered), answerer = M, question = "Who do you want to dedicate the bracelet to?", title = "Friendship Bracelet", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE, timeout = 0)

/obj/item/clothing/accessory/bracelet/friendship/proc/friendship_dedication_entered(datum/act/request/A)
	if(!A.answer)
		return
	. = apply_friendship_dedication(A)
	SStgui.update_uis(src)

/obj/item/clothing/accessory/bracelet/friendship/proc/apply_friendship_dedication(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/M = A.request.answerer
	if(!M.mind)
		return 0
	var/_answer_a1 = A.answer.value
	if(isnull(_answer_a1))
		return
	var/input = sanitizeSafe(_answer_a1, MAX_NAME_LEN)

	if(src && input && !M.stat && in_range(M,src))
		desc = "A beautiful friendship bracelet in all the colors of the rainbow. It's dedicated to [input]."
		to_chat(M, "You dedicate the bracelet to [input], remembering the times you've had together.")
		return 1


/obj/item/clothing/accessory/bracelet/material
	icon_state = "materialbracelet"
	material_slowdown_multiplier = 0
	slowdown = 0

TYPE_TABLE_DECLARE(/obj/item/clothing/accessory/bracelet/material, bracelet_forced_material, null)

// ALLOW(init/INSTANCE_STATE): a material bracelet is named and coloured for its material (or the type's forced one)
/obj/item/clothing/accessory/bracelet/material/Initialize(mapload)
	var/forced_material = TYPE_TABLE_GET(src, bracelet_forced_material)
	if(forced_material)
		default_material = forced_material
	. = ..()
	material = get_material_by_name(default_material || MAT_STEEL)
	if(!istype(material))
		return INITIALIZE_HINT_QDEL
	name = "[material.display_name] bracelet"
	desc = "A bracelet made from [material.display_name]."
	color = material.icon_colour

/obj/item/clothing/accessory/bracelet/material/get_material()
	return material

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/wood, bracelet_forced_material, MAT_WOOD)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/plastic, bracelet_forced_material, MAT_PLASTIC)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/iron, bracelet_forced_material, MAT_IRON)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/steel, bracelet_forced_material, MAT_STEEL)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/silver, bracelet_forced_material, MAT_SILVER)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/gold, bracelet_forced_material, MAT_GOLD)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/platinum, bracelet_forced_material, MAT_PLATINUM)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/phoron, bracelet_forced_material, MAT_PHORON)

TYPE_TABLE(/obj/item/clothing/accessory/bracelet/material/glass, bracelet_forced_material, MAT_GLASS)

//wristbands

/obj/item/clothing/accessory/wristband
	name = "wristband"
	desc = "A simple plastic wristband."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "wristband"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_GLOVES  | SLOT_TIE
	slot = ACCESSORY_SLOT_WRIST

/obj/item/clothing/accessory/wristband/spiked
	name = "wristband (spiked)"
	desc = "A black wristband with short spikes around it."
	icon_state = "wristband_spiked"

/obj/item/clothing/accessory/wristband/collection
	name = "wristband collection"
	desc = "A mix of colourable plastic wristbands."
	icon_state = "wristband_collection"

/obj/item/clothing/accessory/wristband/collection/pink
	name = "wristband collection"
	desc = "A mix of colourable plastic wristbands."
	icon_state = "wristband_collection2"

/obj/item/clothing/accessory/wristband/collection/les
	name = "wristband collection"
	desc = "A mix of colourable plastic wristbands."
	icon_state = "wristband_collection3"

/obj/item/clothing/accessory/wristband/collection/trans
	name = "wristband collection"
	desc = "A mix of colourable plastic wristbands."
	icon_state = "wristband_collection4"

/obj/item/clothing/accessory/wristband/collection/bi
	name = "wristband collection"
	desc = "A mix of colourable plastic wristbands."
	icon_state = "wristband_collection5"

/obj/item/clothing/accessory/wristband/collection/ace
	name = "wristband collection"
	desc = "A mix of colourable plastic wristbands."
	icon_state = "wristband_collection6"
