/atom/movable/screen/alert/leash_dom
	name = "Leash Holder"
	desc = "You're holding a leash, with someone on the end."
	icon_state = "leash_master"

/atom/movable/screen/alert/leash_dom/Click()
	var/obj/item/leash/owner = master_ref?.resolve()
	if(owner)
		owner.unleash()

/atom/movable/screen/alert/leash_pet
	name = "Leashed"
	desc = "You're on the hook now!"
	icon_state = "leash_pet"

/atom/movable/screen/alert/leash_pet/Click()
	var/obj/item/leash/owner = master_ref?.resolve()
	if(owner)
		owner.struggle_leash()

///// RELATIONS /////
// A leash is two edges, and they are its whole state: pet -> leash
// (leashed_to) and leash -> the mob holding it (leash_held_by). LEASH_PET(),
// LEASH_MASTER() and LEASH_OF() (om.dm) read them. Deleting any of the three
// ends the leash, and dropping either edge drops the other; the hooks below
// do the alerts, the slowdown and the movement listeners.

/datum/om/relation/leashed_to
	name = "leash"
	source_single = TRUE
	target_single = TRUE
	conflict = OM_REL_REFUSE

/datum/om/relation/leashed_to/on_link(mob/living/source, obj/item/leash/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(!istype(source) || !istype(target))
		return
	source.add_modifier(/datum/modifier/leash)
	source.throw_alert("leashed", /atom/movable/screen/alert/leash_pet, new_master = target)
	target.RegisterSignal(source, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/obj/item/leash, on_pet_move))
	START_PROCESSING(SSobj, target)

/datum/om/relation/leashed_to/on_unlink(mob/living/source, obj/item/leash/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(source) && !QDELETED(source))
		source.clear_alert("leashed")
		source.remove_a_modifier_of_type(/datum/modifier/leash)
	if(istype(target))
		target.UnregisterSignal(source, COMSIG_MOVABLE_MOVED)
		STOP_PROCESSING(SSobj, target)
		// No pet, no leash: let go of the holder too.
		var/mob/living/master = LEASH_MASTER(target)
		if(master)
			om_unlink(target, master, /datum/om/relation/leash_held_by)

/datum/om/relation/leash_held_by
	name = "leash holder"
	source_single = TRUE

/datum/om/relation/leash_held_by/on_link(obj/item/leash/source, mob/living/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(!istype(source) || !istype(target))
		return
	target.throw_alert("leash", /atom/movable/screen/alert/leash_dom, new_master = source)
	source.RegisterSignal(target, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/obj/item/leash, on_master_move))

/datum/om/relation/leash_held_by/on_unlink(obj/item/leash/source, mob/living/target, datum/om/edge/edge)
	SHOULD_NOT_SLEEP(TRUE)
	if(istype(target) && !QDELETED(target))
		target.clear_alert("leash")
	if(istype(source))
		source.UnregisterSignal(target, COMSIG_MOVABLE_MOVED)
		// No holder, no leash: the pet is free.
		var/mob/living/pet = LEASH_PET(source)
		if(pet)
			om_unlink(pet, source, /datum/om/relation/leashed_to)

///// OBJECT /////
//The leash object itself
/obj/item/leash
	name = "leash"
	desc = "A simple tether that can easily be hooked onto a collar. Usually used to keep pets nearby."
	icon = 'icons/obj/leash.dmi'
	icon_state = "leash"
	item_state = "leash"
	throw_range = 4
	slot_flags = SLOT_TIE
	force = 1
	throwforce = 1
	w_class = ITEMSIZE_SMALL

/obj/item/leash/process()
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_pet || !leash_master) //If there is no pet, there is no dom. Loop breaks.
		clear_leash()
		return

	if(!leash_pet.mind) //in the extremely niche case a sentient simplemob is leashed, and then ghosts, use this
		clear_leash()
		return

	if(leash_pet.absorbed) //Glrk'd
		clear_leash()
		return
	if(!is_wearing_collar(leash_pet) && istype(leash_pet, /mob/living/carbon/human)) //The pet has slipped their collar and is not the pet anymore.
		leash_pet.visible_message(
			span_warning("[leash_pet] has slipped out of [leash_pet.p_their()] collar!"),
			span_warning("You have slipped out of your collar!")
		)
		clear_leash()
		return

//Called when someone is clicked with the leash
/obj/item/leash/attack(mob/living/C, mob/living/user, target_zone, attack_modifier) //C is the target, user is the one with the leash
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(LEASH_OF(C)) //If the pet is already leashed, do not leash them. For the love of god.
		// If they re-click, remove the leash
		if (C == leash_pet && user == leash_master)
			unleash()
			return ITEM_INTERACT_SUCCESS
		else
			// Dear god not the double leashing
			to_chat(user, span_notice("[C] has already been leashed."))
			return ITEM_INTERACT_FAILURE

	if(!C.mind)
		return ITEM_INTERACT_FAILURE

	if(C == user)
		to_chat(user, span_notice("You cannot leash yourself!"))
		return ITEM_INTERACT_FAILURE

	var/leashtime = 35

	if(istype(C, /mob/living/carbon/human))
		var/mob/living/carbon/human/humantarget = C
		if (!is_wearing_collar(humantarget))
			to_chat(user, span_notice("[humantarget] needs a collar before you can attach a leash to it."))
			return ITEM_INTERACT_FAILURE
		if(humantarget.get_equipped_item(SLOT_ID_HANDCUFFED))
			leashtime = 5

	C.visible_message(span_danger("\The [user] is attempting to put the leash on \the [C]!"), span_danger("\The [user] tries to put a leash on you"))
	add_attack_logs(user,C,"Leashed (attempt)")
	om_do_after(user, leashtime, target = C, receiver = src, on_done = PROC_REF(attack_timed_done), done_args = list(C, user))
	return TRUE

/obj/item/leash/proc/attack_timed_done(mob/living/C, mob/living/user)
	if(tgui_alert(C, "Would you like to be leased by [user]? You can OOC escape to escape", "Become Leashed",list("No","Yes")) != "Yes")
		return ITEM_INTERACT_FAILURE
	if(QDELETED(C) || QDELETED(user) || LEASH_OF(C))
		return ITEM_INTERACT_FAILURE

	// This leash may still be on someone else: that one ends here.
	clear_leash()
	if(!istype(om_link(C, src, /datum/om/relation/leashed_to), /datum/om/edge))
		return ITEM_INTERACT_FAILURE
	om_link(src, user, /datum/om/relation/leash_held_by)

	C.visible_message(span_danger("\The [user] puts a leash on \the [C]!"), span_danger("The leash clicks onto your collar!"))
	to_chat(C, span_userdanger("You have been leashed!"))
	to_chat(C, span_danger("(You can use OOC escape to detach the leash)"))
	return ITEM_INTERACT_SUCCESS

//Called when the leash is used in hand
//Tugs the pet closer
/obj/item/leash/attack_self(mob/living/user)
	. = ..(user)
	if(.)
		return TRUE
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_pet || !leash_master) //No pet, no tug.
		return
	if(leash_pet.absorbed) //Glrk'd.
		clear_leash()
		return
	//Yank the pet. Yank em in close.
	apply_tug_mob_to_mob(leash_pet, leash_master, 1)

/obj/item/leash/proc/on_master_move()
	SIGNAL_HANDLER
	var/mob/living/leash_pet = LEASH_PET(src)
	//Make sure the dom still has a pet
	if(!LEASH_MASTER(src) || !leash_pet)
		return
	if(leash_pet.absorbed)
		clear_leash()
		return
	addtimer(CALLBACK(src, PROC_REF(after_master_move)), 0.2 SECONDS)

/obj/item/leash/proc/after_master_move()
	//If the master moves, pull the pet in behind
	//Also, the timer means that the distance check for master happens before the pet, to prevent both from proccing.
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_master || !leash_pet) //Just to stop error messages
		return
	apply_tug_mob_to_mob(leash_pet, leash_master, 2)

	//Knock the pet over if they get further behind. Shouldn't happen too often.
	om_after(src, 0.3 SECONDS, PROC_REF(leash_trip_check)) //This way running normally won't just yank the pet to the ground.

/obj/item/leash/proc/leash_trip_check()
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_master || !leash_pet || leash_pet.absorbed) //Just to stop error messages. Break the loop early if something removed the master
		clear_leash()
		return
	if(get_dist(leash_pet, leash_master) > 3 && !leash_pet.has_status(EFFECT_STUNNED))
		leash_pet.visible_message(
			span_warning("[leash_pet] is pulled to the ground by [leash_pet.p_their()] leash!"),
			span_warning("You are pulled to the ground by your leash!")
		)
		leash_pet.apply_effect(5, STUN, 0)

	//This code is to check if the pet has gotten too far away, and then break the leash.
	om_after(src, 0.3 SECONDS, PROC_REF(leash_snap_check)) //Wait to snap the leash

/obj/item/leash/proc/leash_snap_check()
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_master || !leash_pet || leash_pet.absorbed) //Just to stop error messages
		clear_leash()
		return
	if(get_dist(leash_pet, leash_master) > 5)
		leash_pet.visible_message(
			span_warning("The leash snaps free from [leash_pet]'s collar!"),
			span_warning("Your leash pops from your collar!")
		)
		leash_pet.apply_effect(5, STUN, 0)
		leash_pet.body?.add_restriction(src, BF_AIRWAY, 0.2, 5 SECONDS) // the collar yanks the throat shut
		clear_leash()

/obj/item/leash/proc/on_pet_move()
	SIGNAL_HANDLER
	//This should only work if there is a pet and a master.
	if(!LEASH_MASTER(src) || !LEASH_PET(src))
		return

	//If the pet gets too far away, they get tugged back
	addtimer(CALLBACK(src, PROC_REF(after_pet_move)), 0.3 SECONDS) //A short timer so the pet kind of bounces back after they make the step

/obj/item/leash/proc/after_pet_move()
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_master || !leash_pet || leash_pet.absorbed)
		return
	for(var/i in 3 to get_dist(leash_pet, leash_master)) // Move the pet to a minimum of 2 tiles away from the master, so the pet trails behind them.
		step_towards(leash_pet, leash_master)

/obj/item/leash/dropped(mob/user, equipping, slot)
	//Drop the leash, and the leash effects stop
	. = ..()
	var/mob/living/leash_pet = LEASH_PET(src)
	if(!leash_pet || !LEASH_MASTER(src) || leash_pet.absorbed) //There is no pet. Stop this silliness
		clear_leash()
		return
	//Dropping procs any time the leash changes slots. So, we will wait a tick and see if the leash was actually dropped
	addtimer(CALLBACK(src, PROC_REF(drop_effects), user), 0.1 SECONDS)

/obj/item/leash/proc/drop_effects(mob/user)
	SIGNAL_HANDLER
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(leash_master && (leash_master.item_is_in_hands(src) || leash_master.get_item_by_slot(SLOT_TIE) == src))
		return  //Dom still has the leash as it turns out. Cancel the proc.
	if(leash_master)
		leash_master.visible_message(span_notice("\The [leash_master] drops \the [src]."), span_notice("You drop \the [src]."))
	//DOM HAS DROPPED LEASH. PET IS FREE. SCP HAS BREACHED CONTAINMENT.
	clear_leash()

/// Ends the leash. Unlinking either edge unlinks the other (see above).
/obj/item/leash/proc/clear_leash()
	var/mob/living/leash_pet = LEASH_PET(src)
	if(leash_pet)
		om_unlink(leash_pet, src, /datum/om/relation/leashed_to)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(leash_master)
		om_unlink(src, leash_master, /datum/om/relation/leash_held_by)

/obj/item/leash/proc/struggle_leash()
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_pet)
		return
	if(leash_pet.absorbed)
		clear_leash()
		return
	leash_pet.visible_message(span_danger("\The [leash_pet] is attempting to unhook [leash_pet.p_their()] leash!"), span_danger("You attempt to unhook your leash"))
	add_attack_logs(leash_master,leash_pet,"Self-unleash (attempt)")

	om_do_after(leash_pet, 3.5 SECONDS, target = leash_pet, receiver = src, on_done = PROC_REF(struggle_leash_timed_done), done_args = list(leash_pet))
	return TRUE

/obj/item/leash/proc/struggle_leash_timed_done(mob/living/leash_pet)

	to_chat(leash_pet, span_userdanger("You have been released!"))
	clear_leash()

/obj/item/leash/proc/unleash()
	var/mob/living/leash_pet = LEASH_PET(src)
	var/mob/living/leash_master = LEASH_MASTER(src)
	if(!leash_pet || !leash_master)
		return
	leash_pet.visible_message(span_danger("\The [leash_master] is attempting to remove the leash on \the [leash_pet]!"), span_danger("\The [leash_master] tries to remove leash from you"))
	add_attack_logs(leash_master,leash_pet,"Unleashed (attempt)")

	om_do_after(leash_master, 1.5 SECONDS, target = leash_pet, receiver = src, on_done = PROC_REF(unleash_timed_done), done_args = list(leash_pet))
	return TRUE

/obj/item/leash/proc/unleash_timed_done(mob/living/leash_pet)

	to_chat(leash_pet, span_userdanger("You have been released!"))
	clear_leash()

/obj/item/leash/proc/is_wearing_collar(mob/living/carbon/human/human)
	if (!istype(human))
		return FALSE
	for (var/obj/item/clothing/worn in human.worn_clothing)
		if (istype(worn, /obj/item/clothing/accessory/collar) || (locate(/obj/item/clothing/accessory/collar) in worn.accessories))
			return TRUE
	return FALSE

/datum/modifier/leash
	name = "Leash"
	factors = alist(BF_SLOWDOWN = 5)

// Utility functions
/obj/item/proc/apply_tug_mob_to_mob(mob/living/tug_pet, mob/living/tug_master, distance = 2)
	apply_tug_position(tug_pet, tug_pet.x, tug_pet.y, tug_master.x, tug_master.y, distance)

/obj/item/proc/apply_tug_mob_to_object(mob/living/tug_pet, obj/tug_master, distance = 2)
	apply_tug_position(tug_pet, tug_pet.x, tug_pet.y, tug_master.x, tug_master.y, distance)

/obj/item/proc/apply_tug_object_to_mob(obj/tug_pet, mob/living/tug_master, distance = 2)
	apply_tug_position(tug_pet, tug_pet.x, tug_pet.y, tug_master.x, tug_master.y, distance)

// TODO: improve this for bigger distances, where it's easy to hide behind something and break the tugging
/obj/item/proc/apply_tug_position(tug_pet, tug_pet_x, tug_pet_y, tug_master_x, tug_master_y, distance = 2)
	if(tug_pet_x > tug_master_x + distance)
		step(tug_pet, WEST, 1) //"1" is the speed of movement. We want the tug to be faster than their slow current walk speed.
		if(tug_pet_y > tug_master_y)//Check the other axis, and tug them into alignment so they are behind the master
			step(tug_pet, SOUTH, 1)
		if(tug_pet_y < tug_master_y)
			step(tug_pet, NORTH, 1)
	if(tug_pet_x < tug_master_x - distance)
		step(tug_pet, EAST, 1)
		if(tug_pet_y > tug_master_y)
			step(tug_pet, SOUTH, 1)
		if(tug_pet_y < tug_master_y)
			step(tug_pet, NORTH, 1)
	if(tug_pet_y > tug_master_y + distance)
		step(tug_pet, SOUTH, 1)
		if(tug_pet_x > tug_master_x)
			step(tug_pet, WEST, 1)
		if(tug_pet_x < tug_master_x)
			step(tug_pet, EAST, 1)
	if(tug_pet_y < tug_master_y - distance)
		step(tug_pet, NORTH, 1)
		if(tug_pet_x > tug_master_x)
			step(tug_pet, WEST, 1)
		if(tug_pet_x < tug_master_x)
			step(tug_pet, EAST, 1)

/obj/item/leash/cable
	name = "cable leash"
	desc = "A simple tether that can easily be hooked onto a collar. This one is made from wiring cable."
	icon = 'icons/obj/leash.dmi'
	icon_state = "cable"

/datum/crafting_recipe/leash
	name = "cable leash"
	result = /obj/item/leash/cable
	reqs = list(
		list(/obj/item/stack/cable_coil = 3)
	)
	time = 60
	category = CAT_MISC
