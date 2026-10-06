// Small behaviours on the OM wheel (object_model_core.md §4.11): deleting later, and
// sequences a thing plays out over a few ticks. Each is a real behaviour, not a generic write:
// state that changes later changes through its own setter (om_after(E, d, PROC_REF(setter)))
// so its channel is raised, and a "temporary X that undoes itself" is a timed status or
// contribution (om_apply(), status_at_least()), never a var written back by name.

/// om_after() target: deletes the owner.
/datum/proc/om_qdel_self()
	spent(src)

/// om_after() target: deletes the owner as one batched destroy
/// (code/datums/lifecycle/batch.dm), with `extra` in the same set.
/datum/proc/om_qdel_batch_self(list/extra)
	var/list/doomed = list(src)
	if(extra)
		doomed += extra
	qdel_batch(doomed)

/// Deletes `D` after `delay` deciseconds of its own clock. Null-safe.
/proc/om_qdel_after(datum/D, delay)
	if(!D || QDELETED(D))
		return
	if(!isdatum(D)) // an image or a list: nothing owns it, so the global owner does
		return om_after(null, delay, /proc/qdel, D)
	return om_after(D, delay, /datum/proc/om_qdel_self)

/// Knocks the thing about: `steps` random steps, a few deciseconds apart.
/atom/movable/proc/scatter_steps(steps)
	var/delay = 0
	for(var/i in 1 to steps)
		om_after(src, delay, PROC_REF(scatter_step))
		delay += rand(2, 4)

/atom/movable/proc/scatter_step()
	step(src, pick(GLOB.cardinal))

/// Turns through `dirs` in order, `interval` deciseconds apart (a wiggle or a dance).
/atom/proc/dir_sequence(list/dirs, interval = 1)
	var/delay = 0
	for(var/d in dirs)
		om_after(src, delay, TYPE_PROC_REF(/atom, set_dir), d)
		delay += interval

/// Cycles the atom's colour through `colors`, `interval` deciseconds apart (a warning flash).
/atom/proc/color_sequence(list/colors, interval = 1)
	var/delay = 0
	for(var/c in colors)
		om_after(src, delay, TYPE_PROC_REF(/atom, set_base_color), c)
		delay += interval

/// om_after() target: a message to the owner (a mob, or anything to_chat accepts).
/datum/proc/om_chat(...)
	for(var/message in args)
		to_chat(src, message)

/// om_after() target: plays a sound at the owner.
/atom/proc/om_playsound(soundin, vol, vary)
	playsound(src, soundin, vol, vary)

/// om_after() target: one step in direction `d`.
/atom/movable/proc/om_step(d)
	step(src, d)

/// om_after() target: a command announcement (for delayed event announcements; use the
/// global owner, since no entity owns a round event).
/proc/delayed_command_announcement(message, new_title, new_sound)
	GLOB.command_announcement.Announce(message, new_title, new_sound = new_sound)

/// Starts the effect `times` times, `interval` deciseconds apart, on the effect's own clock.
/datum/effect/effect/system/proc/start_repeatedly(times, interval)
	for(var/i in 0 to times - 1)
		om_after(src, i * interval, PROC_REF(start))

/// om_after() target: takes an image off a mob's client screen (after a fade-out).
/proc/remove_client_image(mob/M, image/I)
	M.client?.images -= I

/// Nearsighted for good (the disability) or for a while (STAT_NEARSIGHTED: a flash, a sting).
/mob/proc/is_nearsighted()
	return (disabilities & NEARSIGHTED) || has_status(STAT_NEARSIGHTED)
