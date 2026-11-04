/*
 * Antagonist-specific gloves, such as traitor or ling-only types.
 */

// Thief - Traitor / Merc
/obj/item/clothing/gloves/sterile/thieves
	name = "sterile gloves"
	desc = "Sterile gloves."
	icon_state = "latex"
	item_state_slots = list(slot_r_hand_str = "white", slot_l_hand_str = "white")
	fingerprint_chance = 10 // They're thieves' gloves. What do you think?

// Pickpocketing is a chain of waits run as one op: a second's rummage, then by the touch's stance either opening their bag (help) or swapping a
// pocket (disarm: left, grab: right) as take-theirs, give-yours. The gloves hold the op; the person touched is its "victim". Each lap's end acts
// (pickpocket_phase_done) and names the next wait, if any, in the op's arguments: phase ("rummage", "open", "take" or "give"), wait, slot_id,
// slot, took, theirs and mine.
CAPABILITIES(/obj/item/clothing/gloves/sterile/thieves)
	configure(atom_rules(description_antag = "These gloves are uniquely suited for stealing, as well as breaking and entering. They have minor insulation.\
	Touching someone out of combat mode will open their backpack, if it exists, or their belt if they have no backpack, allowing you to deposit\
	items into the inventories. Be careful about making too much noise.\
	Touching with Disarm will swap the items in your LEFT pockets. Grab will swap RIGHT pockets."))
	configure(item_protection(siemens = 0.5, permeability = 0.01))
	op("pickpocket", ai(), takes("victim", "stance", "victim_loc"), wait(PROC_REF(pickpocket_wait), keeps = STAY | ALIVE, repeats = PROC_REF(pickpocket_more), after_step = PROC_REF(pickpocket_phase_done)), on_interrupt(PROC_REF(pickpocket_interrupted)), then(PROC_REF(pickpocket_finished)))

/// The chain ended; every stage acted as its lap ended.
/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_finished(datum/act/op/A)
	return OP_OK

/// How long the current wait of the chain is: a second for the rummage and the swaps, longer for opening a belt.
/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_wait(datum/act/op/A)
	return A.arg("wait") || 1 SECOND

/// Another wait follows when the lap that ended named one.
/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_more(datum/act/op/A)
	return !!A.arg("more")

/// The next wait of the chain, with this one's state.
/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_next(datum/act/op/A, next, wait)
	LAZYSET(A.args, "phase", next)
	LAZYSET(A.args, "wait", wait)
	LAZYSET(A.args, "more", TRUE)

/// The wait that just ended did its work, and the chain goes on or stops. The person touched stepping off or going ends the chain like the user moving.
/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_phase_done(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	var/mob/living/carbon/human/victim = A.arg("victim")
	LAZYSET(A.args, "more", FALSE)
	if(QDELETED(victim) || victim.loc != A.arg("victim_loc"))
		pickpocket_interrupted(A)
		return
	var/stance = A.arg("stance") || I_HURT
	var/slot_id = A.arg("slot_id")
	switch(A.arg("phase") || "rummage")
		if("rummage")
			if(stance != I_HURT && (turn(victim.dir, 180) == get_dir(user, victim)))
				to_chat(victim, span_warning("[user] rifles in your pockets!"))
			if(stance == I_HELP)
				if(istype(victim.get_equipped_item(SLOT_ID_BACK), /obj/item/storage))
					LAZYSET(A.args, "slot_id", SLOT_ID_BACK)
					pickpocket_next(A, "open", 3 SECONDS)
				else if(istype(victim.get_equipped_item(SLOT_ID_BELT), /obj/item/storage))
					LAZYSET(A.args, "slot_id", SLOT_ID_BELT)
					pickpocket_next(A, "open", 5 SECONDS)
				return
			if(stance == I_DISARM)
				slot_id = SLOT_ID_POCKET_L
			else if(stance == I_GRAB)
				slot_id = SLOT_ID_POCKET_R
			else
				return
			LAZYSET(A.args, "slot_id", slot_id)
			LAZYSET(A.args, "slot", slot_id)
			var/obj/item/pocketed = victim.get_equipped_item(slot_id)
			if(istype(pocketed))
				LAZYSET(A.args, "theirs", pocketed)
				pickpocket_next(A, "take", 1 SECOND)
			else
				pickpocket_give(A)
		if("open")
			var/obj/item/storage/S = victim.get_equipped_item(slot_id)
			if(istype(S))
				S.open(user)
		if("take")
			var/obj/item/theirs = A.arg("theirs")
			if(victim.get_equipped_item(slot_id) != theirs)
				return
			victim.drop_from_inventory(theirs)
			LAZYSET(A.args, "took", theirs)
			LAZYSET(A.args, "theirs", null)
			pickpocket_give(A)
		if("give")
			pickpocket_swapped(A, TRUE)

/// Slipping your own pocket item into theirs: a second of holding still.
/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_give(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	var/obj/item/own_pocket = user.get_equipped_item(A.arg("slot_id"))
	if(!istype(own_pocket))
		pickpocket_swapped(A, FALSE)
		return
	LAZYSET(A.args, "mine", own_pocket)
	pickpocket_next(A, "give", 1 SECOND)

/// An interrupted give still keeps what was taken.
/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_interrupted(datum/act/op/A)
	if(A.arg("phase") == "give")
		pickpocket_swapped(A, FALSE)

/obj/item/clothing/gloves/sterile/thieves/proc/pickpocket_swapped(datum/act/op/A, gave)
	var/mob/living/carbon/human/user = A.actor
	var/mob/living/carbon/human/victim = A.arg("victim")
	var/obj/item/mine = A.arg("mine")
	var/obj/item/took = A.arg("took")
	var/slot = A.arg("slot")
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
		perform_op(user, src, "pickpocket", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("victim" = A, "stance" = stance, "victim_loc" = A.loc))
		return 1
	return 0
