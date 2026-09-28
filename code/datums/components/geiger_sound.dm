/// Makes a geiger counter play sounds depending on nearby radiation.
/// (Was /datum/component/geiger_sound; now a plain datum owned by the geiger, /obj/item/geiger var geiger_sound.)
/datum/geiger_sound
	/// The geiger counter we belong to.
	var/atom/owner
	var/last_parent = null
	var/wall_mounted = FALSE

/// The geiger loop, owned: deleted with this datum.
REF_VAR(/datum/geiger_sound, OWNED, /datum/looping_sound/geiger, sound)

REF_BACK(/datum/geiger_sound, list("owner" = "geiger_sound"))

/// Owned: the active geiger sound loop while the counter is scanning.
REF_VAR(/obj/item/geiger, OWNED, /datum/geiger_sound, geiger_sound)

/datum/geiger_sound/New(atom/new_owner)
	..()
	if(!isatom(new_owner))
		log_world("[type] was created for a non-atom ([new_owner]); it does nothing.")
		return
	owner = new_owner
	attach()

/datum/geiger_sound/proc/attach()
	if(!wall_mounted)
		sound = new(list(owner), TRUE)

	om_hook(owner, /datum/om/event/before/in_range_of_irradiation, src, PROC_REF(on_pre_potential_irradiation))

	ADD_TRAIT(owner, TRAIT_BYPASS_EARLY_IRRADIATED_CHECK, REF(src))

	if (isitem(owner))
		var/atom/atom_parent = owner
		om_hook(owner, /datum/om/event/moved, src, PROC_REF(on_moved))
		register_to_loc(atom_parent.loc)

/datum/geiger_sound/proc/detach()
	if(!owner)
		return
	om_unhook(owner, list(
		/datum/om/event/moved,
		/datum/om/event/before/in_range_of_irradiation,
	), src)

	REMOVE_TRAIT(owner, TRAIT_BYPASS_EARLY_IRRADIATED_CHECK, REF(src))

// ALLOW(lifecycle): owned state datum (was a component) unhooks and detaches from its owner.
/datum/geiger_sound/Destroy(force)
	detach()
	if(!isnull(last_parent))
		om_unhook(last_parent, /datum/om/event/before/in_range_of_irradiation, src)
	last_parent = null
	owner = null
	return ..()

/datum/geiger_sound/proc/on_pre_potential_irradiation(datum/source, datum/om/event/before/in_range_of_irradiation/event)
	EVENT_HANDLER
	var/datum/radiation_pulse_information/pulse_information = event.pulse_information

	sound.last_insulation_to_target = event.insulation_to_target
	sound.last_radiation_pulse_handle = om_handle(pulse_information)
	sound.start(source)

	om_after_replace(sound, TIME_WITHOUT_RADIATION_BEFORE_RESET, TYPE_PROC_REF(/datum/looping_sound,stop))

/datum/geiger_sound/proc/on_moved(atom/source, datum/om/event/moved/event)
	EVENT_HANDLER
	register_to_loc(source.loc)

/datum/geiger_sound/proc/register_to_loc(new_loc)
	if(last_parent == new_loc)
		return

	if(!isnull(last_parent))
		sound.stop(last_parent)
		om_unhook(last_parent, /datum/om/event/before/in_range_of_irradiation, src)

	last_parent = new_loc

	if(!isnull(new_loc))
		om_hook(new_loc, /datum/om/event/before/in_range_of_irradiation, src, PROC_REF(on_pre_potential_irradiation))

/datum/looping_sound/geiger
	mid_sounds = list(
		list('sound/items/geiger/low1.ogg'=1, 'sound/items/geiger/low2.ogg'=1, 'sound/items/geiger/low3.ogg'=1, 'sound/items/geiger/low4.ogg'=1),
		list('sound/items/geiger/med1.ogg'=1, 'sound/items/geiger/med2.ogg'=1, 'sound/items/geiger/med3.ogg'=1, 'sound/items/geiger/med4.ogg'=1),
		list('sound/items/geiger/high1.ogg'=1, 'sound/items/geiger/high2.ogg'=1, 'sound/items/geiger/high3.ogg'=1, 'sound/items/geiger/high4.ogg'=1),
		list('sound/items/geiger/ext1.ogg'=1, 'sound/items/geiger/ext2.ogg'=1, 'sound/items/geiger/ext3.ogg'=1, 'sound/items/geiger/ext4.ogg'=1)
	)
	mid_length = 2
	volume = 25

	var/last_radiation_pulse_handle
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

	last_radiation_pulse_handle = null

/datum/geiger_sound/wall
	wall_mounted = TRUE

/datum/geiger_sound/wall/attach()
	sound = new /datum/looping_sound/geiger/wall(list(owner), TRUE)
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

/// LC-refs: the last radiation pulse that reached us -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/looping_sound/geiger/proc/last_radiation_pulse() as /datum/radiation_pulse_information
	return om_resolve(last_radiation_pulse_handle)
