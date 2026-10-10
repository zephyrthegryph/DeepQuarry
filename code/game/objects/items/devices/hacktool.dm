/obj/item/multitool/hacktool
	var/max_known_targets
	var/hackspeed = 1		//time taken to hack: lower is faster
	var/max_level = 4		//what's the max door security_level we can handle? default is 1, med/eng/atmos are 1.5, sec/sci are 2, command is 3, vault is 5
	var/full_override = FALSE	//can we override door bolts too? defaults to false for event/safety reasons

	var/in_hack_mode = 0
	var/list/known_targets
	var/static/list/supported_types = list(/obj/machinery/door/airlock,/obj/structure/closet/crate/secure,/obj/structure/closet/secure_closet)
	var/datum/tgui_state/default/must_hack/hack_state
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/obj/item/multitool/hacktool/override
	hackspeed = 0.75
	max_level = 5
	full_override = TRUE

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/multitool/hacktool/proc/roll_max_known_targets(datum/roller/R)
	return 5 + R.number(1, 3)

CAPABILITIES(/obj/item/multitool/hacktool)
	owns_one(nameof(hack_state), starts = /datum/tgui_state/default/must_hack)
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	// The hacks, started by attempt_hack() with the target and the rolled time; the tool is claimed (busy) until one ends.
	op("hack_locker", ai(), takes("locker", "time"), claims(CLAIM_TARGET), wait(PROC_REF(hack_wait)), then(PROC_REF(attempt_hack_timed_done)))
	op("hack_airlock", ai(), takes("door", "time"), claims(CLAIM_TARGET), wait(PROC_REF(hack_wait)), on_interrupt(PROC_REF(hack_airlock_failed)), then(PROC_REF(hack_airlock_done)))
	rolls(nameof(max_known_targets), PROC_REF(roll_max_known_targets))

// known_targets is a relation list (newest last): the framework drops a target when it dies.

/obj/item/multitool/hacktool/proc/screwdriver_used(datum/act/op/A)
	var/obj/item/tool = A.held
	in_hack_mode = !in_hack_mode
	playsound(src, tool.usesound, 50, 1)
	return OP_OK

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
		if(!D.power_systems_on())
			to_chat(user, span_warning("No response from remote, check door power."))
		else if(is_bolted(D) && full_override == FALSE)
			to_chat(user, span_warning("Unable to override door bolts!"))
		else if(is_bolted(D) && full_override == TRUE && D.power_systems_on())
			to_chat(user, span_notice("Door bolts overridden."))
			set_bolted(D, FALSE)
		else if(D.density == TRUE && !is_bolted(D))
			to_chat(user, span_notice("Overriding access. Door opening."))
			D.open()
		else if(D.density == FALSE && !is_bolted(D))
			to_chat(user, span_notice("Overriding access. Door closing."))
			D.close()
	return 1

/obj/item/multitool/hacktool/proc/attempt_hack(mob/user, atom/target)
	if(op_claimed(src))
		to_chat(user, span_warning("You are already hacking!"))
		return 0
	if(!is_type_in_list(target, supported_types))
		to_chat(user, "[icon2html(src, user.client)] " + span_warning("Unable to hack this target, invalid target type."))
		return 0

	if(istype(target, /obj/structure/closet/crate/secure))
		var/obj/structure/closet/crate/secure/A = target
		if(lock_locked(A))
			to_chat(user, span_notice("Overriding access. Stand by."))
			perform_op(user, src, "hack_locker", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("locker" = A, "time" = ((5 SECONDS + rand(0, 5 SECONDS) + rand(0, 5 SECONDS))*hackspeed)))
		else
			return

	if(istype(target, /obj/structure/closet/secure_closet))
		var/obj/structure/closet/secure_closet/A = target
		if(lock_locked(A))
			to_chat(user, span_notice("Overriding access. Stand by."))
			perform_op(user, src, "hack_locker", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("locker" = A, "time" = ((5 SECONDS + rand(0, 5 SECONDS) + rand(0, 5 SECONDS))*hackspeed)))
		else
			return

	if(istype(target, /obj/machinery/door/airlock))
		var/obj/machinery/door/airlock/D = target
		if(D.security_level > max_level)
			to_chat(user, "[icon2html(src, user.client)] " + span_warning("Target's electronic security is too complex."))
			return 0

		if(D in known_targets)
			rel_remove(src, nameof(known_targets), D)	// Move the last hacked item to the newest end
			rel_add(src, nameof(known_targets), D)
			return 1
		to_chat(user, span_notice("You begin hacking \the [D]..."))
		// On average hackin takes ~15 seconds. Fairly small random span to discourage people from simply aborting and trying again
		// Reduced hack duration to compensate for the reduced functionality, multiplied by door sec level
		perform_op(user, src, "hack_airlock", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("door" = D, "time" = (((10 SECONDS + rand(0, 10 SECONDS) + rand(0, 10 SECONDS))*hackspeed)*D.security_level)))
		return 0 // the hack is under way; the door is handled when it lands

/// How long the hack takes, rolled when it was started.
/obj/item/multitool/hacktool/proc/hack_wait(datum/act/op/A)
	return A.arg("time")

/// The hack was cut short.
/obj/item/multitool/hacktool/proc/hack_airlock_failed(datum/act/op/A)
	to_chat(A.actor, span_warning("Your hacking attempt failed!"))

/// The airlock hack landed: remember the door and act on it as a hacked target.
/obj/item/multitool/hacktool/proc/hack_airlock_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/machinery/door/airlock/D = A.arg("door")
	if(QDELETED(D))
		return OP_REFUSED
	if(!in_hack_mode)
		to_chat(user, span_warning("Your hacking attempt failed!"))
		return OP_FAILED
	to_chat(user, span_notice("Your hacking attempt was succesful!"))
	user.playsound_local(get_turf(src), 'sound/runtime/instruments/piano/An6.ogg', 50)
	rel_add(src, nameof(known_targets), D)	// The newly hacked target goes at the newest end
	afterattack(D, user)
	return OP_OK

/obj/item/multitool/hacktool/proc/attempt_hack_timed_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/structure/closet/locker = A.arg("locker")
	if(QDELETED(locker))
		return OP_REFUSED
	to_chat(user, span_notice("Override successful!"))
	locker.force_lock(FALSE)
	play_sfx(locker, SFX_MACHINES_CLICK, 0.3, extrarange = -3)
	return OP_OK

/obj/item/multitool/hacktool/proc/sanity_check()
	if(max_known_targets < 1) max_known_targets = 1
	// Cut away the oldest items if the capacity has been reached
	while(length(known_targets) > max_known_targets)
		rel_remove(src, nameof(known_targets), known_targets[1])

/datum/tgui_state/default/must_hack
	var/obj/item/multitool/hacktool/hacktool

/datum/tgui_state/default/must_hack/New(hacktool)
	rel_set(src, nameof(hacktool), hacktool)
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

/// Relation view: hacktool (reads null once it is gone).
/datum/tgui_state/default/must_hack/proc/hacktool() as /obj/item/multitool/hacktool
	return hacktool
