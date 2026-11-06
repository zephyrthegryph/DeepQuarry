//*****************
//**Cham Jumpsuit**
//*****************

/obj/item/proc/disguise(newtype)
	//this is necessary, unfortunately, as initial() does not play well with list vars
	var/obj/item/copy = new newtype(null) //so that it is GCed once we exit

	desc = copy.desc
	name = copy.name
	set_icon_state(copy.icon_state)
	set_item_state(copy.item_state)
	set_body_parts_covered(worn_of(copy).covers)
	set_flags_inv(worn_of(copy).hides)

	set_item_icons(copy.item_icons?.Copy())
	set_item_state_slots(copy.item_state_slots?.Copy())
	set_sprite_sheets(copy.sprite_sheets?.Copy())
	//copying sprite_sheets_obj should be unnecessary as chameleon items are not refittable.

	return copy //for inheritance

/proc/generate_chameleon_choices(basetype, blacklist=list())
	. = list()

	var/i = 1 //in case there is a collision with both name AND icon_state
	for(var/obj/O as anything in typesof(basetype) - blacklist)
		if(initial(O.icon) && initial(O.icon_state))
			var/name = initial(O.name)
			if(name in .)
				name += " ([initial(O.icon_state)])"
			if(name in .)
				name += " \[[i++]\]"
			.[name] = O

/// Every chameleon item's appearance choices, built once at boot (make_datum_reference_lists) so no instance, and no
/// test creating one, ever mutates a global. Each list leaves out the chameleon type itself (it would disguise as itself)
/// and the types that break the illusion.
/proc/chameleon_choices_build()
	GLOB.chamelion_jumpsuit_choices = generate_chameleon_choices(/obj/item/clothing/under, list(/obj/item/clothing/under/chameleon, /obj/item/clothing/under/gimmick))
	GLOB.chamelion_head_choices = generate_chameleon_choices(/obj/item/clothing/head, list(/obj/item/clothing/head/chameleon))
	GLOB.chamelion_suit_choices = generate_chameleon_choices(/obj/item/clothing/suit, list(/obj/item/clothing/suit/chameleon, /obj/item/clothing/suit/cyborg_suit, /obj/item/clothing/suit/justice, /obj/item/clothing/suit/greatcoat))
	GLOB.chamelion_shoe_choices = generate_chameleon_choices(/obj/item/clothing/shoes, list(/obj/item/clothing/shoes/chameleon, /obj/item/clothing/shoes/syndigaloshes, /obj/item/clothing/shoes/cyborg))
	GLOB.chamelion_back_choices = generate_chameleon_choices(/obj/item/storage/backpack, list(/obj/item/storage/backpack/chameleon, /obj/item/storage/backpack/satchel/withwallet))
	GLOB.chamelion_glove_choices = generate_chameleon_choices(/obj/item/clothing/gloves, list(/obj/item/clothing/gloves/chameleon))
	GLOB.chamelion_mask_choices = generate_chameleon_choices(/obj/item/clothing/mask, list(/obj/item/clothing/mask/chameleon))
	GLOB.chamelion_belt_choices = generate_chameleon_choices(/obj/item/storage/belt, list(/obj/item/storage/belt/chameleon))
	GLOB.chamelion_accessory_choices = generate_chameleon_choices(/obj/item/clothing/accessory, list(/obj/item/clothing/accessory/chameleon, /obj/item/clothing/accessory/storage))
