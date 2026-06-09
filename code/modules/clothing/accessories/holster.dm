/obj/item/clothing/accessory/holster
	name = "shoulder holster"
	desc = "A handgun holster."
	icon_state = "holster"
	slot = ACCESSORY_SLOT_WEAPON
	concealed_holster = 1
	var/obj/item/holstered = null
	var/list/can_hold
	var/holster_in = 'sound/items/holsterin.ogg'
	var/holster_out = 'sound/items/holsterout.ogg'
	w_class = ITEMSIZE_NORMAL

/obj/item/clothing/accessory/holster/proc/holster(obj/item/I, mob/living/user)
	if(holstered && istype(user))
		to_chat(user, span_warning("There is already \a [holstered] holstered here!"))
		return
	// Machete sheath support
	if (LAZYLEN(can_hold))
		if(!is_type_in_list(I,can_hold))
			to_chat(user, span_warning("[I] won't fit in [src]!"))
			return

	else if (!(I.slot_flags & SLOT_HOLSTER))
		to_chat(user, span_warning("[I] won't fit in [src]!"))
		return

	if(holster_in)
		playsound(src, holster_in, 50)

	if(istype(user))
		user.stop_aiming(no_message=1)
	holstered = I
	user.drop_from_inventory(holstered, target = src)
	holstered.add_fingerprint(user)
	w_class = max(w_class, holstered.w_class)
	user.visible_message(span_notice("[user] holsters \the [holstered]."), span_notice("You holster \the [holstered]."))
	name = "occupied [initial(name)]"

/obj/item/clothing/accessory/holster/proc/clear_holster()
	holstered = null
	name = initial(name)

/obj/item/clothing/accessory/holster/proc/unholster(mob/user)
	if(!holstered)
		return

	if(istype(user.get_active_hand(),/obj) && istype(user.get_inactive_hand(),/obj))
		to_chat(user, span_warning("You need an empty hand to draw \the [holstered]!"))
	else
		// begin
		if(iscarbon(user))
			var/mob/living/carbon/C = user
			if(C.handcuffed)
				to_chat(C, span_warning("You cannot draw \the [holstered] while handcuffed!"))
				return
			else if(istype(C, /mob/living/carbon/human))
				var/mob/living/carbon/human/H = C
				if(H.ability_flags & 0x1)
					to_chat(H, span_warning("You cannot draw \the [holstered] while phase shifted!"))
					return
		// end
		var/sound_vol = 25
		if(user.a_intent == I_HURT)
			sound_vol = 50
			user.visible_message(
				span_danger("[user] draws \the [holstered], ready to go!"),
				span_warning("You draw \the [holstered], ready to go!")
				)
		else
			user.visible_message(
				span_notice("[user] draws \the [holstered], pointing it at the ground."),
				span_notice("You draw \the [holstered], pointing it at the ground.")
				)

		if(holster_out)
			playsound(src, holster_out, sound_vol)

		user.put_in_hands(holstered)
		holstered.add_fingerprint(user)
		w_class = initial(w_class)
		clear_holster()

//YW change start
/obj/item/clothing/accessory/holster/attack_hand(mob/user)
	if (user.a_intent == I_HURT && has_suit && (slot & SLOT_HOLSTER ))	//if we are part of a suit and are using harm intent
		if (holstered)
			unholster(user)
		return

	..(user)
//YW change end

/obj/item/clothing/accessory/holster/attackby(obj/item/W as obj, mob/user as mob)
	holster(W, user)

/obj/item/clothing/accessory/holster/examine(mob/user)
	. = ..(user)
	if(holstered)
		. += "A [holstered] is holstered here."
	else
		. += "It is empty."

/obj/item/clothing/accessory/holster/on_attached(obj/item/clothing/under/S, mob/user as mob)
	..()
	if(has_suit)
		has_suit.verbs += /obj/item/clothing/accessory/holster/verb/holster_verb

/obj/item/clothing/accessory/holster/on_removed(mob/user as mob)
	if(has_suit)
		has_suit.verbs -= /obj/item/clothing/accessory/holster/verb/holster_verb
	..()

//For the holster hotkey
/obj/item/clothing/accessory/holster/verb/holster_verb()
	set name = "Holster"
	set category = "Object"
	set src in usr
	if(!isliving(usr)) return
	if(usr.stat) return

	//can't we just use src here?
	var/obj/item/clothing/accessory/holster/H = null
	if (istype(src, /obj/item/clothing/accessory/holster))
		H = src
	else if (istype(src, /obj/item/clothing/under))
		var/obj/item/clothing/under/S = src
		if (LAZYLEN(S.accessories))
			H = locate() in S.accessories

	if (!H)
		to_chat(usr, span_warning("Something is very wrong."))

	if(!H.holstered)
		var/obj/item/W = usr.get_active_hand()
		if(!istype(W, /obj/item))
			to_chat(usr, span_warning("You need your gun equipped to holster it."))
			return
		H.holster(W, usr)
	else
		H.unholster(usr)

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


// === merged from holster_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/accessory/holster/waist/kinetic_accelerator
	name = "KA holster"
	desc = "A specialized holster, made specifically for Kinetic Accelerators."
	can_hold = list(/obj/item/gun/energy/kinetic_accelerator)

/obj/item/clothing/accessory/holster/waist/lanyard
	name = "baton lanyard"
	desc = "A sturdy tether with quick-release carabiner that can keep several patterns of standard-issue security baton ready for quick usage."
	icon_state = "holster_lanyard"
	overlay_state = "holster_lanyard"
	can_hold = list(
		/obj/item/melee/baton,
		/obj/item/melee/classic_baton,
		/obj/item/melee/telebaton
		)

/obj/item/clothing/accessory/holster/machete/rapier
	name = "rapier sheath"
	desc = "A beautiful red sheath, probably for a beautiful blade."
	icon_state = "sheath"
	slot_flags = SLOT_BELT|ACCESSORY_SLOT_WEAPON
	var/has_full_icon = 1
	overlay_state = "sheath"
	can_hold = list(/obj/item/melee/rapier)

/obj/item/clothing/accessory/holster/machete/rapier/swords
	name = "sword sheath"
	desc = "A beautiful red sheath, probably for a beautiful blade."
	can_hold = list(
		/obj/item/melee/rapier,
		/obj/item/material/sword/katana,
		/obj/item/toy/cultsword,
		/obj/item/material/sword,
		/obj/item/melee/cursedblade,
		/obj/item/melee/cultblade
		)

/obj/item/clothing/accessory/holster/machete/rapier/proc/occupied()
	if(!has_full_icon)
		return
	if(contents.len)
		overlay_state = "[initial(overlay_state)]-rapier"
	else
		overlay_state = initial(overlay_state)

/obj/item/clothing/accessory/holster/machete/rapier/swords/occupied()
	if(!has_full_icon)
		return
	if(contents.len)
		overlay_state = "[initial(overlay_state)]-secondary"
	else
		overlay_state = initial(overlay_state)

/obj/item/clothing/accessory/holster/machete/rapier/holster(obj/item/I, mob/living/user)
	..()
	occupied()
	if(has_suit)
		has_suit.update_clothing_icon()

/obj/item/clothing/accessory/holster/machete/rapier/unholster(obj/item/I, mob/living/user)
	..()
	occupied()
	if(has_suit)
		has_suit.update_clothing_icon()


// === merged from holster_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
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
	can_hold = list(/obj/item/instrument)
