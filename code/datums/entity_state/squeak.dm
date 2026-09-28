//You know, with some intelligent coding.. you could add onto this code to handle the turf based footstep sounds, and be away with those turf lists all together
//Partial squeak port from tg. Commented out stuff we don't have.
/// Squeaky footsteps/handling for shoes. An owned state datum held in the shoes' `squeak` var
/// (was /datum/component/squeak); add it with /obj/item/clothing/shoes/proc/make_squeaky().
/datum/squeak
	var/static/list/default_squeak_sounds = list('sound/items/bikehorn.ogg'=1, 'sound/voice/quack.ogg'=1)
	var/list/override_squeak_sounds
	var/holder_handle

	var/squeak_chance = 100
	var/volume = 30

	// This is so shoes don't squeak every step
	var/steps = 0
	var/step_delay = 0	// Changed from 0 to 1 to make the sounds more consistent with movespeed.

	// This is to stop squeak spam from inhand usage
	COOLDOWN_DECLARE(use_cooldown)
	var/use_delay = 20

	///extra-range for this squeak's sound
	var/sound_extra_range = -1
	/*
	///when sounds start falling off for the squeak
	var/sound_falloff_distance = 1
	///sound exponent for squeak. Defaults to 10 as squeaking is loud and annoying enough.
	var/sound_falloff_exponent = 10
	*/
	/// The squeaky shoes.
	var/obj/item/clothing/shoes/owner

DECLARE_REF(/datum/squeak, "owner", BACK, "squeak")
/obj/item/clothing/shoes/var/datum/squeak/squeak // ALLOW(state_ref): owned child (DECLARE_REF OWNED); saved as before, the one-line REF_VAR form hid it from this lint
DECLARE_REF(/obj/item/clothing/shoes, "squeak", OWNED, null)

/// Gives these shoes a squeak (was LoadComponent(/datum/component/squeak, ...)): returns the
/// existing one when they already squeak.
/obj/item/clothing/shoes/proc/make_squeaky(custom_sounds, volume_override, chance_override, step_delay_override, use_delay_override, extrarange)
	RETURN_TYPE(/datum/squeak)
	if(!squeak)
		squeak = new /datum/squeak(src, custom_sounds, volume_override, chance_override, step_delay_override, use_delay_override, extrarange)
	return squeak

/datum/squeak/New(obj/item/clothing/shoes/owner, custom_sounds, volume_override, chance_override, step_delay_override, use_delay_override, extrarange)
	..()
	src.owner = owner
	om_hook(owner, list(/datum/om/event/atom_entered, /datum/om/event/before/movable_bump, /datum/om/event/movable_impact), src, PROC_REF(on_squeak_event))

	//Disposals stuff we don't have
	//(was a loc-behalf connection for item_connections)
	//RegisterSignal(parent, COMSIG_MOVABLE_DISPOSING, PROC_REF(disposing_react))
	//RegisterSignals(parent, list(COMSIG_ITEM_ATTACK, COMSIG_ITEM_ATTACK_ATOM, COMSIG_ITEM_HIT_REACT), PROC_REF(play_squeak))
	om_hook(owner, /datum/om/event/before/attack_self, src, PROC_REF(on_attack_self))
	om_hook(owner, /datum/om/event/item_equipped, src, PROC_REF(on_equip))
	om_hook(owner, /datum/om/event/item_dropped, src, PROC_REF(on_drop))
	om_hook(owner, /datum/om/event/before/shoes_step_action, src, PROC_REF(on_step))

	override_squeak_sounds = custom_sounds
	if(chance_override)
		squeak_chance = chance_override
	if(volume_override)
		volume = volume_override
	if(isnum(step_delay_override))
		step_delay = step_delay_override
	if(isnum(use_delay_override))
		use_delay = use_delay_override
	if(isnum(extrarange))
		sound_extra_range = extrarange

/datum/squeak/proc/on_squeak_event(datum/source, datum/om/event/event)
	EVENT_HANDLER
	play_squeak()

/datum/squeak/proc/play_squeak(volume_mod = 1)
	if(prob(squeak_chance))
		if(!override_squeak_sounds)
			playsound(owner, pick_weight(default_squeak_sounds), volume * volume_mod, TRUE, sound_extra_range)
		else
			playsound(owner, pick_weight(override_squeak_sounds), volume * volume_mod, TRUE, sound_extra_range)

/datum/squeak/proc/on_step(obj/item/clothing/shoes/source, datum/om/event/before/shoes_step_action/event)
	EVENT_HANDLER
	return step_squeak(source, event.m_intent)

/datum/squeak/proc/step_squeak(obj/item/clothing/shoes/source, running)
	if(running == I_WALK)
		running = 0.25
	else
		running = 1
	if(steps > step_delay)
		play_squeak(running)
		steps = 0
	else
		steps++
	return 1

/datum/squeak/proc/play_squeak_crossed(datum/source, atom/movable/arrived, atom/old_loc, list/atom/old_locs)
	/* We don't have abstract items yet
	if(isitem(arrived))
		var/obj/item/I = arrived
		if(I.item_flags & ABSTRACT)
			return
	//Annoyingly, our flight code doesn't set the movement_type, nor do we have a define for it. So I'm not adding it yet.
	//if(arrived.movement_type & (FLYING|FLOATING) || !arrived.get_gravity())
	*/
	if(!arrived.get_gravity())
		return
	if(ismob(arrived) && !arrived.density) // Prevents 10 overlapping mice from making an unholy sound while moving
		return
	var/atom/current_parent = owner
	if(isturf(current_parent?.loc))
		play_squeak()

/datum/squeak/proc/on_attack_self(datum/source, datum/om/event/before/attack_self/event)
	EVENT_HANDLER
	use_squeak()

/datum/squeak/proc/use_squeak()
	if(COOLDOWN_FINISHED(src, use_cooldown))
		COOLDOWN_START(src, use_cooldown, use_delay)
		play_squeak()

/datum/squeak/proc/on_equip(datum/source, datum/om/event/item_equipped/event)
	EVENT_HANDLER
	// An OM handle reads null once the holder is deleted, so no deletion hook is needed.
	holder_handle = om_handle(event.equipper)

/datum/squeak/proc/on_drop(datum/source, datum/om/event/item_dropped/event)
	EVENT_HANDLER
	holder_handle = null

/*	We don't have events set up for these
// Disposal pipes related shits
/datum/squeak/proc/disposing_react(datum/source, obj/structure/disposalholder/disposal_holder, obj/machinery/disposal/disposal_source)
	//We don't need to worry about unhooking as it will happen for us automaticaly when the holder is qdeleted
	om_hook(disposal_holder, /datum/om/event/atom_dir_change, src, PROC_REF(holder_dir_change))

/datum/squeak/proc/holder_dir_change(datum/source, old_dir, new_dir)
	//If the dir changes it means we're going through a bend in the pipes, let's pretend we bumped the wall
	if(old_dir != new_dir)
		play_squeak()
*/

/// LC-refs: the mob wearing the squeaky thing -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/squeak/proc/holder() as /mob
	return om_resolve(holder_handle)
