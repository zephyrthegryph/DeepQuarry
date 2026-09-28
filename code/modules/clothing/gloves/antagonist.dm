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

/// Pickpocketing is one flow: a second's rummage, then by intent either opening their bag
/// (help) or swapping a pocket (disarm: left, grab: right) as take-theirs, give-yours.
/datum/om/flow/pickpocket
	name = "pickpocket"
	/// The pocket being swapped (slot id and equip slot).
	var/slot_id
	var/slot
	/// What was taken from them, and the user's own pocket item being slipped in.
	var/obj/item/took
	var/obj/item/theirs
	var/obj/item/mine
	/// TRUE while giving: an interrupted give still keeps what was taken.
	var/giving = FALSE

/datum/om/flow/pickpocket/start()
	wait(1 SECOND, PROC_REF(rummaged))

/datum/om/flow/pickpocket/proc/rummaged()
	var/mob/living/carbon/human/user = actor
	var/mob/living/carbon/human/victim = target
	if(!IS_HARMING(user) && (turn(victim.dir, 180) == get_dir(user, victim)))
		to_chat(victim, span_warning("[user] rifles in your pockets!"))
	if(IS_HELPING(user))
		if(istype(victim.get_equipped_item(SLOT_ID_BACK), /obj/item/storage))
			slot_id = SLOT_ID_BACK
			wait(3 SECONDS, PROC_REF(open_storage), progress = FALSE)
		else if(istype(victim.get_equipped_item(SLOT_ID_BELT), /obj/item/storage))
			slot_id = SLOT_ID_BELT
			wait(5 SECONDS, PROC_REF(open_storage))
		return
	if(IS_DISARMING(user))
		slot_id = SLOT_ID_POCKET_L
		slot = slot_l_store
	else if(IS_GRABBING(user))
		slot_id = SLOT_ID_POCKET_R
		slot = slot_r_store
	else
		return
	theirs = victim.get_equipped_item(slot_id)
	if(istype(theirs))
		wait(1 SECOND, PROC_REF(take))
	else
		theirs = null
		give()

/datum/om/flow/pickpocket/proc/open_storage()
	var/mob/living/carbon/human/victim = target
	var/obj/item/storage/S = victim.get_equipped_item(slot_id)
	if(istype(S))
		S.open(actor)

/datum/om/flow/pickpocket/proc/take()
	var/mob/living/carbon/human/victim = target
	if(victim.get_equipped_item(slot_id) != theirs)
		return
	victim.drop_from_inventory(theirs)
	took = theirs
	theirs = null
	give()

/// Slipping your own pocket item into theirs: a second of holding still.
/datum/om/flow/pickpocket/proc/give()
	var/mob/living/carbon/human/user = actor
	mine = user.get_equipped_item(slot_id)
	if(!istype(mine))
		mine = null
		swapped(FALSE)
		return
	giving = TRUE
	wait(1 SECOND, PROC_REF(gave))

/datum/om/flow/pickpocket/proc/gave()
	swapped(TRUE)

/datum/om/flow/pickpocket/ended(reason)
	if(giving)
		swapped(FALSE)

/datum/om/flow/pickpocket/proc/swapped(gave)
	var/mob/living/carbon/human/user = actor
	var/mob/living/carbon/human/victim = target
	giving = FALSE
	if(!user)
		return
	// Taking something leaves the user's own pocket item in bluespace: it drops.
	if(mine && (gave || took))
		user.drop_from_inventory(mine)
	if(took)
		user.equip_to_slot(took, slot)
	if(gave && victim)
		victim.equip_to_slot(mine, slot)

/obj/item/clothing/gloves/sterile/thieves/Touch(atom/A, proximity)
	if(proximity && ishuman(usr) && ishuman(A))
		om_flow_start(/datum/om/flow/pickpocket, usr, A)
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
// The battery is built in (nothing removes it): it goes with the ring, not onto the floor.
REF_OWNED(/obj/item/clothing/gloves/ring/buzzer, "battery")

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
