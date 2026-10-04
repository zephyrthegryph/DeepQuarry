/obj/item/clothing/mask/smokable/ecig
	name = DEVELOPER_WARNING_NAME // "electronic cigarette"
	desc = "For the modern approach to smoking."
	icon = 'icons/obj/ecig.dmi'
	var/cartridge_type = /obj/item/reagent_containers/ecig_cartridge/med_nicotine
	var/obj/item/reagent_containers/ecig_cartridge/ec_cartridge // owned: the loaded cartridge, kept in the e-cig's contents
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS | SLOT_MASK
	attack_verb = list("attacked", "poked", "battered")
	body_parts_covered = 0
	var/brightness_on = 1
	chem_volume = 0 //ecig has no storage on its own but has reagent container created by parent obj
	item_state = "ecigoff"
	is_pipe = TRUE //to avoid a runtime in examine()
	var/icon_off
	var/icon_empty
	var/ecig_colors = list(null, COLOR_DARK_GRAY, COLOR_RED_GRAY, COLOR_BLUE_GRAY, COLOR_GREEN_GRAY, COLOR_PURPLE_GRAY)

CAPABILITIES(/obj/item/clothing/mask/smokable/ecig)
	owns_one(nameof(ec_cartridge), /obj/item/reagent_containers/ecig_cartridge)

DECLARE_DEFAULT_CHILD(/obj/item/clothing/mask/smokable/ecig, "ec_cartridge", "cartridge_type")

/// Vapes (periodic_step) every 2 s while switched on (replaces the smokable's "lit").
OM_FIELD(/obj/item/clothing/mask/smokable/ecig, active, 0, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/clothing/mask/smokable/ecig, PERIODIC_SLOW, "active")

/obj/item/clothing/mask/smokable/ecig/examine(mob/user)
	. = ..()

	if(active)
		. += span_notice("It is turned on.")
	else
		. += span_notice("It is turned off.")
	if(Adjacent(user))
		if(ec_cartridge)
			if(!ec_cartridge.reagents?.total_volume)
				. += span_notice("Its cartridge is empty!")
			else if (ec_cartridge.reagents.total_volume <= ec_cartridge.volume * 0.25)
				. += span_notice("Its cartridge is almost empty!")
			else if (ec_cartridge.reagents.total_volume <= ec_cartridge.volume * 0.66)
				. += span_notice("Its cartridge is half full!")
			else if (ec_cartridge.reagents.total_volume <= ec_cartridge.volume * 0.90)
				. += span_notice("Its cartridge is almost full!")
			else
				. += span_notice("Its cartridge is full!")
		else
			. += span_notice("It has no cartridge.")

/obj/item/clothing/mask/smokable/ecig/simple
	name = "simple electronic cigarette"
	desc = "A cheap Lucky 1337 electronic cigarette, styled like a traditional cigarette."
	description_fluff = "Produced by the Ward-Takahashi Corporation on behalf of the Lucky Stars cigarette brand, the 1337 is the e-cig of choice for teenage wastrels across the core worlds. Due to a total lack of safety features, this model is banned on most interstellar flights."
	icon_state = "ccigoff"
	icon_off = "ccigoff"
	icon_empty = "ccigoff"
	icon_on = "ccigon"

/obj/item/clothing/mask/smokable/ecig/util
	name = "electronic cigarette"
	desc = "A popular utilitarian model electronic cigarette, the ONI-55. Comes in a variety of colors."
	description_fluff = "Ward-Takahashi's flagship brand of e-cig is a popular fashion accessory in certain circles where open flames are prohibited. Custom casings are sold for almost as much as the device itself, and are practically impossible to DIY."
	icon_state = "ecigoff1"
	icon_off = "ecigoff1"
	icon_empty = "ecigoff1"
	icon_on = "ecigon"

/obj/item/clothing/mask/smokable/ecig/util/Initialize(mapload)
	. = ..()
	color = pick(ecig_colors)

/obj/item/clothing/mask/smokable/ecig/deluxe
	name = "deluxe electronic cigarette"
	desc = "A premium model eGavana MK3 electronic cigarette, shaped like a cigar."
	description_fluff = "The eGavana is a product of Morpheus Cyberkinetics, and comes standard with additional jacks that allow cyborgs and positronics to experience a simulation of soothing artificial oil residues entering their lungs. It's a pretty good cig for meatbags, too."
	icon_state = "pcigoff1"
	icon_off = "pcigoff1"
	icon_empty = "pcigoff2"
	icon_on = "pcigon"

/obj/item/clothing/mask/smokable/ecig/periodic_step()
	if(ishuman(loc))
		var/mob/living/carbon/human/C = loc
		if (src == C.get_equipped_item(SLOT_ID_MASK) && C.check_has_mouth()) // if it's in the human/monkey mouth, transfer reagents to the mob
			if (!ec_cartridge || !ec_cartridge.reagents.total_volume)//no cartridge
				to_chat(C, span_notice("[src] turns off."))
				set_active(0)//autodisable the cigarette
				update_icon()
				return
			ec_cartridge.reagents.trans_to_mob(C, REM, CHEM_INGEST, 0.4) // Most of it is not inhaled... balance reasons.

DECLARE_APPEARANCE_PROC(/obj/item/clothing/mask/smokable/ecig, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/clothing/mask/smokable/ecig/appearance_overlays()
	. = list()
	if (active)
		item_state = icon_on
		icon_state = icon_on
		set_light(brightness_on)
	else if (ec_cartridge)
		set_light(0)
		item_state = icon_off
		icon_state = icon_off
	else
		icon_state = icon_empty
		item_state = icon_empty
		set_light(0)
	if(ismob(loc))
		var/mob/living/M = loc
		M.update_inv_wear_mask(0)
		M.update_inv_l_hand(0)
		M.update_inv_r_hand(1)

EXTEND_INTERACTIONS(/obj/item/clothing/mask/smokable/ecig, \
	INTERACT_SELF(null, PROC_REF(ecig_self)), \
	INTERACT_ITEM(null, PROC_REF(ecig_item)), \
	INTERACT_HAND_UNGATED("Eject cartridge", PROC_REF(ecig_hand)), \
)

/// Old attackby. It never called its parent, so it always answers (the smokable lighting never applied to e-cigs).
/obj/item/clothing/mask/smokable/ecig/proc/ecig_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/reagent_containers/ecig_cartridge))
		if (ec_cartridge)//can't add second one
			to_chat(user, span_notice("A cartridge has already been installed."))
		else//fits in new one
			if(!move_into(src, nameof(src.ec_cartridge), I, user))
				return INTERACTION_HANDLED_PASS
			update_icon()
			to_chat(user, span_notice("You insert [I] into [src]."))
	return INTERACTION_HANDLED_PASS

/// Old attack_self. Returns FALSE so the clothing self-use still follows, as the old ..() did.
/obj/item/clothing/mask/smokable/ecig/proc/ecig_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(active)
		set_active(FALSE)
		to_chat(user, span_notice("You turn off \the [src]. "))
		update_icon()
	else
		if(!ec_cartridge)
			to_chat(user, span_notice("You can't use it with no cartridge installed!."))
			return FALSE
		set_active(TRUE)
		to_chat(user, span_notice("You turn on \the [src]. "))
		update_icon()
	return FALSE

/// Old attack_hand: eject the cartridge.
/obj/item/clothing/mask/smokable/ecig/proc/ecig_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.get_inactive_hand() != src)//if being hold
		return FALSE
	if (ec_cartridge)
		set_active(0)
		user.put_in_hands(ec_cartridge)
		to_chat(user, span_notice("You eject [ec_cartridge] from \the [src]."))
		own_take(src, nameof(ec_cartridge))
		update_icon()
	return TRUE

MATERIAL_MIX(/obj/item/reagent_containers/ecig_cartridge, list(MAT_STEEL = 50, MAT_GLASS = 10))
/obj/item/reagent_containers/ecig_cartridge
	name = "tobacco flavour cartridge"
	desc = "A small metal cartridge, used with electronic cigarettes, which contains an atomizing coil and a solution to be atomized."
	w_class = ITEMSIZE_TINY
	icon = 'icons/obj/ecig.dmi'
	icon_state = "ecartridge"
	volume = 20
	max_transfer_amount = null

// A cartridge is an open holder of its volume (poured into; its contents are told by its own examine).
CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge)
	reagent_container(
		volume = nameof(volume),
		settable = FALSE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this))

/obj/item/reagent_containers/ecig_cartridge/examine(mob/user as mob)//to see how much left
	. = ..()
	. += "The cartridge has [reagents.total_volume] units of liquid remaining."

//flavours
/obj/item/reagent_containers/ecig_cartridge/blank
	name = "ecigarette cartridge"
	desc = "A small metal cartridge which contains an atomizing coil."

/obj/item/reagent_containers/ecig_cartridge/blanknico
	name = "flavorless nicotine cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says you can add whatever flavoring agents you want."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/blanknico, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10))

/obj/item/reagent_containers/ecig_cartridge/med_nicotine
	name = "tobacco flavour cartridge"
	desc =  "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its tobacco flavored."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/med_nicotine, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 15))

/obj/item/reagent_containers/ecig_cartridge/high_nicotine
	name = "high nicotine tobacco flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its tobacco flavored, with extra nicotine."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/high_nicotine, null, list(REAGENT_ID_NICOTINE = 10, REAGENT_ID_WATER = 10))

/obj/item/reagent_containers/ecig_cartridge/orange
	name = "orange flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its orange flavored."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/orange, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_ORANGEJUICE = 5))

/obj/item/reagent_containers/ecig_cartridge/mint
	name = "mint flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its mint flavored."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/mint, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_MENTHOL = 5))

/obj/item/reagent_containers/ecig_cartridge/watermelon
	name = "watermelon flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its watermelon flavored."
DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/watermelon, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_WATERMELONJUICE = 5))

/obj/item/reagent_containers/ecig_cartridge/grape
	name = "grape flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its grape flavored."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/grape, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_GRAPEJUICE = 5))

/obj/item/reagent_containers/ecig_cartridge/lemonlime
	name = "lemon-lime flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its lemon-lime flavored."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/lemonlime, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_LEMONLIME = 5))

/obj/item/reagent_containers/ecig_cartridge/coffee
	name = "coffee flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its coffee flavored."

DECLARE_REAGENTS(/obj/item/reagent_containers/ecig_cartridge/coffee, null, list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_COFFEE = 5))
