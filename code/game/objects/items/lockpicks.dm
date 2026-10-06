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

/obj/item/lockpick/afterattack(atom/A, mob/user)
	if(!user.IsAdvancedToolUser())	//no lockpicking for monkeys
		return
	if(istype(A, /obj/structure/simple_door))
		var/obj/structure/simple_door/D = A
		if(!D.locked)	//you can pick your nose, but you can't pick an unlocked door
			to_chat(user, span_notice("\The [D] isn't locked."))
			return
		else if(D.lock_type != pick_type) //make sure our types match
			to_chat(user, span_warning("\The [src] can't pick \the [D]. Another tool might work?"))
			return
		else if(!D.can_pick)	//make sure we're actually allowed to bypass it at all
			to_chat(user, span_warning("\The [D] can't be [pick_verb]ed."))
			return
		else	//finally, we can assume that they do match
			to_chat(user, span_notice("You start to [pick_verb] the lock on \the [D]..."))
			playsound(src, D.keysound,100, 1)
			task_timed(user, pick_time * D.lock_difficulty, target = src, receiver = src, on_done = PROC_REF(afterattack_timed_done), done_args = list(user, D))
	if(istype(A, /obj/structure/fence/door))
		var/obj/structure/fence/door/D = A
		if(!D.locked)	//you can pick your nose, but you can't pick an unlocked door
			to_chat(user, span_notice("\The [D] isn't locked."))
			return
		else if(D.lock_type != pick_type) //make sure our types match
			to_chat(user, span_warning("\The [src] can't pick \the [D]. Another tool might work?"))
			return
		else if(!D.can_pick)	//make sure we're actually allowed to bypass it at all
			to_chat(user, span_warning("\The [D] can't be [pick_verb]ed."))
			return
		else	//finally, we can assume that they do match
			to_chat(user, span_notice("You start to [pick_verb] the lock on \the [D]..."))
			playsound(src, D.keysound,100, 1)
			task_timed(user, pick_time * D.lock_difficulty, target = src, receiver = src, on_done = PROC_REF(afterattack_timed_done2), done_args = list(user, D))
	else if(ishuman(A)) //you can pick your friends, and you can pick your nose, but you can't pick your friend's nose
		var/mob/living/carbon/human/H = A
		if(user.zone_sel.selecting == BP_HEAD)
			if(H == user)
				to_chat(user, span_notice("Your nose isn't locked. If you're feeling stuffy, maybe you should talk to a doctor..?"))
			else
				act_message(user, src, MSG_SELF(span_notice("You try to [pick_verb] [H]'s nose. It doesn't seem to be working.")), MSG_OTHERS(span_notice("%U% tries to [pick_verb] [H]'s nose with %T%! They don't seem to be having much success.")))
			return

/obj/item/lockpick/proc/afterattack_timed_done(mob/user, obj/structure/simple_door/D)
	to_chat(user, span_notice("Success!"))
	D.locked = FALSE
/obj/item/lockpick/proc/afterattack_timed_done2(mob/user, obj/structure/simple_door/D)
	to_chat(user, span_notice("Success!"))
	D.locked = FALSE

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
