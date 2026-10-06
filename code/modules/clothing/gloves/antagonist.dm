/*
 * Antagonist-specific gloves, such as traitor or ling-only types.
 */

// Thief - Traitor / Merc
/obj/item/clothing/gloves/sterile/thieves
	name = "sterile gloves"
	desc = "Sterile gloves."
	description_antag = "These gloves are uniquely suited for stealing, as well as breaking and entering. They have minor insulation.\
	Touching someone out of combat mode will open their backpack, if it exists, or their belt if they have no backpack, allowing you to deposit\
	items into the inventories. Be careful about making too much noise.\
	Touching with Disarm will swap the items in your LEFT pockets. Grab will swap RIGHT pockets."
	icon_state = "latex"
	item_state_slots = list(slot_r_hand_str = "white", slot_l_hand_str = "white")
	siemens_coefficient = 0.5 // Not perfect, but slightly more protective than nothing.
	permeability_coefficient = 0.01
	germ_level = 0
	fingerprint_chance = 10 // They're thieves' gloves. What do you think?

/// Pickpocketing is a chain of timed tasks: a second's rummage, then by the touch's stance either opening their bag (help) or swapping a
/// pocket (disarm: left, grab: right) as take-theirs, give-yours. Each wait is a task carrying the chain's state into the next.
/datum/task/timed/pickpocket
	name = "pickpocket"
	complete_proc = /datum/task/timed/pickpocket/proc/phase_done
	cancel_proc = /datum/task/timed/pickpocket/proc/phase_interrupted
	/// Which wait this is: "rummage", "open", "take" or "give".
	var/phase = "rummage"
	/// The stance of the touch that started it (I_HELP, I_DISARM, I_GRAB or I_HURT).
	var/stance = I_HURT
	/// The pocket being swapped (slot id and equip slot).
	var/slot_id
	var/slot
	/// What was taken from them, what is being taken, and the user's own pocket item being slipped in.
	var/obj/item/took
	var/obj/item/theirs
	var/obj/item/mine
	unheld = list("took")

/// The next wait of the chain, with this one's state.
/datum/task/timed/pickpocket/proc/next_phase(next, wait, progress = TRUE)
	task_start(/datum/task/timed/pickpocket, actor, target, duration = wait, progress = progress, phase = next, stance = stance, slot_id = slot_id, slot = slot, took = took, theirs = theirs, mine = mine)

/datum/task/timed/pickpocket/proc/phase_done()
	var/mob/living/carbon/human/user = actor
	var/mob/living/carbon/human/victim = target
	switch(phase)
		if("rummage")
			if(stance != I_HURT && (turn(victim.dir, 180) == get_dir(user, victim)))
				to_chat(victim, span_warning("[user] rifles in your pockets!"))
			if(stance == I_HELP)
				if(istype(victim.get_equipped_item(SLOT_ID_BACK), /obj/item/storage))
					slot_id = SLOT_ID_BACK
					next_phase("open", 3 SECONDS, FALSE)
				else if(istype(victim.get_equipped_item(SLOT_ID_BELT), /obj/item/storage))
					slot_id = SLOT_ID_BELT
					next_phase("open", 5 SECONDS)
				return
			if(stance == I_DISARM)
				slot_id = SLOT_ID_POCKET_L
				slot = SLOT_ID_POCKET_L
			else if(stance == I_GRAB)
				slot_id = SLOT_ID_POCKET_R
				slot = SLOT_ID_POCKET_R
			else
				return
			var/obj/item/pocketed = victim.get_equipped_item(slot_id)
			if(istype(pocketed))
				theirs = pocketed
				next_phase("take", 1 SECOND)
			else
				give()
		if("open")
			var/obj/item/storage/S = victim.get_equipped_item(slot_id)
			if(istype(S))
				S.open(user)
		if("take")
			if(victim.get_equipped_item(slot_id) != theirs)
				return
			victim.drop_from_inventory(theirs)
			took = theirs
			theirs = null
			give()
		if("give")
			swapped(TRUE)

/// Slipping your own pocket item into theirs: a second of holding still.
/datum/task/timed/pickpocket/proc/give()
	var/mob/living/carbon/human/user = actor
	var/obj/item/own_pocket = user.get_equipped_item(slot_id)
	if(!istype(own_pocket))
		swapped(FALSE)
		return
	mine = own_pocket
	next_phase("give", 1 SECOND)

/// An interrupted give still keeps what was taken.
/datum/task/timed/pickpocket/proc/phase_interrupted()
	if(phase == "give")
		swapped(FALSE)

/datum/task/timed/pickpocket/proc/swapped(gave)
	var/mob/living/carbon/human/user = actor
	var/mob/living/carbon/human/victim = target
	if(!user || QDELETED(user))
		return
	// Taking something leaves the user's own pocket item in bluespace: it drops.
	if(mine && (gave || took))
		user.drop_from_inventory(mine)
	if(took && !QDELETED(took))
		user.equip_to_slot(took, slot)
	if(gave && victim && !QDELETED(victim))
		victim.equip_to_slot(mine, slot)

/obj/item/clothing/gloves/sterile/thieves/Touch(atom/A, proximity, stance = I_HURT, mob/user)
	if(proximity && ishuman(user) && ishuman(A))
		task_start(/datum/task/timed/pickpocket, user, A, duration = 1 SECOND, stance = stance)
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

/obj/item/clothing/gloves/ring/buzzer/get_cell()
	return battery

CAPABILITIES(/obj/item/clothing/gloves/ring/buzzer)
	owns_one(nameof(battery), starts = nameof(battery_type))

/obj/item/clothing/gloves/ring/buzzer/Touch(atom/A, proximity, stance = I_HURT, mob/user)
	if(proximity && istype(user, /mob/living/carbon/human))
		return zap(user, A, proximity, stance)
	return 0

/obj/item/clothing/gloves/ring/buzzer/proc/zap(mob/living/carbon/human/user, atom/movable/target, proximity, stance = I_HURT)
	. = FALSE
	if(stance == I_HURT && battery.percent() >= 50)
		if(isliving(target))
			var/mob/living/L = target

			if(ishuman(L) && battery.percent() >= 90)	// Silent text-wise, for maximum potential for gimmicks.
				var/mob/living/carbon/human/H = L

				if(H.stat == DEAD)
					. = TRUE

					do_defib(H)

			to_chat(L, span_warning("You feel a powerful shock!"))
			if(!.)
				play_sfx(L, SFX_EFFECTS_SPARKS7)
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
	H.status_at_least(STAT_WEAKENED, rand(10,25))

	battery.emp_act(1)
