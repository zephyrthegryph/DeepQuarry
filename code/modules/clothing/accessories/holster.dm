/obj/item/clothing/accessory/holster
	name = "shoulder holster"
	desc = "A handgun holster."
	icon_state = "holster"
	slot = ACCESSORY_SLOT_WEAPON
	concealed_holster = 1
	var/obj/item/holstered = null // owned: the holstered item, kept in the holster's contents
	var/holster_in = SFX_ITEMS_HOLSTERIN
	var/holster_out = SFX_ITEMS_HOLSTEROUT
	w_class = ITEMSIZE_NORMAL

/// Holsters take holsterable things; sheaths and special holsters list what they take.
TYPE_TABLE(/obj/item/clothing/accessory/holster, hold_spec, list(REQ_BECAUSE(REQ_TAG(PRED_TARGET, TAG_HOLSTERABLE), "it isn't made for a holster")))

/obj/item/clothing/accessory/holster/proc/holster(obj/item/I, mob/living/user)
	if(holstered && istype(user))
		to_chat(user, span_warning("There is already \a [holstered] holstered here!"))
		return
	if(dq_constraint_refusal(src, CONSTRAINT_HOLD, I, user))
		to_chat(user, span_warning("[I] won't fit in [src]!"))
		return

	if(holster_in)
		playsound(src, holster_in, 50)

	if(istype(user))
		user.stop_aiming(no_message=1)
	if(!move_into(src, nameof(src.holstered), I, user))
		return
	holstered.add_fingerprint(user)
	w_class = max(w_class, holstered.w_class)
	act_message(user, null, MSG_SELF(span_notice("You holster \the [holstered].")), MSG_OTHERS(span_notice("%U% holsters \the [holstered].")))
	name = "occupied [initial(name)]"

/obj/item/clothing/accessory/holster/proc/clear_holster()
	rel_take(src, nameof(holstered))
	name = initial(name)

/// Draws the holstered item; `stance` I_HURT draws it ready to fire.
/obj/item/clothing/accessory/holster/proc/unholster(mob/user, stance = I_HELP)
	if(!holstered)
		return

	if(istype(user.get_active_hand(),/obj) && istype(user.get_inactive_hand(),/obj))
		to_chat(user, span_warning("You need an empty hand to draw \the [holstered]!"))
	else
		// begin
		if(iscarbon(user))
			var/mob/living/carbon/C = user
			if(C.get_equipped_item(SLOT_ID_HANDCUFFED))
				to_chat(C, span_warning("You cannot draw \the [holstered] while handcuffed!"))
				return
			else if(istype(C, /mob/living/carbon/human))
				var/mob/living/carbon/human/H = C
				if(H.ability_flags & 0x1)
					to_chat(H, span_warning("You cannot draw \the [holstered] while phase shifted!"))
					return
		// end
		var/sound_vol = 25
		if(stance == I_HURT)
			sound_vol = 50
			act_message(user, null, MSG_SELF(span_warning("You draw \the [holstered], ready to go!")), \
				MSG_OTHERS(span_danger("%U% draws \the [holstered], ready to go!")))
		else
			act_message(user, null, MSG_SELF(span_notice("You draw \the [holstered], pointing it at the ground.")), \
				MSG_OTHERS(span_notice("%U% draws \the [holstered], pointing it at the ground.")))

		if(holster_out)
			playsound(src, holster_out, sound_vol)

		user.put_in_hands(holstered)
		holstered.add_fingerprint(user)
		w_class = initial(w_class)
		clear_holster()

//YW change start
CAPABILITIES(/obj/item/clothing/accessory/holster)
	op("holster_draw_hand", hand(), ungated(), stance(I_HURT), priority(OP_PRIORITY_DEFAULT - 1), label("Draw"), then(PROC_REF(holster_draw_hand)))
	op("holster_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Holster item"), then(PROC_REF(holster_item)))
	op("holster_quick_holster_verb", menu(), label("Holster"), needs(carried()), then(PROC_REF(holster_quick_holster_verb)))

/// Old attack_hand: draw from an attached holster in combat mode.
/obj/item/clothing/accessory/holster/proc/holster_draw_hand(datum/act/op/A)
	var/mob/user = A.actor
	if (has_suit() && (slot & SLOT_HOLSTER ))	//if we are part of a suit
		if (holstered)
			unholster(user, I_HURT)
		return OP_OK
	return OP_DECLINE
//YW change end

/// Old attackby: holster the item.
/obj/item/clothing/accessory/holster/proc/holster_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	holster(W, user)
	return OP_PASS

/obj/item/clothing/accessory/holster/examine(mob/user)
	. = ..(user)
	if(holstered)
		. += "A [holstered] is holstered here."
	else
		. += "It is empty."

// The uniform it is attached to offers "Holster" too (/obj/item/clothing/under, clothing.dm).
/// Old verb "Holster".
/obj/item/clothing/accessory/holster/proc/holster_quick_holster_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(user)) return
	if(user.stat) return

	var/obj/item/clothing/accessory/holster/H = src
	if(!H.holstered)
		var/obj/item/W = user.get_active_hand()
		if(!istype(W, /obj/item))
			to_chat(user, span_warning("You need your gun equipped to holster it."))
			return
		H.holster(W, user)
	else
		H.unholster(user, I_HELP)

/obj/item/clothing/accessory/holster/armpit
	name = "armpit holster"
	desc = "A worn-out handgun holster. Perfect for concealed carry"
	icon_state = "holster"

/obj/item/clothing/accessory/holster/armpit/black
	name = "black armpit holster" // Loaodut bugfix
	icon_state = "holster_b"

/obj/item/clothing/accessory/holster/waist
	name = "waist holster"
	desc = "A handgun holster. Made of expensive leather."
	icon_state = "holster"
	overlay_state = "holster_low"
	concealed_holster = 0

/obj/item/clothing/accessory/holster/waist/black
	name = "black waist holster" // Loadout bugfix
	icon_state = "holster_b_low"
	overlay_state = "holster_b_low"

/obj/item/clothing/accessory/holster/hip
	name = "hip holster"
	desc = span_italics("No one dared to ask his business, no one dared to make a slip. The stranger there among them had a big iron on his hip.")
	icon_state = "holster_hip"
	concealed_holster = 0

/obj/item/clothing/accessory/holster/hip/black
	name = "black hip holster" // Loadout bugfix
	desc = "A handgun holster slung low on the hip, draw pardner!"
	icon_state = "holster_b_hip"

/obj/item/clothing/accessory/holster/leg
	name = "leg holster"
	desc = "A drop leg holster made of a durable synthetic leather."
	icon_state = "holster_leg"
	overlay_state = "holster_leg"
	concealed_holster = 0

/obj/item/clothing/accessory/holster/leg/black
	name = "black leg holster" // Loadout bugfix
	desc = "A tacticool handgun holster. Worn on the upper leg."
	icon_state = "holster_b_leg"
	overlay_state = "holster_b_leg"


/obj/item/clothing/accessory/holster/waist/kinetic_accelerator
	name = "KA holster"
	desc = "A specialized holster, made specifically for Kinetic Accelerators."

TYPE_TABLE(/obj/item/clothing/accessory/holster/waist/kinetic_accelerator, hold_spec, list(HOLD_ONLY(list(/obj/item/gun/energy/kinetic_accelerator))))

/obj/item/clothing/accessory/holster/waist/lanyard
	name = "baton lanyard"
	desc = "A sturdy tether with quick-release carabiner that can keep several patterns of standard-issue security baton ready for quick usage."
	icon_state = "holster_lanyard"
	overlay_state = "holster_lanyard"

TYPE_TABLE(/obj/item/clothing/accessory/holster/waist/lanyard, hold_spec, list(HOLD_ONLY(list( \
		/obj/item/melee/baton, \
		/obj/item/melee/classic_baton, \
		/obj/item/melee/telebaton \
		))))

/obj/item/clothing/accessory/holster/machete/rapier
	name = "rapier sheath"
	desc = "A beautiful red sheath, probably for a beautiful blade."
	icon_state = "sheath"
	slot_flags = SLOT_BELT|ACCESSORY_SLOT_WEAPON
	var/has_full_icon = 1
	overlay_state = "sheath"

TYPE_TABLE(/obj/item/clothing/accessory/holster/machete/rapier, hold_spec, list(HOLD_ONLY(list(/obj/item/melee/rapier))))

/obj/item/clothing/accessory/holster/machete/rapier/swords
	name = "sword sheath"
	desc = "A beautiful red sheath, probably for a beautiful blade."

TYPE_TABLE(/obj/item/clothing/accessory/holster/machete/rapier/swords, hold_spec, list(HOLD_ONLY(list( \
		/obj/item/melee/rapier, \
		/obj/item/material/sword/katana, \
		/obj/item/toy/cultsword, \
		/obj/item/material/sword, \
		/obj/item/melee/cursedblade, \
		/obj/item/melee/cultblade \
		))))

/obj/item/clothing/accessory/holster/machete/rapier/proc/occupied()
	if(!has_full_icon)
		return
	if(contents_count(src))
		overlay_state = "[initial(overlay_state)]-rapier"
	else
		overlay_state = initial(overlay_state)

/obj/item/clothing/accessory/holster/machete/rapier/swords/occupied()
	if(!has_full_icon)
		return
	if(contents_count(src))
		overlay_state = "[initial(overlay_state)]-secondary"
	else
		overlay_state = initial(overlay_state)

/obj/item/clothing/accessory/holster/machete/rapier/holster(obj/item/I, mob/living/user)
	..()
	occupied()
	if(has_suit())
		has_suit().update_clothing_icon()

/obj/item/clothing/accessory/holster/machete/rapier/unholster(mob/user, stance = I_HELP)
	..()
	occupied()
	if(has_suit())
		has_suit().update_clothing_icon()


/obj/item/clothing/accessory/holster/leg/left
	name = "left leg holster"
	desc = "A drop leg holster made of a durable synthetic leather, fitted for your left leg."
	icon_state = "holster_leg"
	overlay_state = "holster_leg"
	concealed_holster = 0

/obj/item/clothing/accessory/holster/leg/left/black
	name = "black left leg holster"
	desc = "A drop leg holster made of black leather, fitted for your left leg."
	icon_state = "holster_b_leg"
	overlay_state = "holster_b_leg"
	concealed_holster = 0

/obj/item/clothing/accessory/holster/case
	name = "instrument case"
	desc = "A case for keeping your instrument safe."
	icon = 'icons/inventory/accessory/item.dmi'
	icon_state = "instrument"
	concealed_holster = 0

TYPE_TABLE(/obj/item/clothing/accessory/holster/case, hold_spec, list(HOLD_ONLY(list(/obj/item/instrument))))

/obj/item/clothing/accessory/holster/ownership()
	. = ..()
	. += owns(nameof(holstered), policy = OWN_CONTAINED)
