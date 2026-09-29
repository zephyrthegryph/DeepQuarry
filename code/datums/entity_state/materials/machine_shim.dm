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
	var/linked_machine_handle
	/// The mob using the machine.
	var/mob/owner

/mob/var/datum/using_machine_shim/machine_shim

/datum/using_machine_shim/New(mob/new_owner, obj/machinery/machine)
	..()
	rel_set(src, "owner", new_owner)
	own_set(owner, "machine_shim", src)
	// Mob
	om_stage_add(host_mob(), /datum/om/stage/life/trait/using_machine_shim)
	om_hook(host_mob(), /datum/om/event/movable_attempted_move, src, PROC_REF(on_mob_moved))
	om_hook(host_mob(), /datum/om/event/mob_logout, src, PROC_REF(on_mob_logout))

	// Machine
	linked_machine_handle = om_handle(machine)
	om_hook(linked_machine(), /datum/om/event/qdeleting, src, PROC_REF(on_machine_qdelete))
	linked_machine().in_use = TRUE

	// Lets complain if an object uses TGUI but is still setting the machine.
	if(length(linked_machine().tgui_data()))
		log_world("## ERROR [machine.type] implements tgui_data(), and has likely been ported to tgui already. It should no longer use set_machine().")

// the machine is free again and the operator's perspective and trait reset.
/datum/using_machine_shim/lifecycle_prerelease()
	..()
	var/obj/machinery/machine = linked_machine()
	if(machine)
		machine.in_use = FALSE
	if(owner)
		om_stage_remove(owner, /datum/om/stage/life/trait/using_machine_shim)
		owner.reset_perspective()

/datum/using_machine_shim/proc/on_mob_moved(datum/source, datum/om/event/movable_attempted_move/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	on_mob_action()

/datum/using_machine_shim/proc/on_mob_action()
	SHOULD_NOT_OVERRIDE(TRUE)
	if(host_mob().stat == DEAD || !host_mob().client || !host_mob().Adjacent(linked_machine()))
		qdel(src)

/// Called by the using machine shim trait system each Life() cycle.
/datum/using_machine_shim/proc/on_mob_life()
	on_mob_action()

/datum/using_machine_shim/proc/on_machine_qdelete(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	qdel(src)

/datum/using_machine_shim/proc/on_mob_logout(datum/source, datum/om/event/mob_logout/event)
	EVENT_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	qdel(src)

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
		qdel(shim)

/// deprecated, do not use
/mob/proc/set_machine(obj/O)
	var/datum/using_machine_shim/shim = machine_shim
	if(shim)
		if(shim.linked_machine() == O) // Already in use
			return
		qdel(shim)
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

/// Trait system: release the machine when the user leaves it.
/datum/om/stage/life/trait/using_machine_shim
	name = "using machine shim"

/datum/om/stage/life/trait/using_machine_shim/perform(mob/living/self, datum/om/frame/life/ctx)
	self.machine_shim?.on_mob_life()

/// The mob using the machine (our owner).
/datum/using_machine_shim/proc/host_mob() as /mob
	return owner

/// LC-refs: the machine being used -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/using_machine_shim/proc/linked_machine() as /obj/machinery
	return om_resolve(linked_machine_handle)
