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

/datum/om/task/timed/thieves_pickpocket
	duration = 1 SECOND
	complete_proc = /obj/item/clothing/gloves/sterile/thieves/proc/pickpocket
	var/proximity

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket(datum/om/task/timed/thieves_pickpocket/task)
	var/mob/living/carbon/human/user = task.actor
	var/mob/living/carbon/human/target = task.target
	var/proximity = task.proximity
	if(!proximity || !user || !target)
		return 0

	if(!istype(target))
		return 0

	if(!IS_HARMING(user) && (turn(target.dir, 180) == get_dir(user, target)))
		to_chat(target, span_warning("[user] rifles in your pockets!"))

	if(IS_HELPING(user))
		if(istype(target.get_equipped_item(SLOT_ID_BACK),/obj/item/storage))
			om_task_start(/datum/om/task/timed/thieves_pickpocket_open, user, target, list("receiver" = src, "duration" = 3 SECONDS, "slot_id" = SLOT_ID_BACK, "progress" = FALSE))
		else if(istype(target.get_equipped_item(SLOT_ID_BELT), /obj/item/storage))
			om_task_start(/datum/om/task/timed/thieves_pickpocket_open, user, target, list("receiver" = src, "duration" = 5 SECONDS, "slot_id" = SLOT_ID_BELT))
		return 1

	if(IS_DISARMING(user))
		om_task_start(/datum/om/task/timed/thieves_pickpocket_take, user, target, list("receiver" = src, "slot_id" = SLOT_ID_POCKET_L, "slot" = slot_l_store))
		return 1

	if(IS_GRABBING(user))
		om_task_start(/datum/om/task/timed/thieves_pickpocket_take, user, target, list("receiver" = src, "slot_id" = SLOT_ID_POCKET_R, "slot" = slot_r_store))
		return 1

/datum/om/task/timed/thieves_pickpocket_open
	complete_proc = /obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_open
	var/slot_id

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_open(datum/om/task/timed/thieves_pickpocket_open/task)
	var/mob/living/carbon/human/user = task.actor
	var/mob/living/carbon/human/target = task.target
	var/slot_id = task.slot_id
	var/obj/item/storage/S = target.get_equipped_item(slot_id)
	if(istype(S))
		S.open(user)

// Swapping pocket contents is three timed actions: a rummage, taking theirs, giving yours.
/datum/om/task/timed/thieves_pickpocket_take
	duration = 1 SECOND
	complete_proc = /obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_take
	var/slot_id
	var/slot

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_take(datum/om/task/timed/thieves_pickpocket_take/task)
	var/mob/living/carbon/human/user = task.actor
	var/mob/living/carbon/human/target = task.target
	var/slot_id = task.slot_id
	var/slot = task.slot
	var/obj/item/theirs = target.get_equipped_item(slot_id)
	if(istype(theirs))
		om_task_start(/datum/om/task/timed/thieves_pickpocket_took, user, target, list("receiver" = src, "slot_id" = slot_id, "slot" = slot, "theirs" = theirs))
	else
		pickpocket_give(user, target, slot_id, slot, null)

/datum/om/task/timed/thieves_pickpocket_took
	duration = 1 SECOND
	complete_proc = /obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_took
	var/slot_id
	var/slot
	var/obj/item/theirs

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_took(datum/om/task/timed/thieves_pickpocket_took/task)
	var/mob/living/carbon/human/user = task.actor
	var/mob/living/carbon/human/target = task.target
	var/slot_id = task.slot_id
	var/slot = task.slot
	var/obj/item/theirs = task.theirs
	if(target.get_equipped_item(slot_id) != theirs)
		return
	target.drop_from_inventory(theirs)
	pickpocket_give(user, target, slot_id, slot, theirs)

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_give(mob/living/carbon/human/user, mob/living/carbon/human/target, slot_id, slot, obj/item/took)
	var/obj/item/mine = user.get_equipped_item(slot_id)
	if(istype(mine))
		om_task_start(/datum/om/task/timed/pickpocket_swap, user, target, list("receiver" = src, "slot" = slot, "took" = took, "mine" = mine))
	else
		pickpocket_swapped(user, target, slot, took, null, FALSE)

/// Slipping your own pocket item into theirs after taking: a second of holding still.
/datum/om/task/timed/pickpocket_swap
	duration = 1 SECOND
	complete_proc = /obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_gave
	cancel_proc = /obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_kept
	var/slot
	var/obj/item/took
	var/obj/item/mine

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_gave(datum/om/task/timed/pickpocket_swap/task)
	pickpocket_swapped(task.actor, task.target, task.slot, task.took, task.mine, TRUE)

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_kept(datum/om/task/timed/pickpocket_swap/task)
	pickpocket_swapped(task.actor, task.target, task.slot, task.took, task.mine, FALSE)

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_swapped(mob/living/carbon/human/user, mob/living/carbon/human/target, slot, obj/item/took, obj/item/mine, gave)
	if(!user)
		return
	// Taking something leaves the user's own pocket item in bluespace: it drops.
	if(mine && (gave || took))
		user.drop_from_inventory(mine)
	if(took)
		user.equip_to_slot(took, slot)
	if(gave && target)
		target.equip_to_slot(mine, slot)

/obj/item/clothing/gloves/sterile/thieves/Touch(atom/A, proximity)
	if(proximity && ishuman(usr) && ishuman(A))
		om_task_start(/datum/om/task/timed/thieves_pickpocket, usr, A, list("receiver" = src, "proximity" = proximity))
		return 1
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

	if(H.return_from_death("buzzer ring", src, REVIVE_UNCONSCIOUS) != TRUE)
		return 0

	H.emote("gasp")
	H.status_at_least(EFFECT_WEAKENED, rand(10,25))

	battery.emp_act(1)
