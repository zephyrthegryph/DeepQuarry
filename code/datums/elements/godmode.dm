/**
 * Attached to mobs. Gives them godmode by stopping damage, effects, embeds, among all other negative effects.
 */
/datum/element/godmode
	element_flags = ELEMENT_DETACH_ON_HOST_DESTROY|ELEMENT_BESPOKE
	argument_hash_start_idx = 2

/datum/element/godmode/Attach(datum/target)
	. = ..()
	//Must be appliied to mobs.
	if(!ismob(target))
		return ELEMENT_INCOMPATIBLE
	var/mob/our_target = target
	if(our_target.status_flags & GODMODE) //Already have it.
		return ELEMENT_INCOMPATIBLE
	our_target.status_flags |= GODMODE
	hold_incapacitation_immunity(our_target, src)
	if(issilicon(target))
		RegisterSignal(target, COMSIG_SILICON_EMP_ACT, PROC_REF(on_emp))

	if(isrobot(target))
		RegisterSignal(target, COMSIG_ROBOT_EMP_ACT, PROC_REF(on_emp))

	//Every injury of every kind (injure() also checks the GODMODE flag itself).
	RegisterSignal(target, COMSIG_LIVING_INJURE, PROC_REF(on_injure))

	RegisterSignal(target, COMSIG_TAKING_APPLY_EFFECT, PROC_REF(on_apply_effect))

	//For things that don't fall into a single bucket
	RegisterSignal(target, COMSIG_CHECK_FOR_GODMODE, PROC_REF(godmode_check))
	RegisterSignal(target, COMSIG_BEING_ELECTROCUTED, PROC_REF(on_electrocute))
	RegisterSignal(target, COMSIG_EMBED_OBJECT, PROC_REF(embed_check))


/datum/element/godmode/Detach(atom/movable/target)
	if(issilicon(target))
		UnregisterSignal(target, list(COMSIG_SILICON_EMP_ACT))

	if(isrobot(target))
		UnregisterSignal(target, list(COMSIG_ROBOT_EMP_ACT))

	//All the general comsigs.
	UnregisterSignal(target, list(COMSIG_LIVING_INJURE, COMSIG_TAKING_APPLY_EFFECT, COMSIG_CHECK_FOR_GODMODE, COMSIG_BEING_ELECTROCUTED, COMSIG_EMBED_OBJECT))
	var/mob/our_target = target

	//And finally, remove the fact we're in godmode.
	our_target.status_flags &= ~GODMODE
	release_incapacitation_immunity(our_target, src)
	return ..()

/datum/element/godmode/proc/on_injure()
	SIGNAL_HANDLER
	return COMPONENT_CANCEL_INJURY

/datum/element/godmode/proc/on_apply_effect()
	SIGNAL_HANDLER
	return COMSIG_CANCEL_EFFECT

/datum/element/godmode/proc/on_electrocute()
	SIGNAL_HANDLER
	return COMPONENT_CARBON_CANCEL_ELECTROCUTE

/datum/element/godmode/proc/embed_check()
	SIGNAL_HANDLER
	return COMSIG_CANCEL_EMBED

/datum/element/godmode/proc/on_emp()
	SIGNAL_HANDLER
	return COMPONENT_BLOCK_EMP

/datum/element/godmode/proc/godmode_check()
	SIGNAL_HANDLER
	return COMSIG_GODMODE_CANCEL


///The 'lite' version of godmode
/datum/element/lite_godmode
	element_flags = ELEMENT_DETACH_ON_HOST_DESTROY|ELEMENT_BESPOKE
	argument_hash_start_idx = 2

/datum/element/lite_godmode/Attach(datum/target)
	. = ..()
	if(!ismob(target))
		return ELEMENT_INCOMPATIBLE
	var/mob/our_target = target
	hold_incapacitation_immunity(our_target, src)
	RegisterSignal(target, COMSIG_LIVING_INJURE, PROC_REF(on_injure))
	RegisterSignal(target, COMSIG_LIVING_BODY_STATUS, PROC_REF(on_body_status))
	RegisterSignal(target, COMSIG_TAKING_APPLY_EFFECT, PROC_REF(on_apply_effect))

	if(ishuman(target))
		var/mob/living/carbon/human/the_target = target
		for(var/obj/item/organ/external/external_organs in the_target.organs)
			external_organs.cannot_amputate = TRUE
			external_organs.cannot_break = TRUE
			external_organs.cannot_gib = TRUE
			external_organs.stapled_nerves = TRUE

/datum/element/lite_godmode/Detach(atom/movable/target)
	var/mob/our_target = target
	UnregisterSignal(target, COMSIG_LIVING_INJURE)
	UnregisterSignal(target, COMSIG_LIVING_BODY_STATUS)
	UnregisterSignal(target, COMSIG_TAKING_APPLY_EFFECT)
	release_incapacitation_immunity(our_target, src)
	if(ishuman(target))
		var/mob/living/carbon/human/the_target = target
		for(var/obj/item/organ/external/external_organs in the_target.organs)
			external_organs.cannot_amputate = initial(external_organs.cannot_amputate)
			external_organs.cannot_break = initial(external_organs.cannot_break)
			external_organs.cannot_gib = initial(external_organs.cannot_gib)
			external_organs.stapled_nerves = initial(external_organs.stapled_nerves)
	return ..()

/datum/element/lite_godmode/proc/on_body_status()
	SIGNAL_HANDLER
	return COMPONENT_BODY_KEEP_ALIVE

/datum/element/lite_godmode/proc/on_apply_effect()
	SIGNAL_HANDLER
	return COMSIG_CANCEL_EFFECT

/// Lite godmode keeps the patient's internal organs intact: injuries aimed at
/// an internal organ, and neural (brain) injury, are cancelled.
/datum/element/lite_godmode/proc/on_injure(datum/source, kind, list/amount_ref, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	if(kind == INJURY_NEURAL || istype(zone, /obj/item/organ/internal))
		return COMPONENT_CANCEL_INJURY
	return NONE
