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

/// Vapes (ecig_step) every 2 s while switched on (replaces the smokable's "lit").
/obj/item/clothing/mask/smokable/ecig/var/active = 0

/// Switching it on or off changes its in-hand and worn state (a draw never writes it).
/obj/item/clothing/mask/smokable/ecig/proc/set_active(value)
	if(active == value)
		return FALSE
	active = value
	tracked_changed(src, nameof(active))
	sync_item_state()
	return TRUE

SETTER(/obj/item/clothing/mask/smokable/ecig, active)

CAPABILITIES(/obj/item/clothing/mask/smokable/ecig)
	owns_one(nameof(ec_cartridge), /obj/item/reagent_containers/ecig_cartridge, starts = nameof(cartridge_type))
	every(2 SECONDS, then(PROC_REF(ecig_step)), when = nameof(active))
	on_change(nameof(ec_cartridge), ANY, then(PROC_REF(cartridge_changed)))
	op("toggle", in_hand(), then(PROC_REF(toggled)))
	op("eject_cartridge", hand(), ungated(), when(req_empty_hand()), label("Eject cartridge"), then(PROC_REF(cartridge_ejected)))

// ALLOW(init/INSTANCE_STATE): sets its in-hand and worn state from the cartridge the type table loads it with (a draw never writes it)
/obj/item/clothing/mask/smokable/ecig/Initialize(mapload)
	. = ..()
	sync_item_state()

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

CAPABILITIES(/obj/item/clothing/mask/smokable/ecig/util)
	rolls(nameof(color), PROC_REF(roll_color))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/clothing/mask/smokable/ecig/util/proc/roll_color(datum/roller/R)
	return R.choose(ecig_colors)

/obj/item/clothing/mask/smokable/ecig/deluxe
	name = "deluxe electronic cigarette"
	desc = "A premium model eGavana MK3 electronic cigarette, shaped like a cigar."
	description_fluff = "The eGavana is a product of Morpheus Cyberkinetics, and comes standard with additional jacks that allow cyborgs and positronics to experience a simulation of soothing artificial oil residues entering their lungs. It's a pretty good cig for meatbags, too."
	icon_state = "pcigoff1"
	icon_off = "pcigoff1"
	icon_empty = "pcigoff2"
	icon_on = "pcigon"

/obj/item/clothing/mask/smokable/ecig/proc/ecig_step(datum/act/timer/A)
	if(ishuman(loc))
		var/mob/living/carbon/human/C = loc
		if (src == C.get_equipped_item(SLOT_ID_MASK) && C.check_has_mouth()) // if it's in the human/monkey mouth, transfer reagents to the mob
			if (!ec_cartridge || !ec_cartridge.reagents.total_volume)//no cartridge
				to_chat(C, span_notice("[src] turns off."))
				set_active(0)//autodisable the cigarette
				update_icon()
				return
			ec_cartridge.reagents.trans_to_mob(C, REM, CHEM_INGEST, 0.4) // Most of it is not inhaled... balance reasons.

/// A cartridge going in or out (or the first one made) changes its in-hand and worn state.
/obj/item/clothing/mask/smokable/ecig/proc/cartridge_changed(datum/act/A)
	sync_item_state()

/// What it shows: on, off with a cartridge, or empty (its own states, not the smokable's).
/obj/item/clothing/mask/smokable/ecig/proc/ecig_state()
	if(active)
		return icon_on
	if(ec_cartridge)
		return icon_off
	return icon_empty

/obj/item/clothing/mask/smokable/ecig/draw(datum/look/look)
	..()
	look.state(ecig_state())
	if(active)
		look.light(brightness_on)

/obj/item/clothing/mask/smokable/ecig/state_suffix()
	return ""

/// The in-hand and worn state is the icon state it shows.
/obj/item/clothing/mask/smokable/ecig/sync_item_state()
	var/wanted = ecig_state()
	if(item_state == wanted)
		return
	item_state = wanted
	if(ismob(loc))
		var/mob/living/M = loc
		M.update_inv_wear_mask(0)
		M.update_inv_l_hand(0)
		M.update_inv_r_hand(1)

/// A cartridge used on it is installed. It never lit from a flame (the smokable's lighting does not apply to e-cigs); the click goes on.
/obj/item/clothing/mask/smokable/ecig/item_applied(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/reagent_containers/ecig_cartridge))
		if (ec_cartridge)//can't add second one
			to_chat(user, span_notice("A cartridge has already been installed."))
		else//fits in new one
			if(!move_into(src, nameof(src.ec_cartridge), I, user))
				return OP_OK
			update_icon()
			to_chat(user, span_notice("You insert [I] into [src]."))
	return OP_OK

/// Using it in the hand switches it on or off; the click ends here (dq_hc_items b_ecig_toggles... needs it on after one use).
/obj/item/clothing/mask/smokable/ecig/proc/toggled(datum/act/op/A)
	var/mob/user = A.actor
	if(active)
		set_active(FALSE)
		to_chat(user, span_notice("You turn off \the [src]. "))
		update_icon()
	else
		if(!ec_cartridge)
			to_chat(user, span_notice("You can't use it with no cartridge installed!."))
			return OP_DECLINE
		set_active(TRUE)
		to_chat(user, span_notice("You turn on \the [src]. "))
		update_icon()
	return OP_OK

/// An empty hand on the held e-cig ejects the cartridge.
/obj/item/clothing/mask/smokable/ecig/proc/cartridge_ejected(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() != src)//if being hold
		return OP_DECLINE
	if (ec_cartridge)
		set_active(0)
		user.put_in_hands(ec_cartridge)
		to_chat(user, span_notice("You eject [ec_cartridge] from \the [src]."))
		rel_take(src, nameof(ec_cartridge))
		update_icon()
	return OP_OK

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

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/blanknico)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10)))

/obj/item/reagent_containers/ecig_cartridge/med_nicotine
	name = "tobacco flavour cartridge"
	desc =  "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its tobacco flavored."

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/med_nicotine)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 15)))

/obj/item/reagent_containers/ecig_cartridge/high_nicotine
	name = "high nicotine tobacco flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its tobacco flavored, with extra nicotine."

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/high_nicotine)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 10, REAGENT_ID_WATER = 10)))

/obj/item/reagent_containers/ecig_cartridge/orange
	name = "orange flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its orange flavored."

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/orange)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_ORANGEJUICE = 5)))

/obj/item/reagent_containers/ecig_cartridge/mint
	name = "mint flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its mint flavored."

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/mint)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_MENTHOL = 5)))

/obj/item/reagent_containers/ecig_cartridge/watermelon
	name = "watermelon flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its watermelon flavored."
CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/watermelon)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_WATERMELONJUICE = 5)))

/obj/item/reagent_containers/ecig_cartridge/grape
	name = "grape flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its grape flavored."

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/grape)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_GRAPEJUICE = 5)))

/obj/item/reagent_containers/ecig_cartridge/lemonlime
	name = "lemon-lime flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its lemon-lime flavored."

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/lemonlime)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_LEMONLIME = 5)))

/obj/item/reagent_containers/ecig_cartridge/coffee
	name = "coffee flavour cartridge"
	desc = "A small metal cartridge which contains an atomizing coil and a solution to be atomized. The label says its coffee flavored."

CAPABILITIES(/obj/item/reagent_containers/ecig_cartridge/coffee)
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 5, REAGENT_ID_WATER = 10, REAGENT_ID_COFFEE = 5)))
