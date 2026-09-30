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

TYPE_TABLE(/obj/item/storage/wallet, hold_spec, list(HOLD_ONLY(list( \
		/obj/item/spacecash, \
		/obj/item/card, \
		/obj/item/clothing/mask/smokable/cigarette/, \
		/obj/item/flashlight/pen, \
		/obj/item/rectape, \
		/obj/item/cartridge, \
		/obj/item/encryptionkey, \
		/obj/item/seeds, \
		/obj/item/stack/medical, \
		/obj/item/coin, \
		/obj/item/dice, \
		/obj/item/disk, \
		/obj/item/implanter, \
		/obj/item/flame/lighter, \
		/obj/item/flame/match, \
		/obj/item/forensics, \
		/obj/item/glass_extra, \
		/obj/item/haircomb, \
		/obj/item/hand, \
		/obj/item/key, \
		/obj/item/lipstick, \
		/obj/item/paper, \
		/obj/item/pen, \
		/obj/item/photo, \
		/obj/item/reagent_containers/dropper, \
		/obj/item/sample, \
		/obj/item/tool/screwdriver, \
		/obj/item/stamp, \
		/obj/item/clothing/accessory/permit, \
		/obj/item/clothing/accessory/badge, \
		/obj/item/makeover, \
		/obj/item/pizzavoucher, \
		/obj/item/card_fluff \
		)), HOLD_MAX_SIZE(ITEMSIZE_SMALL)))

/obj/item/storage/wallet/remove_from_storage(obj/item/W, atom/new_location, mob/user)
	. = ..()
	if(.)
		if(W == front_id())
			rel_clear(src, nameof(front_id))
			name = original_name || initial(name)
			update_icon()

/obj/item/storage/wallet/insert_item(obj/item/W, mob/user, prevent_warning = FALSE)
	. = ..()
	if(.)
		if(!front_id() && istype(W, /obj/item/card/id))
			rel_set(src, nameof(front_id), W)
			if(!original_name)
				original_name = name
			name = "[original_name] ([front_id()])"
			update_icon()

DECLARE_APPEARANCE_PROC(/obj/item/storage/wallet, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/storage/wallet/appearance_overlays()
	. = list()
	if(front_id())
		var/tiny_state = "id-generic"
		if(icon_exists(icon, "id-[front_id().icon_state]"))
			tiny_state = "id-"+front_id().icon_state
		var/image/tiny_image = new/image(icon, icon_state = tiny_state)
		tiny_image.appearance_flags = RESET_COLOR
		. += tiny_image

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

DECLARE_VERB(/obj/item/storage/wallet/poly, /obj/item/storage/wallet/poly/proc/change_color)

/obj/item/storage/wallet/poly/Initialize(mapload)
	. = ..()
	color = get_random_colour()
	update_icon()

/obj/item/storage/wallet/poly/proc/change_color()
	set name = "Change Wallet Color"
	set category = VERB_CAT_OBJECT
	set desc = "Change the color of the wallet."
	set src in usr

	if(usr.stat || usr.restrained() || usr.incapacitated())
		return

	om_ask(usr, /datum/om/prompt/color, PROC_REF(wallet_color_chosen), title = "Wallet Color", message = "Pick a new color", default = color, ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/storage/wallet/poly/proc/wallet_color_chosen(datum/om/prompt/color/ask)
	if(ask.picked_color && (ask.picked_color != color))
		color = ask.picked_color

DAMAGE_REACTION(/obj/item/storage/wallet/poly, DAMAGE_EMP, PROC_REF(poly_wallet_emp))
/// An EMP glitches the wallet's colour display for a while.
/obj/item/storage/wallet/poly/proc/poly_wallet_emp(datum/damage_packet/packet)
	var/original_state = icon_state
	icon_state = "wallet-emp"
	update_icon()

	om_after(src, 20 SECONDS, PROC_REF(emp_recovered), original_state)

/obj/item/storage/wallet/womens
	name = "women's wallet"
	desc = "A stylish wallet typically used by women."
	icon_state = "girl_wallet"
	item_state_slots = list(slot_r_hand_str = "wowallet", slot_l_hand_str = "wowallet")

/obj/item/storage/wallet/poly/proc/emp_recovered(original_state)
	if(src)
		icon_state = original_state
		update_icon()

/// Relation view: front id (reads null once it is gone).
/obj/item/storage/wallet/proc/front_id() as /obj/item/card/id
	return front_id
