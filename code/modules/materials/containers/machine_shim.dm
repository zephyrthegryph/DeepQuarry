/**
 * THIS IS A SHIM. IT SHOULD NOT BE INCLUDED IN FUTURE CODE. DEPRECATED, DO NOT USE.
 *
 * This is used to replace the machine var in mob, it is a holdover of pre-tgui code.
 * This owned datum operates similar to how the machine var did previous, but better contained.
 * Any uses of set_machine() should eventually be removed in favor of tgui handling instead.
 *
 * All this does is ensure that the mob releases the machine when they leave it.
 */
/datum/using_machine_shim
	var/obj/machinery/linked_machine
	/// The mob using the machine.
	var/mob/owner

/mob/var/datum/using_machine_shim/machine_shim

/datum/using_machine_shim/New(mob/new_owner, obj/machinery/machine)
	..()
	rel_set(src, nameof(owner), new_owner)
	rel_set(owner, nameof(owner.machine_shim), src)
	// Mob
	seq_extra_add(host_mob(), /datum/sequence/life, src)
	observe(host_mob(), /datum/notice/movable_attempted_move, src, then(PROC_REF(on_mob_moved)))
	observe(host_mob(), /datum/notice/mob_logout, src, then(PROC_REF(on_mob_logout)))

	// Machine
	rel_set(src, nameof(linked_machine), machine)
	observe(linked_machine(), /datum/notice/qdeleting, src, then(PROC_REF(on_machine_qdelete)))
	linked_machine().in_use = TRUE

	// Lets complain if an object uses TGUI but is still setting the machine.
	if(present_interface(linked_machine()))
		log_world("## ERROR [machine.type] declares a tgui window (interface()), and has likely been ported to tgui already. It should no longer use set_machine().")

// the machine is free again and the operator's perspective and trait reset.
/datum/using_machine_shim/lifecycle_prerelease()
	..()
	var/obj/machinery/machine = linked_machine()
	if(machine)
		machine.in_use = FALSE
	if(owner)
		seq_extra_remove(owner, /datum/sequence/life, src)
		owner.reset_perspective()

/datum/using_machine_shim/proc/on_mob_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	on_mob_action()

/datum/using_machine_shim/proc/on_mob_action()
	SHOULD_NOT_OVERRIDE(TRUE)
	if(host_mob().stat == DEAD || !host_mob().client || !host_mob().Adjacent(linked_machine()))
		spent(src)

/// Called by the using machine shim trait system each Life() cycle.
/datum/using_machine_shim/proc/on_mob_life()
	on_mob_action()

/datum/using_machine_shim/proc/on_machine_qdelete(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	spent(src)

/datum/using_machine_shim/proc/on_mob_logout(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	spent(src)

/////////////////////////////////////////////////////////////////////////////////
// To be removed helper procs
/////////////////////////////////////////////////////////////////////////////////
/// deprecated, do not use
/mob/proc/get_current_machine()
	RETURN_TYPE(/obj)
	var/datum/using_machine_shim/shim = machine_shim
	if(!shim)
		return
	return shim.linked_machine()

/// deprecated, do not use
/mob/proc/check_current_machine(obj/checking)
	var/datum/using_machine_shim/shim = machine_shim
	if(!shim)
		return FALSE
	return (shim.linked_machine() == checking)

/// deprecated, do not use
/mob/proc/unset_machine()
	var/datum/using_machine_shim/shim = machine_shim
	if(shim)
		spent(shim)

/// deprecated, do not use
/mob/proc/set_machine(obj/O)
	var/datum/using_machine_shim/shim = machine_shim
	if(shim)
		if(shim.linked_machine() == O) // Already in use
			return
		spent(shim)
		return
	new /datum/using_machine_shim(src, O)

/// deprecated, do not use
/obj/proc/updateUsrDialog(mob/user)
	if(in_use)
		var/is_in_use = 0
		var/list/nearby = viewers(1, src)
		for(var/mob/M in nearby)
			if ((M.client && M.check_current_machine(src)))
				is_in_use = 1
				src.attack_hand(M)
		if (isAI(user) || isrobot(user))
			if (!(user in nearby))
				if (user.client && user.check_current_machine(src)) // && M.machine == src is omitted because if we triggered this by using the dialog, it doesn't matter if our machine changed in between triggering it and this - the dialog is probably still supposed to refresh.
					is_in_use = 1
					actor_use(/datum/input_adapter/ai, user, src)

		// check for TK users

		if (ishuman(user))
			var/mob/living/carbon/human/H = user
			if(H.get_type_in_hands(/obj/item/tk_grab))
				if(!(H in nearby))
					if(H.client && H.check_current_machine(src))
						is_in_use = 1
						src.attack_hand(H)
		in_use = is_in_use

/// deprecated, do not use
/obj/machinery/CouldUseTopic(mob/user)
	..()
	user.set_machine(src)

/// deprecated, do not use
/obj/machinery/CouldNotUseTopic(mob/user)
	user.unset_machine()

/// Life: release the machine when the user leaves it (a step this shim contributes while it exists).
/datum/using_machine_shim/proc/life_steps()
	return list(seq_step(PROC_REF(life_trait_using_machine_shim), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_using_machine_shim"))

/datum/using_machine_shim/proc/life_trait_using_machine_shim(mob/living/user, datum/seq_frame/life/F)
	on_mob_life()

/// The mob using the machine (our owner).
/datum/using_machine_shim/proc/host_mob() as /mob
	return owner

/// The machine being used (a relation view).
/datum/using_machine_shim/proc/linked_machine() as /obj/machinery
	return linked_machine
