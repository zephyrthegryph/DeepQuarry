//Generic Ring

/obj/item/clothing/accessory/ring
	name = "generic ring"
	desc = "Torus shaped finger decoration."
	icon_state = "material"
	drop_sound = SFX_ITEMS_DROP_RING
	slot = ACCESSORY_SLOT_RING
	slot_flags = SLOT_GLOVES
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_gloves.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_gloves.dmi',
		)
	gender = PLURAL
	w_class = ITEMSIZE_SMALL
	icon = 'icons/inventory/hands/item.dmi'
	drop_sound = SFX_ITEMS_DROP_RING
	pickup_sound = SFX_ITEMS_PICKUP_RING
	force = 7	//base punch strength is 5
	punch_force = 2	//added to base punch strength when added as a glove accessory
	siemens_coefficient = 1
	slowdown = 0

/////////////////////////////////////////
//Standard Rings
/obj/item/clothing/accessory/ring/engagement
	name = "engagement ring"
	desc = "An engagement ring. It certainly looks expensive."
	icon_state = "diamond"
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/accessory/ring/engagement)
	op("present", in_hand(), label("Present"), then(PROC_REF(ring_presented)))

/obj/item/clothing/accessory/ring/engagement/proc/ring_presented(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_warning("You get down on one knee, presenting %T%.")), \
		MSG_OTHERS(span_warning("%U% gets down on one knee, presenting %T%.")))

/obj/item/clothing/accessory/ring/cti
	name = "CTI ring"
	desc = "A ring commemorating graduation from CTI."
	icon_state = "cti-grad"

/obj/item/clothing/accessory/ring/mariner
	name = "Mariner University ring"
	desc = "A ring commemorating graduation from Mariner University."
	icon_state = "mariner-grad"


/////////////////////////////////////////
//Reagent Rings

/obj/item/clothing/accessory/ring/reagent
	flags = OPENCONTAINER

DECLARE_REAGENTS(/obj/item/clothing/accessory/ring/reagent, 15, null)

/obj/item/clothing/accessory/ring/reagent/equipped(mob/living/carbon/human/H)
	..()
	if(istype(H) && H.get_equipped_item(SLOT_ID_GLOVES)==src)

		if(reagents.total_volume)
			to_chat(H, span_danger("You feel a prick as you slip on \the [src]."))
			if(H.reagents)
				var/contained = reagents.get_reagents()
				var/trans = reagents.trans_to_mob(H, 15, CHEM_BLOOD)
				add_attack_logs(usr, H, "Injected with [name] containing [contained] transferred [trans] units")
	return

//Sleepy Ring
/obj/item/clothing/accessory/ring/reagent/sleepy
	name = "silver ring"
	desc = "A ring made from what appears to be silver."
	icon_state = "material"

// Less than a sleepy-pen, but still enough to knock someone out
DECLARE_REAGENTS(/obj/item/clothing/accessory/ring/reagent/sleepy, null, list(REAGENT_ID_CHLORALHYDRATE = 15))

/////////////////////////////////////////
//Seals and Signet Rings

/obj/item/clothing/accessory/ring/seal
	var/stamptext = null

/obj/item/clothing/accessory/ring/seal/secgen
	name = "Secretary-General's official seal"
	desc = "The official seal of the Secretary-General of the Sol Central Government, featured prominently on a silver ring."
	icon_state = "seal-secgen"

/obj/item/clothing/accessory/ring/seal/mason
	name = "\improper Masonic ring"
	desc = "The Square and Compasses feature prominently on this Masonic ring."
	icon_state = "seal-masonic"

/obj/item/clothing/accessory/ring/seal/signet
	name = "signet ring"
	desc = "A signet ring, for when you're too sophisticated to sign letters."
	icon_state = "seal-signet"
	var/nameset = FALSE
	special_handling = TRUE

TRACKED(/obj/item/clothing/accessory/ring/seal/signet, nameset)

MSG_DEF_SELF(signet/claimed, "it has already been claimed")

CAPABILITIES(/obj/item/clothing/accessory/ring/seal/signet)
	op("claim", in_hand(), label("Claim"), needs(req_is(nameof(nameset), FALSE, because = MSG(signet/claimed))), then(PROC_REF(ring_claimed)))

/obj/item/clothing/accessory/ring/seal/signet/proc/ring_claimed(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You claim the [src] as your own!"))
	change_name(user)
	set_nameset(TRUE)

/obj/item/clothing/accessory/ring/seal/signet/proc/change_name(signet_name = "Unknown")
	name = "[signet_name]'s signet ring"
	desc = "A signet ring belonging to [signet_name], for when you're too sophisticated to sign letters."

/obj/item/clothing/accessory/ring/wedding
	name = "golden wedding ring"
	desc = "For showing your devotion to another person. It has a golden glimmer to it."
	icon = 'icons/inventory/hands/item.dmi'
	icon_state = "wedring_g"
	item_state = "wedring_g"
	var/partnername = ""
	special_handling = TRUE

TRACKED(/obj/item/clothing/accessory/ring/wedding, partnername)

CAPABILITIES(/obj/item/clothing/accessory/ring/wedding)
	op("engrave", in_hand(), label("Engrave"),
		asks(/datum/prompt/text, keeps = 0, fields = list("question" = "Would you like to change the holoengraving on the ring?", "title" = "Name your spouse", "default" = "Bae", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0)), then(PROC_REF(engraving_picked)))

/obj/item/clothing/accessory/ring/wedding/proc/engraving_picked(datum/act/op/A)
	var/datum/prompt/text/picked = A.answer
	if(picked.value)
		set_partnername(picked.value)
		name = "[initial(name)] - [partnername]"
	return OP_OK

/obj/item/clothing/accessory/ring/wedding/silver
	name = "silver wedding ring"
	desc = "For showing your devotion to another person. It has a silver glimmer to it."
	icon_state = "wedring_s"
	item_state = "wedring_s"

/////////////////////////////////////////
//Material Rings
/obj/item/clothing/accessory/ring/material
	icon = 'icons/inventory/hands/item.dmi'
	icon_state = "material"
	material_slowdown_multiplier = 0 //it's a ring, it's never gonna be heavy enough to matter

TYPE_TABLE_DECLARE(/obj/item/clothing/accessory/ring/material, ring_forced_material, null)

// ALLOW(init/INSTANCE_STATE): a material ring is named and coloured for its material (or the type's forced one)
/obj/item/clothing/accessory/ring/material/Initialize(mapload)
	var/forced_material = TYPE_TABLE_GET(src, ring_forced_material)
	if(forced_material)
		default_material = forced_material
	. = ..()
	material = get_material_by_name(default_material || MAT_STEEL)
	if(!istype(material))
		return INITIALIZE_HINT_QDEL
	name = "[material.display_name] ring"
	desc = "A ring made from [material.display_name]."
	color = material.icon_colour

/obj/item/clothing/accessory/ring/material/get_material()
	return material

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/wood, ring_forced_material, MAT_WOOD)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/plastic, ring_forced_material, MAT_PLASTIC)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/iron, ring_forced_material, MAT_IRON)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/glass, ring_forced_material, MAT_GLASS)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/steel, ring_forced_material, MAT_STEEL)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/silver, ring_forced_material, MAT_SILVER)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/gold, ring_forced_material, MAT_GOLD)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/platinum, ring_forced_material, MAT_PLATINUM)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/phoron, ring_forced_material, MAT_PHORON)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/titanium, ring_forced_material, MAT_TITANIUM)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/copper, ring_forced_material, MAT_COPPER)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/bronze, ring_forced_material, MAT_BRONZE)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/uranium, ring_forced_material, MAT_URANIUM)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/osmium, ring_forced_material, MAT_OSMIUM)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/lead, ring_forced_material, MAT_LEAD)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/diamond, ring_forced_material, MAT_DIAMOND)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/tin, ring_forced_material, MAT_TIN)

TYPE_TABLE(/obj/item/clothing/accessory/ring/material/void_opal, ring_forced_material, MAT_VOPAL)


/obj/item/clothing/accessory/ring/ringworld1
	name = "world gem ring"
	desc = "A ring that has a tiny world inside its glassy gem. You can even see clouds moving."
	icon = 'icons/inventory/hands/item_ch.dmi'
	icon_state = "ringworld1"
	drop_sound = SFX_ITEMS_DROP_RING

/obj/item/clothing/accessory/ring/ringworld2
	name = "world ring"
	desc = "A ring that has a tiny landscape all around its exterior. You can even see clouds moving."
	icon = 'icons/inventory/hands/item_ch.dmi'
	icon_state = "ringworld2"
	drop_sound = SFX_ITEMS_DROP_RING
