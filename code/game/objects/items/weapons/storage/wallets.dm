/obj/item/storage/wallet
	name = "wallet"
	desc = "It can hold a few small and personal things."
	storage_slots = 10
	icon = 'icons/obj/wallet.dmi'
	icon_state = "wallet-orange"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_ID

	var/obj/item/card/id/front_id

	drop_sound = SFX_ITEMS_DROP_LEATHER
	pickup_sound = SFX_ITEMS_PICKUP_LEATHER

	var/original_name // Due to loadout customizations and such


CAPABILITIES(/obj/item/storage/wallet)
	configure(storage(accepts = list(
		/obj/item/spacecash,
		/obj/item/card,
		/obj/item/clothing/mask/smokable/cigarette/,
		/obj/item/flashlight/pen,
		/obj/item/rectape,
		/obj/item/cartridge,
		/obj/item/encryptionkey,
		/obj/item/seeds,
		/obj/item/stack/medical,
		/obj/item/coin,
		/obj/item/dice,
		/obj/item/disk,
		/obj/item/implanter,
		/obj/item/flame/lighter,
		/obj/item/flame/match,
		/obj/item/forensics,
		/obj/item/glass_extra,
		/obj/item/haircomb,
		/obj/item/hand,
		/obj/item/key,
		/obj/item/lipstick,
		/obj/item/paper,
		/obj/item/pen,
		/obj/item/photo,
		/obj/item/reagent_containers/dropper,
		/obj/item/sample,
		/obj/item/tool/screwdriver,
		/obj/item/stamp,
		/obj/item/clothing/accessory/permit,
		/obj/item/clothing/accessory/badge,
		/obj/item/makeover,
		/obj/item/pizzavoucher,
		/obj/item/card_fluff)))

/obj/item/storage/wallet/remove_from_storage(obj/item/W, atom/new_location, mob/user)
	. = ..()
	if(.)
		if(W == front_id())
			rel_clear(src, nameof(front_id))
			name = original_name || initial(name)

/obj/item/storage/wallet/insert_item(obj/item/W, mob/user, prevent_warning = FALSE)
	. = ..()
	if(.)
		if(!front_id() && istype(W, /obj/item/card/id))
			rel_set(src, nameof(front_id), W)
			if(!original_name)
				original_name = name
			name = "[original_name] ([front_id()])"

/obj/item/storage/wallet/draw(datum/look/look)
	. = ..()
	look.overlay(id_overlay())

/// The small picture of the ID at the front of the wallet, or null.
/obj/item/storage/wallet/proc/id_overlay()
	var/obj/item/card/id/front = front_id()
	if(!front)
		return null
	var/tiny_state = "id-generic"
	if(icon_exists(icon, "id-[front.icon_state]"))
		tiny_state = "id-[front.icon_state]"
	var/image/tiny_image = new/image(icon, icon_state = tiny_state)
	tiny_image.appearance_flags = RESET_COLOR
	return tiny_image

READS_AS(/obj/item/storage/wallet/proc/id_overlay, STORAGE_CONTENTS_KEY)

/obj/item/storage/wallet/GetID()
	return front_id()

/obj/item/storage/wallet/GetAccess()
	var/obj/item/I = GetID()
	if(I)
		return I.GetAccess()
	else
		return ..()

/obj/item/storage/wallet/random/Initialize(mapload)
	. = ..()
	var/amount = rand(50, 100) + rand(50, 100) // Triangular distribution from 100 to 200
	var/obj/item/spacecash/SC = null
	SC = new(src)
	for(var/i in list(100, 50, 20, 10, 5, 1))
		if(amount < i)
			continue
		while(amount >= i)
			amount -= i
			SC.adjust_worth(i, 0)
		SC.update_icon()

/obj/item/storage/wallet/poly
	name = "polychromic wallet"
	desc = "You can recolor it! Fancy! The future is NOW!"
	icon_state = "wallet-white"

// The colour is chosen from a window: an op of the wallet, reached from the verb a carrier has.
CAPABILITIES(/obj/item/storage/wallet/poly)
	held_verb(/obj/item/storage/wallet/poly/proc/change_color, SLOT_ANY_CARRIED)
	op("recolor", menu(), needs(carried(), req_capable()), label("Change wallet color"),
		asks(/datum/prompt/color, fields = list("question" = "Pick a new color", "title" = "Wallet Color", "default" = nameof(color))),
		then(PROC_REF(recolored)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(poly_wallet_emp)))

/obj/item/storage/wallet/poly/Initialize(mapload)
	. = ..()
	color = get_random_colour()

/obj/item/storage/wallet/poly/proc/change_color()
	set name = "Change Wallet Color"
	set category = VERB_CAT_OBJECT
	set desc = "Change the color of the wallet."
	set src in usr

	perform_op(usr, src, "recolor", null, ORIGIN_VERB)

/// The picked colour becomes the wallet's.
/obj/item/storage/wallet/poly/proc/recolored(datum/act/op/A)
	var/datum/prompt/color/picked = A.answer
	if(picked.value != color)
		color = picked.value
	return OP_OK

/// An EMP glitches the wallet's colour display for a while.
/obj/item/storage/wallet/poly/proc/poly_wallet_emp(datum/act/A)
	var/original_state = icon_state
	icon_state = "wallet-emp"

	after(src, 20 SECONDS, PROC_REF(emp_recovered), with = list(original_state))

/obj/item/storage/wallet/womens
	name = "women's wallet"
	desc = "A stylish wallet typically used by women."
	icon_state = "girl_wallet"
	item_state_slots = list(slot_r_hand_str = "wowallet", slot_l_hand_str = "wowallet")

/obj/item/storage/wallet/poly/proc/emp_recovered(original_state)
	if(src)
		icon_state = original_state

/// Relation view: front id (reads null once it is gone).
/obj/item/storage/wallet/proc/front_id() as /obj/item/card/id
	return front_id
