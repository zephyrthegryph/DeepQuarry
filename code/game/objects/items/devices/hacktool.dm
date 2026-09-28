/obj/item/multitool/hacktool
	var/max_known_targets
	var/hackspeed = 1		//time taken to hack: lower is faster
	var/max_level = 4		//what's the max door security_level we can handle? default is 1, med/eng/atmos are 1.5, sec/sci are 2, command is 3, vault is 5
	var/full_override = FALSE	//can we override door bolts too? defaults to false for event/safety reasons

	var/in_hack_mode = 0
	var/list/known_targets
	var/list/supported_types
	var/datum/tgui_state/default/must_hack/hack_state
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/multitool/hacktool/override
	hackspeed = 0.75
	max_level = 5
	full_override = TRUE

/obj/item/multitool/hacktool/Initialize(mapload)
	. = ..()
	known_targets = list()
	max_known_targets = 5 + rand(1,3)
	supported_types = list(/obj/machinery/door/airlock,/obj/structure/closet/crate/secure,/obj/structure/closet/secure_closet)

DECLARE_REF(/obj/item/multitool/hacktool, "hack_state", OWNED, null)
DECLARE_DEFAULT_CHILD(/obj/item/multitool/hacktool, "hack_state", /datum/tgui_state/default/must_hack)

// stops observing its known targets' destruction.
/obj/item/multitool/hacktool/on_destroy(force)
	for(var/atom/target as anything in known_targets)
		target.unregister(OBSERVER_EVENT_DESTROY, src)
	known_targets.Cut()
	..()

/obj/item/multitool/hacktool/screwdriver_act(mob/user, obj/item/tool)
	in_hack_mode = !in_hack_mode
	playsound(src, tool.usesound, 50, 1)
	return ITEM_INTERACT_SUCCESS

/obj/item/multitool/hacktool/afterattack(atom/A, mob/user)
	sanity_check()

	if(!in_hack_mode)
		return ..()

	if(!attempt_hack(user, A))
		return 0

	// Note, if you ever want to expand supported_types, you must manually add the custom state argument to their tgui_interact
	// DISABLED: too fancy, too high-effort // A.tgui_interact(user, custom_state = hack_state)
	// Just brute-force it
	if(istype(A, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/D = A
		if(!D.arePowerSystemsOn())
			to_chat(user, span_warning("No response from remote, check door power."))
		else if(D.locked == TRUE && full_override == FALSE)
			to_chat(user, span_warning("Unable to override door bolts!"))
		else if(D.locked == TRUE && full_override == TRUE && D.arePowerSystemsOn())
			to_chat(user, span_notice("Door bolts overridden."))
			D.unlock()
		else if(D.density == TRUE && D.locked == FALSE)
			to_chat(user, span_notice("Overriding access. Door opening."))
			D.open()
		else if(D.density == FALSE && D.locked == FALSE)
			to_chat(user, span_notice("Overriding access. Door closing."))
			D.close()
	return 1

/obj/item/multitool/hacktool/proc/attempt_hack(mob/user, atom/target)
	if(om_busy(src))
		to_chat(user, span_warning("You are already hacking!"))
		return 0
	if(!is_type_in_list(target, supported_types))
		to_chat(user, "[icon2html(src, user.client)] " + span_warning("Unable to hack this target, invalid target type."))
		return 0

	if(istype(target, /obj/structure/closet/crate/secure))
		var/obj/structure/closet/crate/secure/A = target
		if(A.locked)
			to_chat(user, span_notice("Overriding access. Stand by."))
			om_task_timed(user, (((5 SECONDS + rand(0, 5 SECONDS) + rand(0, 5 SECONDS))*hackspeed)), target = src, receiver = src, on_done = PROC_REF(attempt_hack_timed_done), done_args = list(user, A), claims = TRUE)
		else
			return

	if(istype(target, /obj/structure/closet/secure_closet))
		var/obj/structure/closet/secure_closet/A = target
		if(A.locked)
			to_chat(user, span_notice("Overriding access. Stand by."))
			om_task_timed(user, (((5 SECONDS + rand(0, 5 SECONDS) + rand(0, 5 SECONDS))*hackspeed)), target = src, receiver = src, on_done = PROC_REF(attempt_hack_timed_done2), done_args = list(user, A), claims = TRUE)
		else
			return

	if(istype(target, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/D = target
		if(D.security_level > max_level)
			to_chat(user, "[icon2html(src, user.client)] " + span_warning("Target's electronic security is too complex."))
			return 0

		var/found = known_targets.Find(D)
		if(found)
			known_targets.Swap(1, found)	// Move the last hacked item first
			return 1
		to_chat(user, span_notice("You begin hacking \the [D]..."))
		// On average hackin takes ~15 seconds. Fairly small random span to discourage people from simply aborting and trying again
		// Reduced hack duration to compensate for the reduced functionality, multiplied by door sec level
		om_task_start(/datum/om/task/timed/hacktool_airlock, user, src, duration = (((10 SECONDS + rand(0, 10 SECONDS) + rand(0, 10 SECONDS))*hackspeed)*D.security_level), receiver = src, door = D)
		return 0 // the hack is under way; the door is handled when it lands

/// Hacking an airlock: the tool is busy with it (claimed) until it lands.
/datum/om/task/timed/hacktool_airlock
	claims = TRUE
	complete_proc = /obj/item/multitool/hacktool/proc/hack_airlock_done
	fail_message = span_warning("Your hacking attempt failed!")
	var/obj/machinery/door/airlock/door

/// The airlock hack landed: remember the door and act on it as a hacked target.
/obj/item/multitool/hacktool/proc/hack_airlock_done(datum/om/task/timed/hacktool_airlock/task)
	var/mob/user = task.actor
	var/obj/machinery/door/airlock/D = task.door
	if(!in_hack_mode)
		to_chat(user, task.fail_message)
		return
	to_chat(user, span_notice("Your hacking attempt was succesful!"))
	user.playsound_local(get_turf(src), 'sound/runtime/instruments/piano/An6.ogg', 50)
	known_targets.Insert(1, D)	// Insert the newly hacked target first,
	D.register(OBSERVER_EVENT_DESTROY, src, /obj/item/multitool/hacktool/proc/on_target_destroy)
	afterattack(D, user)

/obj/item/multitool/hacktool/proc/attempt_hack_timed_done(mob/user, obj/structure/closet/crate/secure/A)
	to_chat(user, span_notice("Override successful!"))
	A.locked = FALSE
	A.update_icon()
	play_sfx(A, SFX_MACHINES_CLICK, 0.3, extrarange = -3)
/obj/item/multitool/hacktool/proc/attempt_hack_timed_done2(mob/user, obj/structure/closet/crate/secure/A)
	to_chat(user, span_notice("Override successful!"))
	A.locked = FALSE
	A.update_icon()
	play_sfx(A, SFX_MACHINES_CLICK, 0.3, extrarange = -3)

/obj/item/multitool/hacktool/proc/sanity_check()
	if(max_known_targets < 1) max_known_targets = 1
	// Cut away the oldest items if the capacity has been reached
	if(known_targets.len > max_known_targets)
		for(var/i = (max_known_targets + 1) to known_targets.len)
			var/atom/A = known_targets[i]
			A.unregister(OBSERVER_EVENT_DESTROY, src)
		known_targets.Cut(max_known_targets + 1)

/obj/item/multitool/hacktool/proc/on_target_destroy(target)
	known_targets -= target

/datum/tgui_state/default/must_hack
	var/hacktool_handle

/datum/tgui_state/default/must_hack/New(hacktool)
	src.hacktool_handle = om_handle(hacktool)
	..()

/datum/tgui_state/default/must_hack/can_use_topic(src_object, mob/user)
	if(!hacktool() || !hacktool().in_hack_mode || !(src_object in hacktool().known_targets))
		return STATUS_CLOSE
	return ..()

/obj/item/multitool/hacktool/modified
	name = "modified multitool"
	desc = "Used for pulsing wires to test which to cut. Not recommended by doctors. This ones seems a bit larger and heavier than the usual model, for some reason. Maybe it's an older version?"
	icon_state = "multitool_modified"

/obj/item/multitool/hacktool/obvious
	name = "non-standard multitool"
	desc = "Used for pulsing wires to test which to cut. Not recommended by doctors. This one doesn't look like the usual model at all!"
	icon_state = "multitool_suspicious"
	in_hack_mode = 1	//start in hackmode

/// LC-refs: hacktool -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/tgui_state/default/must_hack/proc/hacktool() as /obj/item/multitool/hacktool
	return om_resolve(hacktool_handle)
