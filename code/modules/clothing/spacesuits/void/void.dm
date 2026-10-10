//NASA Voidsuit
/obj/item/clothing/head/helmet/space/void
	name = "void helmet"
	desc = "A high-tech dark red space suit helmet. Used for AI satellite maintenance."
	icon_state = "void"
	item_state_slots = list(slot_r_hand_str = "syndicate", slot_l_hand_str = "syndicate")
	armor_spec = "melee=30;bullet=5;laser=20;energy=5;bomb=35;bio=100;rad=20;cold=60"
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 10 * ONE_ATMOSPHERE


	//Species-specific stuff.
	sprite_sheets = VR_SPECIES_SPRITE_SHEETS_HEAD_MOB
	sprite_sheets_obj = VR_SPECIES_SPRITE_SHEETS_HEAD_ITEM

	light_overlay = "helmet_light"
	var/no_cycle = FALSE	//stop this item from being put in a cycler

TYPE_TABLE(/obj/item/clothing/head/helmet/space/void, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_HUMAN, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN, SPECIES_XENOCHIMERA, SPECIES_XENOMORPH_HYBRID))))

/obj/item/clothing/suit/space/void
	name = "voidsuit"
	icon_state = "void"
	item_state_slots = list(slot_r_hand_str = "space_suit_syndicate", slot_l_hand_str = "space_suit_syndicate")
	desc = "A high-tech dark red space suit. Used for AI satellite maintenance."
	slowdown = 0.5
	armor_spec = "melee=30;bullet=5;laser=20;energy=5;bomb=35;bio=100;rad=20;cold=60"
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 10 * ONE_ATMOSPHERE
	special_hood_handling = TRUE
	actions_types = list(/datum/action/item_action/toggle_helmet)
	sprite_sheets = ALL_SPRITE_SHEETS_SUIT_MOB
	sprite_sheets_obj = SPECIES_SPRITE_SHEETS_SUIT_ITEM

	//Breach thresholds, should ideally be inherited by most (if not all) voidsuits.
	//With 0.2 resiliance, will reach 10 breach damage after 3 laser carbine blasts or 8 smg hits.
	breach_threshold = 12
	can_breach = 1

	//Inbuilt devices.
	// owned: deployable boots, kept in the suit's contents
	var/obj/item/clothing/shoes/magboots/boots = null // Deployable boots, if any.
	hood = null   // Deployable helmet, if any.
	// owned: deployable tank, kept in the suit's contents
	var/obj/item/tank/tank = null              // Deployable tank, if any.
	// owned: installed cooling unit, kept in the suit's contents
	var/obj/item/suit_cooling_unit/cooler = null// Cooling unit, for FBPs.  Cannot be installed alongside a tank.

	//Cycler settings
	var/no_cycle = FALSE	//stop this item from being put in a cycler

//Does it spawn with any Inbuilt devices?

TYPE_TABLE(/obj/item/clothing/suit/space/void, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN, SPECIES_XENOCHIMERA, SPECIES_XENOMORPH_HYBRID))))

TYPE_TABLE(/obj/item/clothing/suit/space/void, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_ALL_TANKS, POCKET_SUIT_REGULATORS))))
// A path in boots/hood/tank is created in the suit; null deploys nothing.
MSG_DEF_SELF(void/worn, "You cannot modify that while it is being worn.")
MSG_DEF_SELF(void/nothing_to_eject, "There is no tank or cooling unit inserted.")
MSG_DEF_SELF(void/no_helmet, "There is no helmet installed.")

CAPABILITIES(/obj/item/clothing/suit/space/void)
	owns_one(nameof(hood), /obj/item/clothing/head, starts = nameof(hood))
	op("voidsuit_eject_tank_alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), label("Eject tank"), needs(any_of(req_is(nameof(tank), TRUE, because = MSG(void/nothing_to_eject)), req_is(nameof(cooler), TRUE, because = MSG(void/nothing_to_eject)))), then(PROC_REF(voidsuit_eject_tank_alt)))
	op("voidsuit_install_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Voidsuit install item"), when(req(PROC_REF(install_item_applies))), needs(req_not_worn(SLOT_ID_SUIT, because = MSG(void/worn))), then(PROC_REF(voidsuit_install_item)))
	op("void_toggle_helmet_verb", menu(), label("Toggle Helmet"), needs(carried(), req_is(nameof(hood), TRUE, because = MSG(void/no_helmet))), then(PROC_REF(void_toggle_helmet_verb)))
	op("voidsuit_remove_component", tool(TOOL_SCREWDRIVER), label("Remove component"), needs(req_actor_kind(/mob/living), req_not_worn(SLOT_ID_SUIT, because = MSG(void/worn)), req_bool(PROC_REF(has_removable_component), because = MSG(void/nothing_installed))), asks(/datum/prompt/choice, fields = list("question" = "What component would you like to remove?", "title" = "Remove Component", "choices" = computed(PROC_REF(removable_components)), "timeout" = 0), step = "component"), then(PROC_REF(remove_component)))
	op("void_eject_tank_verb", menu(), label("Eject Voidsuit Tank/Cooler"), needs(carried(), any_of(req_is(nameof(tank), TRUE, because = MSG(void/nothing_to_eject)), req_is(nameof(cooler), TRUE, because = MSG(void/nothing_to_eject)))), then(PROC_REF(void_eject_tank_verb)))

/obj/item/clothing/suit/space/void/examine(mob/user)
	. = ..()
	. += span_notice("Alt-click to relase Tank/Cooling unit if installed.")
	for(var/obj/item/I in list(hood,boots,tank,cooler))
		. += "It has \a [I] installed."
	if(tank && in_range(src,user))
		. += span_notice("The wrist-mounted pressure gauge reads [max(round(tank.air_contents.return_pressure()),0)] kPa remaining in \the [tank].")

/obj/item/clothing/suit/space/void/refit_for_species(target_species)
	..()
	if(istype(hood))
		hood.refit_for_species(target_species)
	if(istype(boots))
		boots.refit_for_species(target_species)

/obj/item/clothing/suit/space/void/equipped(mob/M)
	..()

	var/mob/living/carbon/human/H = M

	if(!istype(H)) return

	if(H.get_equipped_item(SLOT_ID_SUIT) != src)
		return

	if(boots)
		if (H.equip_to_slot_if_possible(boots, SLOT_ID_SHOES))
			boots.canremove = FALSE

	if(hood)
		if(H.get_equipped_item(SLOT_ID_HEAD))
			to_chat(M, "You are unable to deploy your suit's helmet as \the [H.get_equipped_item(SLOT_ID_HEAD)] is in the way.")
		else if (H.equip_to_slot_if_possible(hood, SLOT_ID_HEAD))
			to_chat(M, "Your suit's helmet deploys with a hiss.")
			hood.canremove = FALSE

	if(cooler)
		if(H.get_equipped_item(SLOT_ID_SUIT_STORAGE)) //Ditto
			to_chat(M, "Alarmingly, the cooling unit installed into your suit fails to deploy.")
		else if (H.equip_to_slot_if_possible(cooler, SLOT_ID_SUIT_STORAGE))
			to_chat(M, "Your suit's cooling unit deploys.")
			cooler.canremove = FALSE

/obj/item/clothing/suit/space/void/dropped(mob/user, equipping, slot)
	..()

	var/mob/living/carbon/human/H

	if(hood)
		hood.canremove = TRUE
		H = hood.loc
		if(istype(H))
			if(hood && H.get_equipped_item(SLOT_ID_HEAD) == hood)
				H.drop_from_inventory(hood)
				hood.forceMove(src)

	if(boots)
		boots.canremove = TRUE
		H = boots.loc
		if(istype(H))
			if(boots && H.get_equipped_item(SLOT_ID_SHOES) == boots)
				H.drop_from_inventory(boots)
				boots.forceMove(src)

	if(tank)
		tank.canremove = TRUE
		tank.forceMove(src)

	if(cooler)
		cooler.canremove = TRUE
		cooler.forceMove(src)

/obj/item/clothing/suit/space/void/proc/attach_helmet(obj/item/clothing/head/helmet/space/void/helm)
	if(!istype(helm) || hood)
		return

	if(!move_into(src, nameof(src.hood), helm))
		return
	helm.set_light_flags(helm.light_flags | LIGHT_ATTACHED)

/obj/item/clothing/suit/space/void/proc/remove_helmet()
	if(!hood)
		return

	hood.forceMove(get_turf(src))
	hood.set_light_flags(hood.light_flags & ~LIGHT_ATTACHED)
	rel_take(src, nameof(hood))

/obj/item/clothing/suit/space/void/ui_action_click(mob/living/user, action_name)
	if(..())
		return TRUE
	var/why = can_toggle_helmet(user, src, null)
	if(why != TRUE)
		to_chat(user, span_warning("[why]."))
		return
	toggle_helmet_for(user)

/// Old verb "Toggle Helmet".
/obj/item/clothing/suit/space/void/proc/void_toggle_helmet_verb(datum/act/op/A)
	return toggle_helmet_for(A.actor)

/obj/item/clothing/suit/space/void/proc/toggle_helmet_for(mob/user)
	if(!isliving(loc))
		return

	var/mob/living/carbon/human/H = user

	if(!istype(H)) return
	if(H.stat) return
	if(H.get_equipped_item(SLOT_ID_SUIT) != src) return

	if(hood.light_on)
		to_chat(H, span_notice("The helmet light shuts off as it retracts."))
		hood.update_flashlight(H)

	if(H.get_equipped_item(SLOT_ID_HEAD) == hood)
		to_chat(H, span_notice("You retract your suit helmet."))
		hood.canremove = TRUE
		H.drop_from_inventory(hood)
		hood.forceMove(src)
		play_sfx(src.loc, SFX_MACHINES_CLICK2)
	else
		if(H.get_equipped_item(SLOT_ID_HEAD))
			to_chat(H, span_danger("You cannot deploy your helmet while wearing \the [H.get_equipped_item(SLOT_ID_HEAD)]."))
			return
		if(H.equip_to_slot_if_possible(hood, SLOT_ID_HEAD))
			hood.canremove = FALSE
			to_chat(H, span_info("You deploy your suit helmet, sealing you off from the world."))
			play_sfx(src.loc, SFX_MACHINES_CLICK2)

/// The install op is for anything but an accessory or a labeler: those go on to the clothing's own attach-an-accessory op.
/obj/item/clothing/suit/space/void/proc/install_item_applies(datum/act/op/A)
	return (!istype(A.held, /obj/item/clothing/accessory) && !istype(A.held, /obj/item/hand_labeler)) ? null : /datum/msg/req_failed

/// Requirement: TRUE, or why the helmet can't be toggled (a suit nobody wears is ignored silently by the effect).
/obj/item/clothing/suit/space/void/proc/can_toggle_helmet(mob/user, atom/target, obj/item/held)
	if(!isliving(loc))
		return TRUE
	if(!hood)
		return "there is no helmet installed"
	return TRUE

/// Requirement: TRUE, or why nothing can be ejected (a suit nobody wears is ignored silently by the effect).
/obj/item/clothing/suit/space/void/proc/can_eject_tank(mob/user, atom/target, obj/item/held)
	if(!isliving(loc))
		return TRUE
	if(!tank && !cooler)
		return "there is no tank or cooling unit inserted"
	return TRUE

/// Old click_alt. It never reached the clothing alt-click.
/obj/item/clothing/suit/space/void/proc/voidsuit_eject_tank_alt(datum/act/op/A)
	eject_tank_for(A.actor)
	return OP_OK

/// Old verb "Eject Voidsuit Tank/Cooler".
/obj/item/clothing/suit/space/void/proc/void_eject_tank_verb(datum/act/op/A)
	return eject_tank_for(A.actor)

/obj/item/clothing/suit/space/void/proc/eject_tank_for(mob/user)
	if(!isliving(src.loc)) return

	var/mob/living/carbon/human/H = user

	if(!istype(H)) return
	if(H.stat) return
	if(H.get_equipped_item(SLOT_ID_SUIT) != src) return

	var/obj/item/removing = null
	if(tank)
		removing = tank
		rel_take(src, nameof(tank))
	else
		removing = cooler
		rel_take(src, nameof(cooler))
	to_chat(H, span_danger("You press the emergency release, ejecting \the [removing] from your suit."))
	play_sfx(src.loc, SFX_MACHINES_CLICK, 1.5)
	removing.canremove = TRUE
	H.drop_from_inventory(removing)

/// Old attackby: install a helmet, magboots, tank or cooler.
/obj/item/clothing/suit/space/void/proc/voidsuit_install_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held

	if(!isliving(user)) return OP_PASS

	if(istype(W,/obj/item/clothing/head/helmet/space))
		if(hood)
			to_chat(user, "\The [src] already has a helmet installed.")
		else
			to_chat(user, "You attach \the [W] to \the [src]'s helmet mount.")
			user.drop_item()
			attach_helmet(W)
		return OP_PASS
	else if(istype(W,/obj/item/clothing/shoes/magboots))
		if(boots)
			to_chat(user, "\The [src] already has magboots installed.")
		else
			to_chat(user, "You attach \the [W] to \the [src]'s boot mounts.")
			move_into(src, nameof(src.boots), W, user)
		return OP_PASS
	else if(istype(W,/obj/item/tank))
		if(tank)
			to_chat(user, "\The [src] already has an airtank installed.")
		else if(cooler)
			to_chat(user, "\The [src]'s suit cooling unit is the modular suit storage. Remove it first.")
		else
			to_chat(user, "You insert \the [W] into \the [src]'s storage compartment.")
			move_into(src, nameof(src.tank), W, user)
		return OP_PASS
	else if(istype(W,/obj/item/suit_cooling_unit))
		if(cooler)
			to_chat(user, "\The [src] already has a suit cooling unit installed.")
		else if(tank)
			to_chat(user, "\The [src]'s airtank is in the modular suit storage.  Remove it first.")
		else
			to_chat(user, "You insert \the [W] into \the [src]'s storage compartment.")
			move_into(src, nameof(src.cooler), W, user)
		return OP_PASS

	return OP_DECLINE


//
// Because of our custom change in update_icons, we cannot rely upon the normal
// method of switching sprites when refitting (which is to have the referitter
// set the value of icon_override).  Therefore we use the sprite sheets method
// instead.
//

/obj/item/clothing/head/helmet/space/void

/obj/item/clothing/suit/space/void

/obj/item/clothing/head/helmet/space/void/heck
	name = "\improper H.E.C.K. helmet"
	desc = "Hostile Environiment Cross-Kinetic Helmet: A helmet designed to withstand the wide variety of hazards from \[REDACTED\]. It wasn't enough for its last owner."
	icon_state = "hostile_env"
	item_state = "hostile_env"
	armor_spec = "melee=60;bullet=35;laser=35;energy=15;bomb=55;bio=100;rad=20;cold=60"

/obj/item/clothing/head/helmet/space/void/heck/Initialize(mapload)
	. = ..()

/obj/item/clothing/head/helmet/space/void/heck/apply_accessories(image/standing)
	. = ..()
	var/mutable_appearance/glass_overlay = mutable_appearance(icon_override, "hostile_env_glass")
	glass_overlay.appearance_flags = KEEP_APART|RESET_COLOR
	standing.add_overlay(glass_overlay)
	return standing

/obj/item/clothing/suit/space/void/heck
	name = "\improper H.E.C.K. suit"
	desc = "Hostile Environment Cross-Kinetic Suit: A suit designed to withstand the wide variety of hazards from \[REDACTED\]. It wasn't enough for its last owner."
	icon_state = "hostile_env"
	item_state = "hostile_env"
	slowdown = 1.5
	armor_spec = "melee=60;bullet=35;laser=35;energy=15;bomb=55;bio=100;rad=20;cold=60"

/obj/item/clothing/head/helmet/space/void/syndicate_contract
	name = "syndicate contract helmet"
	desc = "A free helmet, gifted you by your new not-quite-corporate master!"
	icon_state = "syndicate-contract"
	item_state = "syndicate-contract"
	armor_spec = "melee=60;bullet=50;laser=30;energy=15;bomb=35;bio=100;rad=60;cold=60"
	siemens_coefficient = 0.6
	camera_networks = list(NETWORK_MERCENARY)

/obj/item/clothing/suit/space/void/syndicate_contract
	name = "syndicate contract suit"
	desc = "A free suit, gifted you by your new not-quite-corporate master!"
	icon_state = "syndicate-contract"
	item_state = "syndicate-contract"
	armor_spec = "melee=60;bullet=50;laser=30;energy=15;bomb=35;bio=100;rad=60;cold=60"
	siemens_coefficient = 0.6

/obj/item/clothing/head/helmet/space/void/chrono
	name = "chrono-helmet"
	desc = "From out of space and time, this helmet will protect you while you perform your duties."
	icon_state = "chronohelmet"
	item_state = "chronohelmet"

/obj/item/clothing/suit/space/void/chrono
	name = "chrono-suit"
	desc = "From out of space and time, this helmet will protect you while you perform your duties."
	icon_state = "chronosuit"
	item_state = "chronosuit"

/obj/item/clothing/suit/space/void/autolok
	name = "AutoLok pressure suit"
	desc = "A high-tech snug-fitting pressure suit. Fits any species. It offers very little physical protection, but is equipped with sensors that will automatically deploy the integral helmet to protect the wearer."
	icon_state = "autoloksuit"
	item_state = "autoloksuit"
	item_state_slots = list(slot_r_hand_str = "space_suit_syndicate", slot_l_hand_str = "space_suit_syndicate")
	armor_spec = "melee=15;bullet=5;laser=5;energy=5;bomb=5;bio=100;rad=80;cold=60"
	slowdown = 0.5
	siemens_coefficient = 1
	breach_threshold = 6 //this thing is basically tissue paper
	w_class = ITEMSIZE_NORMAL //if it's snug, high-tech, and made of relatively soft materials, it should be much easier to store!
	default_worn_icon = 'icons/inventory/suit/mob.dmi'
	sprite_sheets = ALL_SPRITE_SHEETS_SUIT_MOB
	sprite_sheets_obj = null
	hood = /obj/item/clothing/head/helmet/space/void/autolok // autoinstall the helmet

TYPE_TABLE(/obj/item/clothing/suit/space/void/autolok, fit_spec, list(REQ_FITS_BODYTYPES(list("exclude",SPECIES_DIONA,SPECIES_VOX))))

/// Screwdriver on a suit that is not worn: pick a component (the asks() step) and pop or detach it. The ledger read (is it on the actor?) is req_not_worn().
MSG_DEF_SELF(void/nothing_installed, "It does not have anything installed.")

/// Something a screwdriver can remove (a helmet, boots or a tank; the cooling unit is on the list but does not count on its own, as before).
/obj/item/clothing/suit/space/void/proc/has_removable_component(datum/act/op/A)
	return !!(hood || boots || tank)

/// What the question offers.
/obj/item/clothing/suit/space/void/proc/removable_components(datum/act/A)
	var/list/choices = list()
	for(var/obj/item/I in list(hood, boots, tank, cooler))
		choices += I
	return choices

/// The chosen component comes out.
/obj/item/clothing/suit/space/void/proc/remove_component(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	var/obj/item/choice = A.step_value("component")
	if(!choice || QDELETED(choice) || !tool)
		return OP_OK
	if(choice == tank)	//No, a switch doesn't work here. Sorry. ~Techhead
		to_chat(user, "You pop 	he [tank] out of 	he [src]'s storage compartment.")
		tank.forceMove(get_turf(src))
		playsound(src, tool.usesound, 50, 1)
		rel_take(src, nameof(tank))
	else if(choice == cooler)
		to_chat(user, "You pop 	he [cooler] out of 	he [src]'s storage compartment.")
		cooler.forceMove(get_turf(src))
		playsound(src, tool.usesound, 50, 1)
		rel_take(src, nameof(cooler))
	else if(choice == hood)
		to_chat(user, "You detach 	he [hood] from 	he [src]'s helmet mount.")
		remove_helmet()
		playsound(src, tool.usesound, 50, 1)
	else if(choice == boots)
		to_chat(user, "You detach 	he [boots] from 	he [src]'s boot mounts.")
		boots.forceMove(get_turf(src))
		playsound(src, tool.usesound, 50, 1)
		rel_take(src, nameof(boots))
	SStgui.update_uis(src)
	return OP_OK

/// The AutoLok's helmet is part of the suit: its screwdriver offers boots, tank and cooling unit.
/obj/item/clothing/suit/space/void/autolok/has_removable_component(datum/act/op/A)
	return !!(boots || tank || cooler)

/obj/item/clothing/suit/space/void/autolok/removable_components(datum/act/A)
	var/list/choices = list()
	for(var/obj/item/I in list(boots, tank, cooler))
		choices += I
	return choices

/obj/item/clothing/head/helmet/space/void/autolok
	name = "AutoLok pressure helmet"
	desc = "A rather close-fitting helmet designed to protect the wearer from hazardous conditions. Automatically deploys when the suit's sensors detect an environment that is hazardous to the wearer."
	icon_state = "autolokhelmet"
	item_state = "autolokhelmet"
	flags_inv = HIDEEARS|BLOCKHAIR //removed HIDEFACE/MASK/EYES flags so sunglasses or facemasks don't disappear. still gotta have BLOCKHAIR or it'll clip out tho.
	sprite_sheets = ALL_VR_SPRITE_SHEETS_HEAD_MOB
	sprite_sheets_obj = null

TYPE_TABLE(/obj/item/clothing/head/helmet/space/void/autolok, fit_spec, list(REQ_FITS_BODYTYPES(list("exclude",SPECIES_DIONA,SPECIES_VOX))))


/obj/item/clothing/head/helmet/space/void

/obj/item/clothing/suit/space/void


/obj/item/clothing/suit/space
	armor_spec = "cold=60"

	can_breach = 0 //disabling breaching as a general mechanic

/obj/item/clothing/suit/space/emergency
	can_breach = 1

/obj/item/clothing/suit/space/void
	can_breach = 0

/obj/item/clothing/suit/space/void/ownership()
	. = ..()
	. += owns(nameof(boots), policy = OWN_CONTAINED, starts = nameof(boots))
	. += owns(nameof(tank), policy = OWN_CONTAINED, starts = nameof(tank))
	. += owns(nameof(cooler), policy = OWN_CONTAINED)

/obj/item/clothing/head/helmet/space/void/heck/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image(icon, "hostile_env_glass", appearance_flags = RESET_COLOR))
