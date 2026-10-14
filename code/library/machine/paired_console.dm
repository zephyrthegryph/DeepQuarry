// paired_console(target_type, partner, faces =) (doc/rewrite/final_api.html, section 6 "Lifecycle": after_init(); section 11 "The library"): a
// console that works the machine beside it, a sleeper's or a body scanner's.
//
//   CAPABILITIES(/obj/machinery/sleep_console)
//       paired_console(/obj/machinery/sleeper, nameof(sleeper))
//       links(/obj/machinery/sleep_console::sleeper, /obj/machinery/sleeper::console)
//       interface("Sleeper", title = "Sleeper", forwards = nameof(sleeper))   the window is the sleeper's panel: its buttons and its data
//       extend("ui_open", needs(req_paired(nameof(sleeper))))                  no window without a sleeper
//
// When the console's init is complete (an after_init(0): for a mapped console, the whole map around it exists and has initialized) it looks on the
// four tiles around it for a `target_type` and writes it into `partner`, a links() var, so the machine learns its console in the same write. With
// `faces` the console turns toward it. A console with nothing beside it pairs with nothing; a multitool, or the machine being rebuilt beside it, pairs
// it later through rel_set(). Nothing is looked for again on a click: the old consoles' search on every touch is gone.

MSG_DEF_SELF(paired_console/missing, "It isn't connected to anything.")

CAPABILITY_TYPE(paired_console, CAP_PAIRED_CONSOLE, /datum/capability/lib/paired_console, key = NONE, target_type = null, partner = null, faces = FALSE)

/datum/capability/lib/paired_console

/datum/capability/lib/paired_console/entries()
	return list(after_init(0, then(CAP_PROC(pair))))

/// Pairs the console with the first `target_type` on a tile beside it, unless something already paired it.
/datum/capability/lib/paired_console/proc/pair(datum/act/timer/A)
	var/atom/holder = A.holder
	if(!istype(holder) || QDELETED(holder) || !(partner in holder.vars) || holder.vars[partner])
		return
	for(var/direction in GLOB.cardinal)
		var/atom/found = locate_within(get_step(holder, direction), target_type)
		if(!found)
			continue
		rel_set(holder, partner, found)
		if(faces)
			holder.set_dir(direction)
		log_world("PAIRED_CONSOLE: [holder.type] at [AREACOORD(holder)] paired with [found.type] to the [dir2text(direction)]")
		return

/// The console is paired: its `partner` var names a machine. Refused with "It isn't connected to anything."
/proc/req_paired(partner)
	return req_full(partner, because = MSG(paired_console/missing))
