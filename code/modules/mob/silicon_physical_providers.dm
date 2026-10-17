// Physical transactions and values are provided by the actual actor. These do
// not substitute a remote interface for a body, hand, grip or inventory slot.

/mob/proc/wall_plating_duration()
	return 4 SECONDS

/mob/living/silicon/robot/wall_plating_duration()
	return 1.5 SECONDS

/// Opening exposed wires is a physical device transaction, unavailable to AI eyes.
/mob/proc/open_exposed_wiring(atom/device)
	wires_open(device, src)

/mob/living/silicon/ai/open_exposed_wiring(atom/device)
	return

/// Inventory removal consults the actor's slot model. Silicon grippers have no
/// equipment slot identifier; their carried items still honor canremove.
/mob/proc/can_unequip_item(obj/item/I, slot, disable_warning = FALSE)
	if(!I.canremove || !slot)
		return 0
	return slot_is_accessible(slot, I, disable_warning ? null : src) ? 1 : 0

/mob/living/silicon/can_unequip_item(obj/item/I, slot, disable_warning = FALSE)
	if(!I.canremove)
		return 0
	if(!slot)
		return 1
	return ..()

/// Assembly authorization is an actor credential, independent of the brain's passenger.
/mob/proc/robot_assembly_refusal(obj/item/component)
	return null

/mob/living/silicon/robot/ai_shell/robot_assembly_refusal(obj/item/component)
	if(istype(component, /obj/item/mmi/inert/ai_remote))
		return span_warning("Your hardware prohibits you from self-replicating.")
	return null

/// Buckling is performed by the actor's physical body. A pAI has no such
/// transaction; adjacency and restraint checks are not replaced by remote reach.
/mob/proc/secure_buckle_mob(atom/movable/seat, mob/living/passenger, forced = FALSE, silent = FALSE)
	if(!Adjacent(passenger) || restrained() || stat)
		return FALSE
	return seat.finish_user_buckle(passenger, src, forced, silent)

/mob/living/silicon/pai/secure_buckle_mob(atom/movable/seat, mob/living/passenger, forced = FALSE, silent = FALSE)
	return FALSE

/// Concrete evidence authorizing a restraint action: the actor itself for self
/// application, otherwise its actual aggressive grab of the intended subject.
/mob/proc/restraint_evidence(mob/subject, adjacent_required = FALSE)
	if(subject == src)
		return src
	for(var/obj/item/grab/G in subject?.grabbed_by_list())
		if(G.loc == src && G.state >= GRAB_AGGRESSIVE)
			return G
	return null

/// Borg hardware supplies the grip. Cuffs require adjacent hardware, whereas
/// tape historically permits the hardware grip independently of this extra test.
/mob/living/silicon/robot/restraint_evidence(mob/subject, adjacent_required = FALSE)
	if(subject == src || !adjacent_required || Adjacent(subject))
		return src
	return null

/// Emptying a storage item is a physical transaction provided by human and borg
/// manipulators; an interface alone cannot spill the contents onto a floor.
/mob/proc/empty_storage(obj/item/storage/container)
	return FALSE

/mob/living/carbon/human/empty_storage(obj/item/storage/container)
	return container.finish_quick_empty(src)

/mob/living/silicon/robot/empty_storage(obj/item/storage/container)
	return container.finish_quick_empty(src)
