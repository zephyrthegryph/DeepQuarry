/**
 * Godmode (was /datum/element/godmode). Holds EFFECT_GODMODE (which implies the
 * incapacitation immunities); injure(), apply_effects(), electrocute_act(), embedding
 * and silicon EMPs check om_has(mob, EFFECT_GODMODE) themselves, so nothing listens.
 */
/datum/godmode_source

/// The one contribution source for godmode holds.
/proc/godmode_source()
	var/static/datum/godmode_source/source = new
	return source

/// Puts `M` in godmode. FALSE if it already was.
/proc/godmode_enable(mob/M)
	if(!ismob(M) || om_has(M, EFFECT_GODMODE))
		return FALSE
	om_hold(M, EFFECT_GODMODE, godmode_source())
	return TRUE

/// Takes `M` out of godmode.
/proc/godmode_disable(mob/M)
	if(!ismob(M))
		return
	om_release(M, EFFECT_GODMODE, godmode_source())

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
