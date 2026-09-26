// Small targets for om_after() (object_model_core.md §4.11), for the one-liners that
// used to be `spawn(d)` bodies: delete the owner, clear or set a var, or set a var and
// then call a proc, all on the owner's clock and cancelled with it.

/// om_after() target: deletes the owner.
/datum/proc/om_qdel_self()
	qdel(src)

/// Deletes `D` after `delay` deciseconds of its own clock. Null-safe.
/proc/om_qdel_after(datum/D, delay)
	if(D && !QDELETED(D))
		om_after(D, delay, /datum/proc/om_qdel_self)

/// om_after() target: sets var `name` on the owner to `value`.
/datum/proc/om_set_var(name, value)
	vars[name] = value

/// om_after() target: sets var `name` on the owner, then calls `proc_ref` on it.
/datum/proc/om_set_var_then(name, value, proc_ref)
	vars[name] = value
	call(src, proc_ref)()

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
		om_after(src, delay, TYPE_PROC_REF(/datum, om_set_var), "color", c)
		delay += interval

/// om_after() target: a message to the owner (a mob, or anything to_chat accepts).
/datum/proc/om_chat(...)
	for(var/message in args)
		to_chat(src, message)

/// om_after() target: plays a sound at the owner.
/atom/proc/om_playsound(soundin, vol, vary)
	playsound(src, soundin, vol, vary)

/// om_after() target: a temporary disability (`flag` of `disabilities`) wears off.
/mob/proc/cure_temporary_disability(flag)
	disabilities &= ~flag

/// om_after() target: flips boolean var `name` on the owner (a temporary toggle undoing itself).
/datum/proc/om_toggle_var(name)
	vars[name] = !vars[name]
