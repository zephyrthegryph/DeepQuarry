//You know, with some intelligent coding.. you could add onto this code to handle the turf based footstep sounds, and be away with those turf lists all together
//Partial squeak port from tg. Commented out stuff we don't have.
/// Squeaky footsteps/handling for shoes. An owned state datum held in the shoes' `squeak` var
///; add it with /obj/item/clothing/shoes/proc/make_squeaky().
/datum/squeak
	var/static/list/default_squeak_sounds = list('sound/items/bikehorn.ogg'=1, 'sound/voice/quack.ogg'=1)
	var/list/override_squeak_sounds
	var/mob/holder

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
	*/
	/// The squeaky shoes.
	var/obj/item/clothing/shoes/owner

CAPABILITIES(/datum/squeak)
	ref_one(nameof(holder))
	ref_one(nameof(owner))

/// Not saved: make_squeaky() in Initialize() rebuilds it.
/obj/item/clothing/shoes/var/tmp/datum/squeak/squeak

/// Gives these shoes a squeak (was LoadComponent(/datum/component/squeak, ...)): returns the
/// existing one when they already squeak.
/obj/item/clothing/shoes/proc/make_squeaky(custom_sounds, volume_override, chance_override, step_delay_override, use_delay_override, extrarange)
	RETURN_TYPE(/datum/squeak)
	if(!squeak)
		rel_set(src, nameof(squeak), new /datum/squeak(src, custom_sounds, volume_override, chance_override, step_delay_override, use_delay_override, extrarange))
	return squeak

/datum/squeak/New(obj/item/clothing/shoes/owner, custom_sounds, volume_override, chance_override, step_delay_override, use_delay_override, extrarange)
	..()
	rel_set(src, nameof(owner), owner)
	observe(owner, /datum/notice/atom_entered, src, then(PROC_REF(on_squeak_event)))
	observe(owner, /datum/notice/movable_bump, src, then(PROC_REF(on_squeak_event)))
	observe(owner, /datum/notice/movable_impact, src, then(PROC_REF(on_squeak_event)))
	observe(owner, /datum/notice/self_attacked, src, then(PROC_REF(on_attack_self)))
	observe(owner, /datum/notice/item_equipped, src, then(PROC_REF(on_equip)))
	observe(owner, /datum/notice/item_dropped, src, then(PROC_REF(on_drop)))
	observe(owner, /datum/notice/shoes_step, src, then(PROC_REF(on_step)))

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

/datum/squeak/proc/on_squeak_event(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	play_squeak()

/datum/squeak/proc/play_squeak(volume_mod = 1)
	if(prob(squeak_chance))
		if(!override_squeak_sounds)
			playsound(owner, pick_weight(default_squeak_sounds), volume * volume_mod, TRUE, sound_extra_range)
		else
			playsound(owner, pick_weight(override_squeak_sounds), volume * volume_mod, TRUE, sound_extra_range)

/datum/squeak/proc/on_step(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/shoes_step/N = A
	step_squeak(owner, N.m_intent)

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

/datum/squeak/proc/on_attack_self(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	use_squeak()

/datum/squeak/proc/use_squeak()
	if(COOLDOWN_FINISHED(src, use_cooldown))
		COOLDOWN_START(src, use_cooldown, use_delay)
		play_squeak()

/datum/squeak/proc/on_equip(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/item_equipped/event = A
	// The relation view clears once the holder is deleted, so no deletion hook is needed.
	rel_set(src, nameof(holder), event.equipper)

/datum/squeak/proc/on_drop(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	rel_clear(src, nameof(holder))



/// The mob wearing the squeaky thing (a relation view).
/datum/squeak/proc/holder() as /mob
	return holder
