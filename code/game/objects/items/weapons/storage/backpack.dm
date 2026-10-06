/*
 * Backpack
 */

/obj/item/storage/backpack
	name = "backpack"
	desc = "You wear this on your back and put items into it."
	icon = 'icons/inventory/back/item.dmi'
	icon_state = "backpack"
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/back/mob_teshari.dmi',
		SPECIES_WEREBEAST = 'icons/inventory/back/mob_werebeast.dmi'
		)
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BACK
	max_storage_space = INVENTORY_STANDARD_SPACE
	var/flippable = 0
	var/side = 0 //0 = right, 1 = left
	drop_sound = SFX_ITEMS_DROP_BACKPACK
	pickup_sound = SFX_ITEMS_PICKUP_BACKPACK



CAPABILITIES(/obj/item/storage/backpack)
	configure(storage(max_size = ITEMSIZE_LARGE))

/obj/item/storage/backpack/equipped(mob/user, slot)
	if (slot == SLOT_ID_BACK && src.use_sound)
// Chomp edit
		if(isbelly(user.loc))
			var/obj/belly/B = user.loc
			if(B.mode_flags & DM_FLAG_MUFFLEITEMS)
				return
		else
// Chomp edit end
			playsound(src, src.use_sound, 50, 1, -5)

	..(user, slot)

/*
/obj/item/storage/backpack/dropped(mob/user, equipping, slot)
	if (loc == user && src.use_sound)
		if(isbelly(user.loc))
			var/obj/belly/B = user.loc
			if(B.mode_flags & DM_FLAG_MUFFLEITEMS)
				return
		else
			playsound(src, src.use_sound, 50, 1, -5)
	..(user)
*/

/*
 * Backpack Types
 */

/obj/item/storage/backpack/holding
	name = "bag of holding"
	desc = "A backpack that opens into a localized pocket of Blue Space."
	icon_state = "holdingpack"
	max_storage_space = ITEMSIZE_COST_NORMAL * 14 // 56
	storage_cost = INVENTORY_STANDARD_SPACE + 1


/obj/item/storage/backpack/holding/duffle
	name = "dufflebag of holding"
	var/tilted = 0
	icon_state = "holdingduffle"

/// Rolled before init (rolls()): half the bags lie tilted.
/obj/item/storage/backpack/holding/duffle/proc/roll_tilted_look(datum/roller/R)
	return tilted ? "[icon_state]_tilted" : icon_state

CAPABILITIES(/obj/item/storage/backpack/holding/duffle)
	op("tilt", menu(), label("Adjust Duffelbag Angle"), needs(carried()), then(PROC_REF(duffle_tilt_effect)))
	rolls(nameof(tilted), chance(50))
	rolls(nameof(icon_state), PROC_REF(roll_tilted_look), from = list(nameof(tilted)))

/obj/item/storage/backpack/holding/duffle/proc/duffle_tilt_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return OP_REFUSED
	if(tilted)
		icon_state = "[initial(icon_state)]"
		to_chat(user, "You adjust the angle of \the [src] to rest across your lower back.")
		tilted = 0
	else
		icon_state = "[icon_state]_tilted"
		to_chat(user, "You adjust the angle of \the [src] to rest diagonally across your back.")
		tilted = 1
	user.update_inv_back()
	return OP_OK

CAPABILITIES(/obj/item/storage/backpack/holding)
	configure(storage(refuses = list(/obj/item/storage/backpack/holding)))
	op("conflict", item(/obj/item/storage/backpack/holding), label("Put in"), then(PROC_REF(bluespace_conflict)))

/// Two bags of holding destroy the one put in.
/obj/item/storage/backpack/holding/proc/bluespace_conflict(datum/act/op/A)
	to_chat(A.actor, span_warning("The Bluespace interfaces of the two devices conflict and malfunction."))
	consume(A.held, A.actor)
	return OP_OK

/obj/item/storage/backpack/cultpack
	name = "trophy rack"
	desc = "It's useful for both carrying extra gear and proudly declaring your insanity."
	icon_state = "backpack_cult"

/obj/item/storage/backpack/clown
	name = "Giggles von Honkerton"
	desc = "It's a backpack made by Honk! Co."
	icon_state = "backpack_clown"

/obj/item/storage/backpack/white
	name = "white backpack"
	icon_state = "backpack_white"

/obj/item/storage/backpack/fancy
	name = "fancy backpack"
	icon_state = "backpack_fancy"

/obj/item/storage/backpack/military
	name = "military backpack"
	icon_state = "backpack_military"

/obj/item/storage/backpack/medic
	name = "medical backpack"
	desc = "It's a backpack especially designed for use in a sterile environment."
	icon_state = "backpack_medical"

/obj/item/storage/backpack/security
	name = "security backpack"
	desc = "It's a very robust backpack."
	icon_state = "backpack_security"

/obj/item/storage/backpack/captain
	name = "site manager's backpack"
	desc = "It's a special backpack made exclusively for officers."
	icon_state = "backpack_captain"

/obj/item/storage/backpack/industrial
	name = "industrial backpack"
	desc = "It's a tough backpack for the daily grind of station life."
	icon_state = "backpack_industrial"

/obj/item/storage/backpack/toxins
	name = "laboratory backpack"
	desc = "It's a light backpack modeled for use in laboratories and other scientific institutions."
	icon_state = "backpack_purple"

/obj/item/storage/backpack/hydroponics
	name = "herbalist's backpack"
	desc = "It's a green backpack with many pockets to store plants and tools in."
	icon_state = "backpack_hydro"

/obj/item/storage/backpack/genetics
	name = "geneticist backpack"
	desc = "It's a backpack fitted with slots for diskettes and other workplace tools."
	icon_state = "backpack_blue"

/obj/item/storage/backpack/virology
	name = "sterile backpack"
	desc = "It's a sterile backpack able to withstand different pathogens from entering its fabric."
	icon_state = "backpack_green"

/obj/item/storage/backpack/chemistry
	name = "chemistry backpack"
	desc = "It's an orange backpack which was designed to hold beakers, pill bottles and bottles."
	icon_state = "backpack_orange"

/*
 * Duffle Types
 */

/obj/item/storage/backpack/dufflebag
	name = "dufflebag"
	desc = "A large dufflebag for holding extra things."
	icon_state = "duffle"
	slowdown = 0.5
	var/tilted = 0
	var/can_tilt = 1
	max_storage_space = INVENTORY_DUFFLEBAG_SPACE

/// Rolled before init (rolls()): half the bags lie tilted.
/obj/item/storage/backpack/dufflebag/proc/roll_tilted_look(datum/roller/R)
	return tilted ? "[icon_state]_tilted" : icon_state

MSG_DEF_SELF(backpack/cant_tilt, "It can't be adjusted like that.")

CAPABILITIES(/obj/item/storage/backpack/dufflebag)
	op("tilt", menu(), label("Adjust Duffelbag Angle"), needs(carried(), req(PROC_REF(can_adjust_tilt), because = MSG(backpack/cant_tilt))), then(PROC_REF(dufflebag_tilt_effect)))
	rolls(nameof(tilted), chance(50))
	rolls(nameof(icon_state), PROC_REF(roll_tilted_look), from = list(nameof(tilted)))

/// Only some duffelbags tilt.
/obj/item/storage/backpack/dufflebag/proc/can_adjust_tilt(datum/act/op/A)
	return can_tilt

/obj/item/storage/backpack/dufflebag/proc/dufflebag_tilt_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return OP_REFUSED
	if(tilted)
		icon_state = "[initial(icon_state)]"
		to_chat(user, "You adjust the angle of \the [src] to rest across your lower back.")
		tilted = 0
	else
		icon_state = "[icon_state]_tilted"
		to_chat(user, "You adjust the angle of \the [src] to rest diagonally across your back.")
		tilted = 1
	user.update_inv_back()
	return OP_OK

/obj/item/storage/backpack/dufflebag/syndie
	name = "black dufflebag"
	desc = "A large dufflebag for holding extra tactical supplies. This one appears to be made out of lighter material than usual."
	icon_state = "duffle_syndie"
	slowdown = 0

/obj/item/storage/backpack/dufflebag/syndie/med
	name = "medical dufflebag"
	desc = "A large dufflebag for holding extra tactical medical supplies. This one appears to be made out of lighter material than usual."
	icon_state = "duffle_syndiemed"

/obj/item/storage/backpack/dufflebag/syndie/ammo
	name = "ammunition dufflebag"
	desc = "A large dufflebag for holding extra weapons ammunition and supplies. This one appears to be made out of lighter material than usual."
	icon_state = "duffle_syndieammo"

/obj/item/storage/backpack/dufflebag/captain
	name = "site manager's dufflebag"
	desc = "A large dufflebag for holding extra captainly goods."
	icon_state = "duffle_captain"

/obj/item/storage/backpack/dufflebag/med
	name = "medical dufflebag"
	desc = "A large dufflebag for holding extra medical supplies."
	icon_state = "duffle_medical"

/obj/item/storage/backpack/dufflebag/emt
	name = "EMT dufflebag"
	desc = "A large dufflebag for holding extra medical supplies. This one has reflective stripes!"
	icon_state = "duffle_emt"

/obj/item/storage/backpack/dufflebag/sec
	name = "security dufflebag"
	desc = "A large dufflebag for holding extra security supplies and ammunition."
	icon_state = "duffle_security"

/obj/item/storage/backpack/dufflebag/eng
	name = "industrial dufflebag"
	desc = "A large dufflebag for holding extra tools and supplies."
	icon_state = "duffle_industrial"

/obj/item/storage/backpack/dufflebag/sci
	name = "science dufflebag"
	desc = "A large dufflebag for holding circuits and beakers."
	icon_state = "duffle_science"

/obj/item/storage/backpack/dufflebag/drone
	name = "drone dufflebag"
	desc = "A large dufflebag for holding small robots? Or maybe it's one used by robots!"
	icon_state = "duffle_drone"

/obj/item/storage/backpack/dufflebag/cursed
	name = "cursed dufflebag"
	desc = "That probably shouldn't be moving..."
	icon_state = "duffle_curse"

/*
 * Satchel Types
 */

/obj/item/storage/backpack/satchel
	name = "leather satchel"
	desc = "It's a very fancy satchel made with fine leather."
	icon_state = "satchel"

/obj/item/storage/backpack/satchel/withwallet
	starts_with = list(/obj/item/storage/wallet/random)

/obj/item/storage/backpack/satchel/norm
	name = "satchel"
	desc = "A trendy looking satchel."
	icon_state = "satchel_grey"

/obj/item/storage/backpack/satchel/white
	name = "white satchel"
	icon_state = "satchel_white"

/obj/item/storage/backpack/satchel/fancy
	name = "fancy satchel"
	icon_state = "satchel_fancy"

/obj/item/storage/backpack/satchel/military
	name = "military satchel"
	icon_state = "satchel_military"

/obj/item/storage/backpack/satchel/eng
	name = "industrial satchel"
	desc = "A tough satchel with extra pockets."
	icon_state = "satchel_industrial"

/obj/item/storage/backpack/satchel/med
	name = "medical satchel"
	desc = "A sterile satchel used in medical departments."
	icon_state = "satchel_medical"

/obj/item/storage/backpack/satchel/vir
	name = "virologist satchel"
	desc = "A sterile satchel with virologist colours."
	icon_state = "satchel_green"

/obj/item/storage/backpack/satchel/chem
	name = "chemist satchel"
	desc = "A sterile satchel with chemist colours."
	icon_state = "satchel_orange"

/obj/item/storage/backpack/satchel/gen
	name = "geneticist satchel"
	desc = "A sterile satchel with geneticist colours."
	icon_state = "satchel_blue"

/obj/item/storage/backpack/satchel/tox
	name = "scientist satchel"
	desc = "Useful for holding research materials."
	icon_state = "satchel_purple"

/obj/item/storage/backpack/satchel/sec
	name = "security satchel"
	desc = "A robust satchel for security related needs."
	icon_state = "satchel_security"

/obj/item/storage/backpack/satchel/hyd
	name = "hydroponics satchel"
	desc = "A green satchel for plant related work."
	icon_state = "satchel_hydro"

/obj/item/storage/backpack/satchel/cap
	name = "site manager's satchel"
	desc = "An exclusive satchel for officers."
	icon_state = "satchel_captain"

//ERT backpacks.
/obj/item/storage/backpack/ert
	name = "emergency response team backpack"
	desc = "A spacious backpack with lots of pockets, used by members of the Emergency Response Team."
	icon_state = "ert_commander"
	max_storage_space = INVENTORY_DUFFLEBAG_SPACE

//Commander
/obj/item/storage/backpack/ert/commander
	name = "emergency response team commander backpack"
	desc = "A spacious backpack with lots of pockets, worn by the commander of an Emergency Response Team."

//Security
/obj/item/storage/backpack/ert/security
	name = "emergency response team security backpack"
	desc = "A spacious backpack with lots of pockets, worn by security members of an Emergency Response Team."
	icon_state = "ert_security"

//Engineering
/obj/item/storage/backpack/ert/engineer
	name = "emergency response team engineer backpack"
	desc = "A spacious backpack with lots of pockets, worn by engineering members of an Emergency Response Team."
	icon_state = "ert_engineering"

//Medical
/obj/item/storage/backpack/ert/medical
	name = "emergency response team medical backpack"
	desc = "A spacious backpack with lots of pockets, worn by medical members of an Emergency Response Team."
	icon_state = "ert_medical"

/*
 * Courier Bags
 */

/obj/item/storage/backpack/messenger
	name = "messenger bag"
	desc = "A sturdy backpack worn over one shoulder."
	icon_state = "courier"
	item_state_slots = list(slot_r_hand_str = "satchel_grey", slot_l_hand_str = "satchel_grey")

/obj/item/storage/backpack/messenger/chem
	name = "chemistry messenger bag"
	desc = "A serile backpack worn over one shoulder.  This one is in Chemsitry colors."
	icon_state = "courier_chemistry"
	item_state_slots = list(slot_r_hand_str = "satchel_orange", slot_l_hand_str = "satchel_orange")

/obj/item/storage/backpack/messenger/med
	name = "medical messenger bag"
	desc = "A sterile backpack worn over one shoulder used in medical departments."
	icon_state = "courier_medical"
	item_state_slots = list(slot_r_hand_str = "satchel_medical", slot_l_hand_str = "satchel_medical")

/obj/item/storage/backpack/messenger/viro
	name = "virology messenger bag"
	desc = "A sterile backpack worn over one shoulder.  This one is in Virology colors."
	icon_state = "courier_virology"
	item_state_slots = list(slot_r_hand_str = "satchel_green", slot_l_hand_str = "satchel_green")

/obj/item/storage/backpack/messenger/tox
	name = "research messenger bag"
	desc = "A backpack worn over one shoulder.  Useful for holding science materials."
	icon_state = "courier_toxins"
	item_state_slots = list(slot_r_hand_str = "satchel_purple", slot_l_hand_str = "satchel_purple")

/obj/item/storage/backpack/messenger/com
	name = "command messenger bag"
	desc = "A special backpack worn over one shoulder.  This one is made specifically for officers."
	icon_state = "courier_captain"
	item_state_slots = list(slot_r_hand_str = "satchel_captain", slot_l_hand_str = "satchel_captain")

/obj/item/storage/backpack/messenger/engi
	name = "engineering messenger bag"
	icon_state = "courier_industrial"
	item_state_slots = list(slot_r_hand_str = "satchel_industrial", slot_l_hand_str = "satchel_industrial")

/obj/item/storage/backpack/messenger/hyd
	name = "hydroponics messenger bag"
	desc = "A backpack worn over one shoulder.  This one is designed for plant-related work."
	icon_state = "courier_hydro"
	item_state_slots = list(slot_r_hand_str = "satchel_hydro", slot_l_hand_str = "satchel_hydro")

/obj/item/storage/backpack/messenger/sec
	name = "security messenger bag"
	desc = "A tactical backpack worn over one shoulder. This one is in Security colors."
	icon_state = "courier_security"
	item_state_slots = list(slot_r_hand_str = "satchel_security", slot_l_hand_str = "satchel_security")

/obj/item/storage/backpack/messenger/black
	icon_state = "courier_black"


/*
 * Sport Bags
 */

/obj/item/storage/backpack/sport
	name = "sports backpack"
	icon_state = "backsport"

/obj/item/storage/backpack/sport/white
	name = "white sports backpack"
	icon_state = "backsport_white"

/obj/item/storage/backpack/sport/fancy
	name = "fancy sports backpack"
	icon_state = "backsport_fancy"

/obj/item/storage/backpack/sport/vir
	name = "virologist sports backpack"
	desc = "A sterile sports backpack with virologist colours."
	icon_state = "backsport_green"

/obj/item/storage/backpack/sport/chem
	name = "chemist sports backpack"
	desc = "A sterile sports backpack with chemist colours."
	icon_state = "backsport_orange"

/obj/item/storage/backpack/sport/gen
	name = "geneticist sports backpack"
	desc = "A sterile sports backpack with geneticist colours."
	icon_state = "backsport_blue"

/obj/item/storage/backpack/sport/tox
	name = "scientist sports backpack"
	desc = "Useful for holding research materials."
	icon_state = "backsport_purple"

/obj/item/storage/backpack/sport/sec
	name = "security sports backpack"
	desc = "A robust sports backpack for security related needs."
	icon_state = "backsport_security"

/obj/item/storage/backpack/sport/hyd
	name = "hydroponics sports backpack"
	desc = "A green sports backpack for plant related work."
	icon_state = "backsport_hydro"

//Purses
/obj/item/storage/backpack/purse
	name = "purse"
	desc = "A small, fashionable bag typically worn over the shoulder."
	icon_state = "purse"
	item_state_slots = list(slot_r_hand_str = "lgpurse", slot_l_hand_str = "lgpurse")
	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_COST_NORMAL * 5

CAPABILITIES(/obj/item/storage/backpack/purse)
	configure(storage(max_size = ITEMSIZE_NORMAL))

//Parachutes

/obj/item/storage/backpack/parachute
	name = "parachute"
	desc = "A specially made backpack, designed to help one survive jumping from incredible heights. It sacrifices some storage space for that added functionality."
	icon_state = "parachute"
	item_state_slots = list(slot_r_hand_str = "backpack", slot_l_hand_str = "backpack")
	max_storage_space = ITEMSIZE_COST_NORMAL * 5
	/// Packed and ready to open (movement reads the same fact through dq_get_parachute()).
	var/packed = FALSE

TRACKED(/obj/item/storage/backpack/parachute, packed)

/obj/item/storage/backpack/parachute/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(dq_get_parachute(src))
			. += "It seems to be packed."
		else
			. += "It seems to be unpacked."

/obj/item/storage/backpack/parachute/handleParachute()
	set_packed(FALSE)
	dq_set_parachute(src, FALSE)	//If you dq_get_parachute(src) in, the dq_get_parachute(src) has probably been used.

MSG_DEF_SELF(parachute/worn, "How do you expect to work on it while it's on your back?")
MSG_DEF(parachute/packed, "You finish packing %T%!", "%U% finishes packing %T%!")
MSG_DEF(parachute/unpacked, "You finish unpacking %T%!", "%U% finishes unpacking %T%!")

CAPABILITIES(/obj/item/storage/backpack/parachute)
	op("pack", menu(), when(PROC_REF(is_unpacked)), label("Pack Parachute"),
		needs(carried(), req_not_worn(SLOT_ID_BACK, because = MSG(parachute/worn))), wait(5 SECONDS),
		then(PROC_REF(pack_it)), says(MSG(parachute/packed), blind = span_infoplain("You hear the shuffling of cloth.")))
	op("unpack", menu(), when(PROC_REF(is_packed)), label("Unpack Parachute"),
		needs(carried(), req_not_worn(SLOT_ID_BACK, because = MSG(parachute/worn))), wait(2.5 SECONDS),
		then(PROC_REF(unpack_it)), says(MSG(parachute/unpacked), blind = span_infoplain("You hear the shuffling of cloth.")))

/obj/item/storage/backpack/parachute/proc/is_packed(datum/act/op/A)
	return packed

/obj/item/storage/backpack/parachute/proc/is_unpacked(datum/act/op/A)
	return !packed

/obj/item/storage/backpack/parachute/proc/pack_it(datum/act/op/A)
	set_packed(TRUE)
	dq_set_parachute(src, TRUE)
	return OP_OK

/obj/item/storage/backpack/parachute/proc/unpack_it(datum/act/op/A)
	set_packed(FALSE)
	dq_set_parachute(src, FALSE)
	return OP_OK

/obj/item/storage/backpack/satchel/ranger
	name = "ranger satchel"
	desc = "A satchel designed for the Go Go ERT Rangers series to allow for slightly bigger carry capacity for the ERT-Rangers.\
		Unlike the show claims, it is not a phoron-enhanced satchel of holding with plot-relevant content."
	icon = 'icons/obj/clothing/ranger.dmi'
	icon_state = "ranger_satchel"

//Virgo-added items

/obj/item/storage/backpack/saddlebag
	name = "Horse Saddlebags"
	desc = "A saddle that holds items. Seems slightly bulky."
	item_state = "saddlebag"
	icon_state = "saddlebag"
	max_storage_space = INVENTORY_DUFFLEBAG_SPACE //Saddlebags can hold more, like dufflebags
	slowdown = 0.5 //And are slower, too...
	var/taurtype = /datum/sprite_accessory/tail/taur/horse //Acceptable taur type to be wearing this
	var/no_message = "You aren't the appropriate taur type to wear this!"

TYPE_TABLE(/obj/item/storage/backpack/saddlebag, equip_spec, dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/storage/backpack/saddlebag/proc/taur_fit, null))))

/obj/item/storage/backpack/saddlebag/proc/taur_fit(mob/living/carbon/human/H)
	return (istype(H) && istype(H.tail_style, taurtype)) ? TRUE : lowertext(no_message)

/* If anyone wants to make some... this is how you would.
/obj/item/storage/backpack/saddlebag/spider
	name = "Drider Saddlebags"
	item_state = "saddlebag_drider"
	icon_state = "saddlebag_drider"
	var/taurtype = /datum/sprite_accessory/tail/taur/spider
*/

/obj/item/storage/backpack/saddlebag_common //Shared bag for other taurs with sturdy backs
	name = "Taur Saddlebags"
	desc = "A saddle that holds items. Seems slightly bulky."
	item_state = "saddlebag"
	icon_state = "saddlebag"
	var/icon_base = "saddlebag"
	max_storage_space = INVENTORY_DUFFLEBAG_SPACE //Saddlebags can hold more, like dufflebags
	slowdown = 0.5 //And are slower, too...
	var/no_message = "You aren't the appropriate taur type to wear this!"

TYPE_TABLE(/obj/item/storage/backpack/saddlebag_common, equip_spec, dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/storage/backpack/saddlebag_common/proc/taur_fit, null))))

/// Any taur half; the bags take the look of the wearer's.
/obj/item/storage/backpack/saddlebag_common/proc/taur_fit(mob/living/carbon/human/H)
	var/datum/sprite_accessory/tail/taur/TT = istype(H) ? H.tail_style : null
	if(!istype(TT))
		return lowertext(no_message)
	item_state = "[icon_base]_[TT.icon_sprite_tag]"	//icon_sprite_tag is something like "deer"
	return TRUE



/obj/item/storage/backpack/saddlebag_common/robust //Shared bag for other taurs with sturdy backs
	name = "Robust Saddlebags"
	desc = "A saddle that holds items. Seems robust."
	item_state = "robustsaddle"
	icon_state = "robustsaddle"
	icon_base = "robustsaddle"

/obj/item/storage/backpack/saddlebag_common/vest //Shared bag for other taurs with sturdy backs
	name = "Taur Duty Vest"
	desc = "An armored vest with the armor modules replaced with various handy compartments with decent storage capacity. Useless for protection though. Holds less than a saddle."
	item_state = "taurvest"
	icon_state = "taurvest"
	icon_base = "taurvest"
	max_storage_space = INVENTORY_STANDARD_SPACE
	slowdown = 0

/obj/item/storage/backpack/dufflebag/fluff //Black dufflebag without syndie buffs.
	name = "plain black dufflebag"
	desc = "A large dufflebag for holding extra tactical supplies."
	icon_state = "duffle_syndie"

///Exploration Bags///

/obj/item/storage/backpack/explorer
	name = "exploration backpack"
	desc = "A backpack for carrying a large number of supplies easily."
	icon_state = "explorer"

/obj/item/storage/backpack/satchel/explorer
	name = "exploration satchel"
	desc = "A satchel for carrying a large number of supplies easily."
	icon_state = "explorer_satchel"
	item_state_slots = null

/obj/item/storage/backpack/messenger/explorer
	name = "exploration messenger bag"
	desc = "A sturdy backpack worn over one shoulder."
	icon_state = "explorer_courier"
	item_state_slots = null

/obj/item/storage/backpack/dufflebag/explorer
	name = "exploration dufflebag"
	desc = "A large dufflebag for holding extra supplies."
	icon_state = "explorer_duffle"

///Talon Bags///

/obj/item/storage/backpack/talon
	name = "Talon backpack"
	desc = "A backpack for carrying a large number of supplies easily."
	icon_state = "talon"

/obj/item/storage/backpack/satchel/talon
	name = "Talon satchel"
	desc = "A satchel for carrying a large number of supplies easily."
	icon_state = "talon_satchel"
	item_state_slots = null

/obj/item/storage/backpack/messenger/talon
	name = "Talon messenger bag"
	desc = "A sturdy backpack worn over one shoulder."
	icon_state = "talon_courier"
	item_state_slots = null

/obj/item/storage/backpack/dufflebag/talon
	name = "Talon dufflebag"
	desc = "A large dufflebag for holding extra supplies."
	icon_state = "talon_duffle"

///Roboticist Bags///

/obj/item/storage/backpack/satchel/roboticist
	name = "roboticist satchel"
	desc = "A satchel for carrying a large number of spare parts easily."
	item_state = "satchel-robo"
	icon_state = "satchel-robo"

/obj/item/storage/backpack/roboticist
	name = "roboticist backpack"
	desc = "A backpack for carrying a large number of spare parts easily."
	item_state = "backpack-robo"
	icon_state = "backpack-robo"

///Vintage Military Bags///

/obj/item/storage/backpack/vietnam
	name = "vietnam backpack"
	desc = "There are tangos in the trees! We need napalm right now! Why is my gun jammed?"
	item_state = "nambackpack"
	icon_state = "nambackpack"

/obj/item/storage/backpack/russian
	name = "russian backpack"
	desc = "Useful for carrying large quantities of vodka."
	item_state = "ru_rucksack"
	icon_state = "ru_rucksack"

/obj/item/storage/backpack/korean
	name = "korean backpack"
	desc = "Insert witty description here."
	item_state = "kr_rucksack"
	icon_state = "kr_rucksack"

//strapless
/obj/item/storage/backpack/satchel/strapless
	name = "strapless satchel"
	desc = "A satchel for carrying a large number of supplies easily. Without Straps"
	icon_state = "satchel_strapless"
	item_state_slots = null


/obj/item/storage/backpack/saddlebag_common/lightweight
	name = "Taur Saddlebags (Light)"
	desc = "A saddle that holds items. Lighter than its heavier cousin, as the cost of storage space."
	max_storage_space = INVENTORY_STANDARD_SPACE
	slowdown = 0

/obj/item/storage/backpack/saddlebag_common/robust/lightweight
	name = "Lightweight Saddlebags"
	desc = "A saddle that holds items. Lighter than it's robust cousin, at the cost of storage space.."
	max_storage_space = INVENTORY_STANDARD_SPACE
	slowdown = 0

/obj/item/storage/backpack/saddlebag_common/vest/heavy
	name = "Taur Duty Vest (Heavy)"
	desc = "An armored vest with the armor modules replaced with various handy compartments with decent storage capacity. Useless for protection though. Holds more than its lighter cousin.."
	max_storage_space = INVENTORY_DUFFLEBAG_SPACE
	slowdown = 0.5
