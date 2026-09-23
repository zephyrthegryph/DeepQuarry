/*
 * Antagonist-specific gloves, such as traitor or ling-only types.
 */

// Thief - Traitor / Merc
/obj/item/clothing/gloves/sterile/thieves
	name = "sterile gloves"
	desc = "Sterile gloves."
	description_antag = "These gloves are uniquely suited for stealing, as well as breaking and entering. They have minor insulation.\
	Attempting to 'help' someone will open their backpack, if it exists, or their belt if they have no backpack, allowing you to deposit\
	items into the inventories. Be careful about making too much noise.\
	Disarm intent will swap the items in your LEFT pockets. Grab will swap RIGHT pockets."
	icon_state = "latex"
	item_state_slots = list(slot_r_hand_str = "white", slot_l_hand_str = "white")
	siemens_coefficient = 0.5 // Not perfect, but slightly more protective than nothing.
	permeability_coefficient = 0.01
	germ_level = 0
	fingerprint_chance = 10 // They're thieves' gloves. What do you think?

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket(mob/living/carbon/human/user, mob/living/carbon/human/target, proximity)
	if(!proximity || !user || !target)
		return 0

	if(!istype(target))
		return 0

	if(!IS_HARMING(user) && (turn(target.dir, 180) == get_dir(user, target)))
		to_chat(target, span_warning("[user] rifles in your pockets!"))

	if(IS_HELPING(user))
		if(istype(target.get_equipped_item(SLOT_ID_BACK),/obj/item/storage) && do_after(user, 3 SECONDS, target, progress = FALSE))
			var/obj/item/storage/Backpack = target.get_equipped_item(SLOT_ID_BACK)
			Backpack.open(user)
		else if(istype(target.get_equipped_item(SLOT_ID_BELT), /obj/item/storage) && do_after(user, 5 SECONDS, target))
			var/obj/item/storage/Belt = target.get_equipped_item(SLOT_ID_BELT)
			Belt.open(user)
		return 1

	if(IS_DISARMING(user))
		var/obj/item/LTarg = target.get_equipped_item(SLOT_ID_L_STORE)
		var/obj/item/LUser = user.get_equipped_item(SLOT_ID_L_STORE)

		if(do_after(user, 1 SECOND, target))
			var/took = istype(LTarg) && do_after(user, 1 SECOND, target)
			target.drop_from_inventory(LTarg)
			var/gave = istype(LUser) && do_after(user, 1 SECOND, target)
			// Taking something leaves the user's own pocket item in bluespace: it drops.
			if(gave || (took && istype(LUser)))
				user.drop_from_inventory(LUser)
			if(took)
				user.equip_to_slot(LTarg, slot_l_store)
			if(gave)
				target.equip_to_slot(LUser, slot_l_store)

		return 1

	if(IS_GRABBING(user))
		var/obj/item/RTarg = target.get_equipped_item(SLOT_ID_R_STORE)
		var/obj/item/RUser = user.get_equipped_item(SLOT_ID_R_STORE)

		if(do_after(user, 1 SECOND, target))
			var/took = istype(RTarg) && do_after(user, 1 SECOND, target)
			target.drop_from_inventory(RTarg)
			var/gave = istype(RUser) && do_after(user, 1 SECOND, target)
			// Taking something leaves the user's own pocket item in bluespace: it drops.
			if(gave || (took && istype(RUser)))
				user.drop_from_inventory(RUser)
			if(took)
				user.equip_to_slot(RTarg, slot_r_store)
			if(gave)
				target.equip_to_slot(RUser, slot_r_store)

		return 1

/obj/item/clothing/gloves/sterile/thieves/Touch(atom/A, proximity)
	if(proximity && ishuman(usr) && ishuman(A) && do_after(usr, 1 SECOND, target = A))
		return pickpocket(usr, A, proximity)
	return 0


// Buzzer Ring - Traitor, Merc.
/obj/item/clothing/gloves/ring/buzzer
	name = "ring"
	desc = "A plain metal band."
	description_antag = "This morphium-alloy ring continually generates an electric field, capable of electrocuting a target while not injuring the wearer.\
	The device is also capable of 'frankenstein'-ing a corpse, long after normal technology would be able to save them. The body will still be tied to the\
	normal damage limits for survival, however, so care must be taken."
	icon_state = "material"
	var/battery_type = /obj/item/cell/device/weapon/recharge
	var/obj/item/cell/battery = null

/obj/item/clothing/gloves/ring/buzzer/get_cell()
	return battery

/obj/item/clothing/gloves/ring/buzzer/Initialize(mapload)
	. = ..()
	if(!battery)
		battery = new battery_type(src)

/obj/item/clothing/gloves/ring/buzzer/Touch(atom/A, proximity)
	if(proximity && istype(usr, /mob/living/carbon/human))
		return zap(usr, A, proximity)
	return 0

/obj/item/clothing/gloves/ring/buzzer/proc/zap(mob/living/carbon/human/user, atom/movable/target, proximity)
	. = FALSE
	if(IS_HARMING(user) && battery.percent() >= 50)
		if(isliving(target))
			var/mob/living/L = target

			if(ishuman(L) && battery.percent() >= 90)	// Silent text-wise, for maximum potential for gimmicks.
				var/mob/living/carbon/human/H = L

				if(H.stat == DEAD)
					. = TRUE

					do_defib(H)

			to_chat(L, span_warning("You feel a powerful shock!"))
			if(!.)
				playsound(L, 'sound/effects/sparks7.ogg', 40, 1)
				L.electrocute_act(battery.percent() * 0.25, src)
				battery.emp_act(2)
			return .

	return 0

/obj/item/clothing/gloves/ring/buzzer/proc/do_defib(mob/living/carbon/human/H = null)
	if(!istype(H))
		return 0

	GLOB.dead_mob_list.Remove(H)
	if((H in GLOB.living_mob_list) || (H in GLOB.dead_mob_list))
		WARNING("Mob [H] was ring-defibbed but already in the living or dead list still!")
	GLOB.living_mob_list += H

	H.timeofdeath = 0
	H.set_stat(UNCONSCIOUS)
	H.failed_last_breath = 0
	H.reload_fullscreen()

	H.emote("gasp")
	H.Weaken(rand(10,25))

	battery.emp_act(1)
