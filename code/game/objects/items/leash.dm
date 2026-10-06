/atom/movable/screen/alert/leash_dom
	name = "Leash Holder"
	desc = "You're holding a leash, with someone on the end."
	icon_state = "leash_master"

/atom/movable/screen/alert/leash_dom/Click()
	var/obj/item/leash/owner = master_ref
	if(owner)
		owner.unleash()

/atom/movable/screen/alert/leash_pet
	name = "Leashed"
	desc = "You're on the hook now!"
	icon_state = "leash_pet"

/atom/movable/screen/alert/leash_pet/Click()
	var/obj/item/leash/owner = master_ref
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
	if(!istype(source) || !istype(target))
		return
	source.apply_body_effect(/datum/body_effect/leash)
	source.throw_alert("leashed", /atom/movable/screen/alert/leash_pet, new_master = target)
	observe(source, /datum/notice/moved, target, then(TYPE_PROC_REF(/obj/item/leash, on_pet_move)))
	om_task_periodic(target, PERIODIC_SLOW)

/datum/om/relation/leashed_to/on_unlink(mob/living/source, obj/item/leash/target, datum/om/edge/edge)
	if(istype(source) && !QDELETED(source))
		source.clear_alert("leashed")
		source.remove_body_effect(/datum/body_effect/leash)
	if(istype(target))
		unobserve(source, /datum/notice/moved, target)
		om_task_periodic_stop(target)
		// No pet, no leash: let go of the holder too.
		var/mob/living/master = target?.leash_master()
		if(master)
			om_unlink(target, master, /datum/om/relation/leash_held_by)

/datum/om/relation/leash_held_by
	name = "leash holder"
	source_single = TRUE

/datum/om/relation/leash_held_by/on_link(obj/item/leash/source, mob/living/target, datum/om/edge/edge)
	if(!istype(source) || !istype(target))
		return
	target.throw_alert("leash", /atom/movable/screen/alert/leash_dom, new_master = source)
	observe(target, /datum/notice/moved, source, then(TYPE_PROC_REF(/obj/item/leash, on_master_move)))

/datum/om/relation/leash_held_by/on_unlink(obj/item/leash/source, mob/living/target, datum/om/edge/edge)
	if(istype(target) && !QDELETED(target))
		target.clear_alert("leash")
	if(istype(source))
		unobserve(target, /datum/notice/moved, source)
		// No holder, no leash: the pet is free.
		var/mob/living/pet = source?.leash_pet()
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

/obj/item/leash/periodic_step()
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
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
		act_message(leash_pet, null, MSG_SELF(span_warning("You have slipped out of your collar!")), \
			MSG_OTHERS(span_warning("%U% has slipped out of %THEIR% collar!")))
		clear_leash()
		return

//Called when someone is clicked with the leash
/obj/item/leash/attack(mob/living/C, mob/living/user, target_zone, attack_modifier) //C is the target, user is the one with the leash
	if(C?.leash_item()) //If the pet is already leashed, do not leash them. For the love of god.
		// If they re-click, remove the leash
		if (C == leash_pet() && user == leash_master())
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

	if(istype(C, /mob/living/carbon/human) && !is_wearing_collar(C))
		to_chat(user, span_notice("[C] needs a collar before you can attach a leash to it."))
		return ITEM_INTERACT_FAILURE

	om_flow_start(/datum/om/flow/leash, user, C, leash = src)
	return TRUE

/// Putting a leash on: the holder (actor) works on the pet (target), the pet agrees, the leash
/// clicks on. Every step after the first re-checks valid(): the holder still has the leash and
/// the pet isn't leashed by someone else meanwhile.
/datum/om/flow/leash
	name = "leash"
	var/obj/item/leash/leash

/datum/om/flow/leash/valid()
	var/mob/living/pet = target
	if(leash.loc != actor)
		return "not holding the leash"
	if(pet.leash_item())
		return "already leashed"
	return null

/datum/om/flow/leash/start()
	var/mob/living/pet = target
	var/mob/living/carbon/human/human_pet = pet
	var/leashtime = (istype(human_pet) && human_pet.get_equipped_item(SLOT_ID_HANDCUFFED)) ? 0.5 SECONDS : 3.5 SECONDS
	act_message(pet, null, MSG_SELF(span_danger("\The [actor] tries to put a leash on you")), MSG_OTHERS(span_danger("\The [actor] is attempting to put the leash on %U%!")))
	add_attack_logs(actor, pet, "Leashed (attempt)")
	wait(leashtime, PROC_REF(offer))

/datum/om/flow/leash/proc/offer()
	om_ask(target, /datum/om/prompt/confirm/leash_offer, PROC_REF(accepted))

/datum/om/flow/leash/proc/accepted(datum/om/prompt/confirm/leash_offer/ask)
	leash.attach(target, actor)

/// The pet is asked (asker: the holder, from the flow). Re-checked on the answer: still face to face.
/datum/om/prompt/confirm/leash_offer
	title = "Become Leashed"
	no_first = TRUE
	ask_flags = ASK_FACE_TO_FACE

/datum/om/prompt/confirm/leash_offer/prepare()
	message = "Would you like to be leashed by [asker]? You can OOC escape to escape"
	return TRUE

/// Links the leash between `pet` and `holder`. This leash may still be on someone else: that one ends here.
/obj/item/leash/proc/attach(mob/living/pet, mob/living/holder)
	clear_leash()
	if(!istype(om_link(pet, src, /datum/om/relation/leashed_to), /datum/om/edge))
		return FALSE
	om_link(src, holder, /datum/om/relation/leash_held_by)
	act_message(pet, holder, MSG_SELF(span_danger("The leash clicks onto your collar!")), MSG_OTHERS(span_danger("%T% puts a leash on %U%!")))
	to_chat(pet, span_userdanger("You have been leashed!"))
	to_chat(pet, span_danger("(You can use OOC escape to detach the leash)"))
	return TRUE

//Called when the leash is used in hand
//Tugs the pet closer
CAPABILITIES(/obj/item/leash)
	op("tug", in_hand(), label("Tug leash"), then(PROC_REF(leash_tug_requested)))

/obj/item/leash/proc/leash_tug_requested(datum/act/op/A)
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
	if(!leash_pet || !leash_master) //No pet, no tug.
		return OP_OK
	if(leash_pet.absorbed) //Glrk'd.
		clear_leash()
		return OP_OK
	//Yank the pet. Yank em in close.
	apply_tug_mob_to_mob(leash_pet, leash_master, 1)
	return OP_OK

/obj/item/leash/proc/on_master_move(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/leash_pet = src?.leash_pet()
	//Make sure the dom still has a pet
	if(!src?.leash_master() || !leash_pet)
		return
	if(leash_pet.absorbed)
		clear_leash()
		return
	after(src, 0.2 SECONDS, PROC_REF(after_master_move))

/obj/item/leash/proc/after_master_move()
	//If the master moves, pull the pet in behind
	//Also, the timer means that the distance check for master happens before the pet, to prevent both from proccing.
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
	if(!leash_master || !leash_pet) //Just to stop error messages
		return
	apply_tug_mob_to_mob(leash_pet, leash_master, 2)

	//Knock the pet over if they get further behind. Shouldn't happen too often.
	after(src, 0.3 SECONDS, PROC_REF(leash_trip_check)) //This way running normally won't just yank the pet to the ground.

/obj/item/leash/proc/leash_trip_check()
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
	if(!leash_master || !leash_pet || leash_pet.absorbed) //Just to stop error messages. Break the loop early if something removed the master
		clear_leash()
		return
	if(get_dist(leash_pet, leash_master) > 3 && !leash_pet.has_status(STAT_STUNNED))
		act_message(leash_pet, null, MSG_SELF(span_warning("You are pulled to the ground by your leash!")), \
			MSG_OTHERS(span_warning("%U% is pulled to the ground by %THEIR% leash!")))
		leash_pet.apply_effect(5, STUN, 0)

	//This code is to check if the pet has gotten too far away, and then break the leash.
	after(src, 0.3 SECONDS, PROC_REF(leash_snap_check)) //Wait to snap the leash

/obj/item/leash/proc/leash_snap_check()
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
	if(!leash_master || !leash_pet || leash_pet.absorbed) //Just to stop error messages
		clear_leash()
		return
	if(get_dist(leash_pet, leash_master) > 5)
		act_message(leash_pet, null, MSG_SELF(span_warning("Your leash pops from your collar!")), \
			MSG_OTHERS(span_warning("The leash snaps free from %U%'s collar!")))
		leash_pet.apply_effect(5, STUN, 0)
		leash_pet.body?.add_restriction(src, BF_AIRWAY, 0.2, 5 SECONDS) // the collar yanks the throat shut
		clear_leash()

/obj/item/leash/proc/on_pet_move(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	//This should only work if there is a pet and a master.
	if(!src?.leash_master() || !src?.leash_pet())
		return

	//If the pet gets too far away, they get tugged back
	after(src, 0.3 SECONDS, PROC_REF(after_pet_move)) //A short timer so the pet kind of bounces back after they make the step

/obj/item/leash/proc/after_pet_move()
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
	if(!leash_master || !leash_pet || leash_pet.absorbed)
		return
	for(var/i in 3 to get_dist(leash_pet, leash_master)) // Move the pet to a minimum of 2 tiles away from the master, so the pet trails behind them.
		step_towards(leash_pet, leash_master)

/obj/item/leash/dropped(mob/user, equipping, slot)
	//Drop the leash, and the leash effects stop
	. = ..()
	var/mob/living/leash_pet = src?.leash_pet()
	if(!leash_pet || !src?.leash_master() || leash_pet.absorbed) //There is no pet. Stop this silliness
		clear_leash()
		return
	//Dropping procs any time the leash changes slots. So, we will wait a tick and see if the leash was actually dropped
	after(src, 0.1 SECONDS, PROC_REF(drop_effects), with = list(user))

/obj/item/leash/proc/drop_effects(mob/user)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/leash_master = src?.leash_master()
	if(leash_master && (leash_master.item_is_in_hands(src) || leash_master.isEquipped(src)))
		return  //Dom still has the leash as it turns out. Cancel the proc.
	if(leash_master)
		act_message(leash_master, src, MSG_SELF(span_notice("You drop %T%.")), MSG_OTHERS(span_notice("%U% drops %T%.")))
	//DOM HAS DROPPED LEASH. PET IS FREE. SCP HAS BREACHED CONTAINMENT.
	clear_leash()

/// Ends the leash. Unlinking either edge unlinks the other (see above).
/obj/item/leash/proc/clear_leash()
	var/mob/living/leash_pet = src?.leash_pet()
	if(leash_pet)
		om_unlink(leash_pet, src, /datum/om/relation/leashed_to)
	var/mob/living/leash_master = src?.leash_master()
	if(leash_master)
		om_unlink(src, leash_master, /datum/om/relation/leash_held_by)

/obj/item/leash/proc/struggle_leash()
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
	if(!leash_pet)
		return
	if(leash_pet.absorbed)
		clear_leash()
		return
	act_message(leash_pet, null, MSG_SELF(span_danger("You attempt to unhook your leash")), MSG_OTHERS(span_danger("%U% is attempting to unhook %THEIR% leash!")))
	add_attack_logs(leash_master,leash_pet,"Self-unleash (attempt)")

	om_task_timed(leash_pet, 3.5 SECONDS, target = leash_pet, receiver = src, on_done = PROC_REF(released))
	return TRUE

/obj/item/leash/proc/unleash()
	var/mob/living/leash_pet = src?.leash_pet()
	var/mob/living/leash_master = src?.leash_master()
	if(!leash_pet || !leash_master)
		return
	act_message(leash_pet, null, MSG_SELF(span_danger("\The [leash_master] tries to remove leash from you")), MSG_OTHERS(span_danger("\The [leash_master] is attempting to remove the leash on %U%!")))
	add_attack_logs(leash_master,leash_pet,"Unleashed (attempt)")

	om_task_timed(leash_master, 1.5 SECONDS, target = leash_pet, receiver = src, on_done = PROC_REF(released))
	return TRUE

/// A timed unhook finished (by the pet or the holder): the pet is free.
/obj/item/leash/proc/released()
	var/mob/living/leash_pet = leash_pet()
	if(leash_pet)
		to_chat(leash_pet, span_userdanger("You have been released!"))
	clear_leash()

/obj/item/leash/proc/is_wearing_collar(mob/living/carbon/human/human)
	if (!istype(human))
		return FALSE
	for (var/obj/item/clothing/worn in human.get_worn_clothing())
		if (istype(worn, /obj/item/clothing/accessory/collar) || (locate_in_list(worn.accessories, /obj/item/clothing/accessory/collar)))
			return TRUE
	return FALSE

/datum/body_effect/leash
	stacks = MODIFIER_STACK_FORBID
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
