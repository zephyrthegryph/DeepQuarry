//*****************
//**Cham Jumpsuit**
//*****************

/obj/item/proc/disguise(newtype)
	//this is necessary, unfortunately, as initial() does not play well with list vars
	var/obj/item/copy = new newtype(null) //so that it is GCed once we exit

	desc = copy.desc
	name = copy.name
	icon_state = copy.icon_state
	item_state = copy.item_state
	body_parts_covered = copy.body_parts_covered
	flags_inv = copy.flags_inv

	item_icons = copy.item_icons?.Copy()
	item_state_slots = copy.item_state_slots?.Copy()
	sprite_sheets = copy.sprite_sheets?.Copy()
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

/obj/item/clothing/under/chameleon
//starts off as black
	name = "black jumpsuit"
	icon_state = "black"
	worn_state = "black"
	desc = "It's a plain jumpsuit. It seems to have a small dial on the wrist."


/obj/item/clothing/under/chameleon/on_materialize()
	if(!GLOB.chamelion_jumpsuit_choices)
		var/blocked = list(src.type, /obj/item/clothing/under/gimmick)//Prevent infinite loops and bad jumpsuits.
		GLOB.chamelion_jumpsuit_choices = generate_chameleon_choices(/obj/item/clothing/under, blocked)
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/under/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "psychedelic"
	desc = "Groovy!"
	icon_state = "psyche"
	LAZYSET(item_state_slots, slot_w_uniform_str, "psyche")
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/under/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("chameleon_change_verb", menu(), label("Change Jumpsuit Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(chameleon_change_verb)))

/// Old verb "Change Jumpsuit Appearance".
/obj/item/clothing/under/chameleon/proc/chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_jumpsuit_choices

/obj/item/clothing/under/chameleon/proc/chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_jumpsuit_choices[picked]))
		return

	disguise(GLOB.chamelion_jumpsuit_choices[picked])
	update_clothing_icon()	//so our overlays update.

//*****************
//**Chameleon Hat**
//*****************

/obj/item/clothing/head/chameleon
	name = "grey cap"
	icon_state = "greysoft"
	desc = "It looks like a plain hat, but upon closer inspection, there's an advanced holographic array installed inside. It seems to have a small dial inside."
	body_parts_covered = 0

/obj/item/clothing/head/chameleon/on_materialize()
	if(!GLOB.chamelion_head_choices)
		var/blocked = list(src.type)//Prevent infinite loops and bad hats.
		GLOB.chamelion_head_choices = generate_chameleon_choices(/obj/item/clothing/head, blocked)
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/head/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "grey cap"
	desc = "It's a baseball hat in a tasteful grey colour."
	icon_state = "greysoft"
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/head/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("head_chameleon_change_verb", menu(), label("Change Hat/Helmet Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(head_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(head_chameleon_change_verb)))

/// Old verb "Change Hat/Helmet Appearance".
/obj/item/clothing/head/chameleon/proc/head_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_head_choices

/obj/item/clothing/head/chameleon/proc/head_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_head_choices[picked]))
		return

	disguise(GLOB.chamelion_head_choices[picked])
	update_clothing_icon()	//so our overlays update.

//******************
//**Chameleon Suit**
//******************

/obj/item/clothing/suit/chameleon
	name = "armor"
	icon_state = "armor"
	desc = "It appears to be a vest of standard armor, except this is embedded with a hidden holographic cloaker, allowing it to change it's appearance, but offering no protection.. It seems to have a small dial inside."

/obj/item/clothing/suit/chameleon/on_materialize()
	if(!GLOB.chamelion_suit_choices)
		var/blocked = list(src.type, /obj/item/clothing/suit/cyborg_suit, /obj/item/clothing/suit/justice, /obj/item/clothing/suit/greatcoat)
		GLOB.chamelion_suit_choices = generate_chameleon_choices(/obj/item/clothing/suit, blocked)
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/suit/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "armor"
	desc = "An armored vest that protects against some damage."
	icon_state = "armor"
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/suit/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("suit_chameleon_change_verb", menu(), label("Change Oversuit Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(suit_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(suit_chameleon_change_verb)))

/// Old verb "Change Oversuit Appearance".
/obj/item/clothing/suit/chameleon/proc/suit_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_suit_choices

/obj/item/clothing/suit/chameleon/proc/suit_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_suit_choices[picked]))
		return

	disguise(GLOB.chamelion_suit_choices[picked])
	update_clothing_icon()	//so our overlays update.

//*******************
//**Chameleon Shoes**
//*******************
/obj/item/clothing/shoes/chameleon
	name = "black shoes"
	icon_state = "black"
	desc = "They're comfy black shoes, with clever cloaking technology built in. It seems to have a small dial on the back of each shoe."

/obj/item/clothing/shoes/chameleon/on_materialize()
	if(!GLOB.chamelion_shoe_choices)
		var/blocked = list(src.type, /obj/item/clothing/shoes/syndigaloshes, /obj/item/clothing/shoes/cyborg)//prevent infinite loops and bad shoes.
		GLOB.chamelion_shoe_choices = generate_chameleon_choices(/obj/item/clothing/shoes, blocked)
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/shoes/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "black shoes"
	desc = "A pair of black shoes."
	icon_state = "black"
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/shoes/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("shoes_chameleon_change_verb", menu(), label("Change Footwear Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(shoes_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(shoes_chameleon_change_verb)))

/// Old verb "Change Footwear Appearance".
/obj/item/clothing/shoes/chameleon/proc/shoes_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_shoe_choices

/obj/item/clothing/shoes/chameleon/proc/shoes_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_shoe_choices[picked]))
		return

	disguise(GLOB.chamelion_shoe_choices[picked])
	update_clothing_icon()	//so our overlays update.

//**********************
//**Chameleon Backpack**
//**********************
/obj/item/storage/backpack/chameleon
	name = "backpack"
	icon_state = "backpack"
	desc = "A backpack outfitted with cloaking tech. It seems to have a small dial inside, kept away from the storage."

/obj/item/storage/backpack/chameleon/Initialize(mapload)
	. = ..()
	if(!GLOB.chamelion_back_choices)
		var/blocked = list(src.type, /obj/item/storage/backpack/satchel/withwallet)
		GLOB.chamelion_back_choices = generate_chameleon_choices(/obj/item/storage/backpack, blocked)

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/storage/backpack/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "backpack"
	desc = "You wear this on your back and put items into it."
	icon_state = "backpack"
	if (ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_back()

CAPABILITIES(/obj/item/storage/backpack/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("backpack_chameleon_change_verb", menu(), label("Change Backpack Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(backpack_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(backpack_chameleon_change_verb)))

/// Old verb "Change Backpack Appearance".
/obj/item/storage/backpack/chameleon/proc/backpack_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_back_choices

/obj/item/storage/backpack/chameleon/proc/backpack_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_back_choices[picked]))
		return

	disguise(GLOB.chamelion_back_choices[picked])

	//so our overlays update.
	if (ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_back()

/obj/item/storage/backpack/chameleon/full
	starts_with = list(
		/obj/item/clothing/under/chameleon,
		/obj/item/clothing/head/chameleon,
		/obj/item/clothing/suit/chameleon,
		/obj/item/clothing/shoes/chameleon,
		/obj/item/clothing/gloves/chameleon,
		/obj/item/clothing/mask/chameleon,
		/obj/item/clothing/glasses/chameleon,
		/obj/item/clothing/accessory/chameleon
	)

//********************
//**Chameleon Gloves**
//********************

/obj/item/clothing/gloves/chameleon
	name = "black gloves"
	icon_state = "black"
	desc = "It looks like a pair of gloves, but it seems to have a small dial inside."

/obj/item/clothing/gloves/chameleon/on_materialize()
	if(!GLOB.chamelion_glove_choices)
		GLOB.chamelion_glove_choices = generate_chameleon_choices(/obj/item/clothing/gloves, list(src.type))
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/gloves/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "black gloves"
	desc = "It looks like a pair of gloves, but it seems to have a small dial inside."
	icon_state = "black"
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/gloves/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("gloves_chameleon_change_verb", menu(), label("Change Gloves Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(gloves_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(gloves_chameleon_change_verb)))

/// Old verb "Change Gloves Appearance".
/obj/item/clothing/gloves/chameleon/proc/gloves_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_glove_choices

/obj/item/clothing/gloves/chameleon/proc/gloves_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_glove_choices[picked]))
		return

	disguise(GLOB.chamelion_glove_choices[picked])
	update_clothing_icon()	//so our overlays update.

//******************
//**Chameleon Mask**
//******************

/obj/item/clothing/mask/chameleon
	name = "gas mask"
	icon_state = "gas_alt" // file change
	desc = "It looks like a plain gask mask, but on closer inspection, it seems to have a small dial inside."

/obj/item/clothing/mask/chameleon/on_materialize()
	if(!GLOB.chamelion_mask_choices)
		GLOB.chamelion_mask_choices = generate_chameleon_choices(/obj/item/clothing/mask, list(src.type))
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/mask/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "gas mask"
	desc = "It's a gas mask."
	icon_state = "gas_alt" // file change
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/mask/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("mask_chameleon_change_verb", menu(), label("Change Mask Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(mask_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(mask_chameleon_change_verb)))

/// Old verb "Change Mask Appearance".
/obj/item/clothing/mask/chameleon/proc/mask_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_mask_choices

/obj/item/clothing/mask/chameleon/proc/mask_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_mask_choices[picked]))
		return

	disguise(GLOB.chamelion_mask_choices[picked])
	update_clothing_icon()	//so our overlays update.

//*********************
//**Chameleon Glasses**
//*********************

/obj/item/clothing/glasses/chameleon
	name = "Optical Meson Scanner"
	icon_state = "meson"
	item_state_slots = list(slot_r_hand_str = "meson", slot_l_hand_str = "meson")
	desc = "It looks like a plain set of mesons, but on closer inspection, it seems to have a small dial inside."
	var/list/global/clothing_choices

/obj/item/clothing/glasses/chameleon/on_materialize()
	if(!clothing_choices)
		clothing_choices = generate_chameleon_choices(/obj/item/clothing/glasses, list(src.type))
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/glasses/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "Optical Meson Scanner"
	desc = "It's a set of mesons."
	icon_state = "meson"
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/glasses/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("glasses_chameleon_change_verb", menu(), label("Change Glasses Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = nameof(clothing_choices), "timeout" = 0), step = "a1"), then(PROC_REF(glasses_chameleon_change_verb)))

/// Old verb "Change Glasses Appearance".
/obj/item/clothing/glasses/chameleon/proc/glasses_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(clothing_choices[picked]))
		return

	disguise(clothing_choices[picked])
	update_clothing_icon()	//so our overlays update.

//******************
//**Chameleon Belt**
//******************

/obj/item/storage/belt/chameleon
	name = "belt"
	desc = "Can hold various things.  It also has a small dial inside one of the pouches."
	icon_state = "utilitybelt"

/obj/item/storage/belt/chameleon/Initialize(mapload)
	. = ..()
	if(!GLOB.chamelion_belt_choices)
		GLOB.chamelion_belt_choices = generate_chameleon_choices(/obj/item/storage/belt, list(src.type))

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/storage/belt/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "belt"
	desc = "Can hold various things."
	icon_state = "utilitybelt"
	if(ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_belt()

CAPABILITIES(/obj/item/storage/belt/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("belt_chameleon_change_verb", menu(), label("Change Belt Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(belt_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(belt_chameleon_change_verb)))

/// Old verb "Change Belt Appearance".
/obj/item/storage/belt/chameleon/proc/belt_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_belt_choices

/obj/item/storage/belt/chameleon/proc/belt_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_belt_choices[picked]))
		return

	disguise(GLOB.chamelion_belt_choices[picked])

	if(ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_belt() //so our overlays update.

//******************
//**Chameleon Tie**
//******************

/obj/item/clothing/accessory/chameleon
	name = "black tie"
	desc = "Looks like a black tie, but his one also has a dial inside."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "blacktie"

/obj/item/clothing/accessory/chameleon/on_materialize()
	if(!GLOB.chamelion_accessory_choices)
		var/blocked = list(src.type, /obj/item/clothing/accessory/storage)
		GLOB.chamelion_accessory_choices = generate_chameleon_choices(/obj/item/clothing/accessory, blocked)
	. = ..()

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/clothing/accessory/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "black tie"
	desc = "Looks like a black tie, but his one also has a dial inside."
	icon_state = "blacktie"
	update_clothing_icon()

CAPABILITIES(/obj/item/clothing/accessory/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("accessory_chameleon_change_verb", menu(), label("Change Accessory Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(accessory_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(accessory_chameleon_change_verb)))

/// Old verb "Change Accessory Appearance".
/obj/item/clothing/accessory/chameleon/proc/accessory_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.chamelion_accessory_choices

/obj/item/clothing/accessory/chameleon/proc/accessory_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.chamelion_accessory_choices[picked]))
		return

	disguise(GLOB.chamelion_accessory_choices[picked])

//*****************
//**Chameleon Gun**
//*****************
/obj/item/gun/energy/chameleon
	name = "desert eagle"
	desc = "A hologram projector in the shape of a gun. There is a dial on the side to change the gun's disguise."
	icon_state = "deagle"
	w_class = ITEMSIZE_NORMAL
	MATERIAL_NONE

	fire_sound = SFX_WEAPONS_GUNSHOT1
	projectile_type = /obj/item/projectile/chameleon
	charge_meter = 0
	charge_cost = 48 //uses next to no power, since it's just holograms
	battery_lock = 1

	var/copy_projectile	// a projectile type path

/obj/item/gun/energy/chameleon/on_materialize()
	if(!LAZYLEN(GLOB.gun_choices))
		for(var/gun_type in typesof(/obj/item/gun/) - src.type)
			var/obj/item/gun/G = gun_type
			GLOB.gun_choices[initial(G.name)] = gun_type
	. = ..()

/obj/item/gun/energy/chameleon/consume_next_projectile()
	var/obj/item/projectile/P = ..()
	var/obj/item/projectile/copy_type = copy_projectile
	if(P && ispath(copy_projectile))
		P.name = initial(copy_type.name)
		P.icon = initial(copy_type.icon)
		P.icon_state = initial(copy_type.icon_state)
		P.pass_flags = initial(copy_type.pass_flags)
		P.fire_sound = initial(copy_type.fire_sound)
		P.hitscan = initial(copy_type.hitscan)
		P.speed = initial(copy_type.speed)
		P.muzzle_type = initial(copy_type.muzzle_type)
		P.tracer_type = initial(copy_type.tracer_type)
		P.impact_type = initial(copy_type.impact_type)
	return P

/// A pulse scrambles the disguise back to its base look (the cover is blown).
/obj/item/gun/energy/chameleon/proc/chameleon_emp_reveal(datum/act/A)
	name = "desert eagle"
	desc = "It's a desert eagle."
	icon_state = "deagle"
	if (ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_r_hand()
		M.update_inv_l_hand()

/obj/item/gun/energy/chameleon/disguise(newtype)
	var/obj/item/gun/copy = ..()

	flags_inv = copy.flags_inv
	if(copy.fire_sound)
		fire_sound = copy.fire_sound
	else
		fire_sound = null
	fire_sound_text = copy.fire_sound_text

	var/obj/item/gun/G = copy
	if(istype(G))
		copy_projectile = G.projectile_type
		//charge_meter = E.charge_meter //does not work very well with icon_state changes, ATM
	else
		copy_projectile = null

CAPABILITIES(/obj/item/gun/energy/chameleon)
	on_notice(/datum/notice/hit/emp, then(PROC_REF(chameleon_emp_reveal)))
	op("energy_chameleon_change_verb", menu(), label("Change Gun Appearance"), needs(carried()), asks(/datum/prompt/choice, fields = list("question" = "Choose an appearance.", "title" = "Chameleon", "choices" = computed(PROC_REF(energy_chameleon_change_verb_a1_choices)), "timeout" = 0), step = "a1"), then(PROC_REF(energy_chameleon_change_verb)))

/// Old verb "Change Gun Appearance".
/obj/item/gun/energy/chameleon/proc/energy_chameleon_change_verb_a1_choices(datum/act/op/A)
	return GLOB.gun_choices

/obj/item/gun/energy/chameleon/proc/energy_chameleon_change_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/picked = A.step_value("a1")
	if(get(src, /mob) != user)
		return
	if(!ispath(GLOB.gun_choices[picked]))
		return

	disguise(GLOB.gun_choices[picked])

	//so our overlays update.
	if (ismob(src.loc))
		var/mob/M = src.loc
		M.update_inv_r_hand()
		M.update_inv_l_hand()
