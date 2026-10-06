/// Makes a geiger counter play sounds depending on nearby radiation.
/// (Was /datum/component/geiger_sound; now a plain datum owned by the geiger, /obj/item/geiger var geiger_sound.)
/datum/geiger_sound
	/// The geiger counter we belong to.
	var/atom/owner
	var/last_parent = null
	var/wall_mounted = FALSE

/// The geiger loop, owned: deleted with this datum.
/datum/geiger_sound/var/datum/looping_sound/geiger/sound

CAPABILITIES(/datum/geiger_sound)
	owns_one(nameof(sound), /datum/looping_sound/geiger)


/// Owned: the active geiger sound loop while the counter is scanning.
/obj/item/geiger/var/datum/geiger_sound/geiger_sound

/datum/geiger_sound/New(atom/new_owner)
	..()
	if(!isatom(new_owner))
		log_world("[type] was created for a non-atom ([new_owner]); it does nothing.")
		return
	rel_set(src, nameof(owner), new_owner)
	attach()

/datum/geiger_sound/proc/attach()
	if(!wall_mounted)
		rel_set(src, nameof(sound), new /datum/looping_sound/geiger(list(owner), TRUE))

	observe(owner, /datum/notice/in_range_of_irradiation, src, then(PROC_REF(on_pre_potential_irradiation)))

	add_trait(owner, TRAIT_BYPASS_EARLY_IRRADIATED_CHECK, src)

	if (isitem(owner))
		var/atom/atom_parent = owner
		observe(owner, /datum/notice/moved, src, then(PROC_REF(on_moved)))
		register_to_loc(atom_parent.loc)

/datum/geiger_sound/proc/detach()
	if(!owner)
		return
	unobserve(owner, /datum/notice/moved, src)
	unobserve(owner, /datum/notice/in_range_of_irradiation, src)

	remove_trait(owner, TRAIT_BYPASS_EARLY_IRRADIATED_CHECK, src)

// owned state datum (was a component) unhooks and detaches from its owner.
/datum/geiger_sound/lifecycle_prerelease()
	..()
	detach() // reads owner, which phase 4 nulls
	last_parent = null

/datum/geiger_sound/proc/on_pre_potential_irradiation(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = N.target
	var/datum/notice/in_range_of_irradiation/event = N
	var/datum/radiation_pulse_information/pulse_information = event.pulse_information

	sound.last_insulation_to_target = event.insulation_to_target
	rel_set(sound, nameof(sound.last_radiation_pulse_ref), pulse_information)
	sound.start(source)

	after(sound, TIME_WITHOUT_RADIATION_BEFORE_RESET, TYPE_PROC_REF(/datum/looping_sound, stop), key = "geiger_sound_stop")

/datum/geiger_sound/proc/on_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/atom/source = A.target
	register_to_loc(source.loc)

/datum/geiger_sound/proc/register_to_loc(new_loc)
	if(last_parent == new_loc)
		return

	if(!isnull(last_parent))
		sound.stop(last_parent)
		unobserve(last_parent, /datum/notice/in_range_of_irradiation, src)

	last_parent = new_loc

	if(!isnull(new_loc))
		observe(new_loc, /datum/notice/in_range_of_irradiation, src, then(PROC_REF(on_pre_potential_irradiation)))

/datum/looping_sound/geiger
	mid_sounds = list(
		list('sound/items/geiger/low1.ogg'=1, 'sound/items/geiger/low2.ogg'=1, 'sound/items/geiger/low3.ogg'=1, 'sound/items/geiger/low4.ogg'=1),
		list('sound/items/geiger/med1.ogg'=1, 'sound/items/geiger/med2.ogg'=1, 'sound/items/geiger/med3.ogg'=1, 'sound/items/geiger/med4.ogg'=1),
		list('sound/items/geiger/high1.ogg'=1, 'sound/items/geiger/high2.ogg'=1, 'sound/items/geiger/high3.ogg'=1, 'sound/items/geiger/high4.ogg'=1),
		list('sound/items/geiger/ext1.ogg'=1, 'sound/items/geiger/ext2.ogg'=1, 'sound/items/geiger/ext3.ogg'=1, 'sound/items/geiger/ext4.ogg'=1)
	)
	mid_length = 2
	volume = 25

	var/tmp/datum/radiation_pulse_information/last_radiation_pulse_ref
	var/last_insulation_to_target
	var/wall_mounted = FALSE

/datum/looping_sound/geiger/get_sound(starttime, _mid_sounds, danger)
	if(wall_mounted) //Child does all the work.
		return ..(starttime, mid_sounds[danger])

	if (isnull(last_radiation_pulse()))
		return null
	danger = get_perceived_radiation_danger(last_radiation_pulse(), last_insulation_to_target)

	if(danger >= PERCEIVED_RADIATION_DANGER_HIGH)
		chance = 100
	else
		chance = danger * 15
	volume = (danger * 5)

	return ..(starttime, mid_sounds[danger])

/datum/looping_sound/geiger/stop(null_parent = FALSE)
	. = ..()

	rel_clear(src, nameof(last_radiation_pulse_ref))

/datum/geiger_sound/wall
	wall_mounted = TRUE

/datum/geiger_sound/wall/attach()
	rel_set(src, nameof(sound), new /datum/looping_sound/geiger/wall(list(owner), TRUE))
	..()

//Subtype for wall mounted geiger counters, which should be quieter and not have the chance to play when radiation is low.
/datum/looping_sound/geiger/wall
	wall_mounted = TRUE

/datum/looping_sound/geiger/wall/get_sound(starttime, _mid_sounds)
	if (isnull(last_radiation_pulse()))
		return null

	var/danger = get_perceived_radiation_danger(last_radiation_pulse(), last_insulation_to_target)

	if(danger >= PERCEIVED_RADIATION_DANGER_HIGH)
		chance = 100
		volume = (danger * 5)
	else
		chance = 0
		volume = 0

	return ..(starttime, mid_sounds[danger], danger)

/// A strong internal reference (tmp): this holder is what keeps it alive.
/datum/looping_sound/geiger/proc/last_radiation_pulse() as /datum/radiation_pulse_information
	return last_radiation_pulse_ref
