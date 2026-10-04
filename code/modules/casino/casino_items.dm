/obj/item/storage/wallet/casino
	name = "casino wallet"
	desc = "A fancy casino wallet with flashy lights, oooh~"
	icon = 'icons/obj/casino_ch.dmi'
	icon_state = "casinowallet_black"


CAPABILITIES(/obj/item/storage/wallet/casino)
	configure(storage(accepts = list(
		/obj/item/spacecash,
		/obj/item/card,
		/obj/item/clothing/mask/smokable/cigarette/,
		/obj/item/flashlight/pen,
		/obj/item/tape,
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
		/obj/item/spacecasinocash,
		/obj/item/casino_platinum_chip,
		/obj/item/deck,
		/obj/item/book/codex/casino,
		/obj/item/storage/pill_bottle/dice,
		/obj/item/storage/pill_bottle/dice_nerd,
		/obj/item/storage/dicecup/loaded)))
	op("casino_toggle_design_effect", menu(), label("Toggle design"), needs(carried()), then(PROC_REF(casino_toggle_design_effect)))

/obj/item/storage/wallet/casino/proc/casino_toggle_design_effect(datum/act/op/A)

	if (icon_state == "casinowallet_black")
		icon_state = "casinowallet_brown"
		return
	if (icon_state == "casinowallet_brown")
		icon_state = "casinowallet_white"
		return
	else
		icon_state = "casinowallet_black"

/obj/structure/stripper_pole
	name = "stripper pole"
	icon = 'icons/obj/casino_ch.dmi'
	icon_state = "stripper_pole"
	plane = MOB_PLANE
	layer = BELOW_MOB_LAYER
	density = 0

CAPABILITIES(/obj/structure/stripper_pole)
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/stripper_pole/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	dance(user)
	user.spin(32,2)
	return OP_DECLINE

/obj/structure/stripper_pole/proc/dance(mob/user)
	if(layer == BELOW_MOB_LAYER)
		layer = ABOVE_MOB_LAYER
	else
		layer = BELOW_MOB_LAYER

/// Old object verbs.
