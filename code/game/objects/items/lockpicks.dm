//For bypassing locked /obj/structure/simple_doors
//now with added fence gate support

/obj/item/lockpick
	name = "set of lockpicks"
	desc = "A set of picks and tension wrenches, ideal for picking old-style mechanical locks... not that any of those exist on most NT facilities these days. Still, it might be useful elsewhere?"
	icon = 'icons/obj/lockpicks.dmi'
	icon_state = "lockpicks"
	w_class = ITEMSIZE_SMALL
	var/pick_type = "simple"
	var/pick_time = 10 SECONDS
	var/pick_verb = "pick"

MSG_DEF_SELF(lockpick/not_locked, span_notice("%T% isn't locked."))
MSG_DEF_SELF(lockpick/wrong_type, span_warning("%I% can't pick %T%. Another tool might work?"))
MSG_DEF_SELF(lockpick/cannot_pick, span_warning("%T% can't be picked by %I%."))
MSG_DEF(lockpick/picking, "You start to work on the lock of %T%...", "%U% starts working on the lock of %T%.")

CAPABILITIES(/obj/item/lockpick)
	op("pick", at_target(/obj/structure/simple_door), at_target(/obj/structure/fence/door), priority(OP_PRIORITY_PART), answers(INTENT_USE), needs(req(PROC_REF(handy_user), silent = TRUE)), starts(PROC_REF(pick_started)), begins(PROC_REF(pick_begins)), wait(PROC_REF(pick_duration)), then(PROC_REF(picked)))

/// No lockpicking for monkeys.
/obj/item/lockpick/proc/handy_user(datum/act/op/A)
	var/mob/user = A.actor
	return !!user?.IsAdvancedToolUser()

/// A door that is not locked, of another lock type or not pickable at all ends the click before anything starts.
/obj/item/lockpick/proc/pick_started(datum/act/op/A)
	var/obj/structure/simple_door/door = A.target
	if(istype(door))
		if(!door.locked)
			return /datum/msg/lockpick/not_locked
		if(door.lock_type != pick_type)
			return /datum/msg/lockpick/wrong_type
		if(!door.can_pick)
			return /datum/msg/lockpick/cannot_pick
		playsound(src, door.keysound, 100, 1)
		return null
	var/obj/structure/fence/door/gate = A.target
	if(!istype(gate))
		return /datum/msg/lockpick/cannot_pick
	if(!gate.locked)
		return /datum/msg/lockpick/not_locked
	if(gate.lock_type != pick_type)
		return /datum/msg/lockpick/wrong_type
	if(!gate.can_pick)
		return /datum/msg/lockpick/cannot_pick
	playsound(src, gate.keysound, 100, 1)
	return null

/obj/item/lockpick/proc/pick_begins(datum/act/op/A)
	return msg_text(span_notice("You start to [pick_verb] the lock on \the [A.target]..."), span_notice("[A.actor] starts to [pick_verb] the lock on \the [A.target]."))

/obj/item/lockpick/proc/pick_duration(datum/act/op/A)
	var/obj/structure/simple_door/door = A.target
	if(istype(door))
		return pick_time * door.lock_difficulty
	var/obj/structure/fence/door/gate = A.target
	return pick_time * (istype(gate) ? gate.lock_difficulty : 1)

/obj/item/lockpick/proc/picked(datum/act/op/A)
	var/obj/structure/simple_door/door = A.target
	var/obj/structure/fence/door/gate = A.target
	to_chat(A.actor, span_notice("Success!"))
	if(istype(door))
		door.locked = FALSE
	else if(istype(gate))
		gate.locked = FALSE
	return OP_OK

/// You can pick your friends, and you can pick your nose, but you can't pick your friend's nose.
/obj/item/lockpick/afterattack(atom/A, mob/user)
	if(!user.IsAdvancedToolUser())
		return
	if(ishuman(A))
		var/mob/living/carbon/human/H = A
		if(user.zone_sel.selecting == BP_HEAD)
			if(H == user)
				to_chat(user, span_notice("Your nose isn't locked. If you're feeling stuffy, maybe you should talk to a doctor..?"))
			else
				act_message(user, src, MSG_SELF(span_notice("You try to [pick_verb] [H]'s nose. It doesn't seem to be working.")), MSG_OTHERS(span_notice("%U% tries to [pick_verb] [H]'s nose with %T%! They don't seem to be having much success.")))

/obj/item/lockpick/pick_gun
	name = "pick gun"
	desc = "A more sophisticated and automated alternative to traditional lockpicking methods. Contains a dazzling array of tools in a simple-to-use housing: just press the face plate against the lock face and hold the trigger down until it goes click."
	icon_state = "pick_gun"
	pick_time = 3 SECONDS

/obj/item/lockpick/mag_sequencer
	name = "magnetic sequencer"
	desc = "A deceptively simple gadget that brute-forces magnetic locks using a small electromagnet. A predecessor to the cryptographic sequencer, a more complicated device that is considered contraband in most jurisdictions. Not that these aren't illegal either, mind you!"
	icon_state = "mag_sequencer"
	pick_type = "maglock"
	pick_time = 5 SECONDS
	pick_verb = "bypass"
