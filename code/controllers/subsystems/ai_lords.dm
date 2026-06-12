// Drives the per-pack /datum/ai_lord coordinators. Faster than SSai (the 2s
// member strategic tick) so a pack reacts to threats and re-shares targets
// promptly, but far cheaper than the per-mob fast tick — there's one lord per
// pack, not one per mob. SS_BACKGROUND: coordination is best-effort and yields
// to gameplay subsystems under load.
SUBSYSTEM_DEF(ai_lords)
	name = "AI Lords"
	priority = FIRE_PRIORITY_AI
	wait = LORD_TICK_INTERVAL
	flags = SS_NO_INIT | SS_BACKGROUND
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME

	dependencies = list(
		/datum/controller/subsystem/ai
	)

	var/list/lords = list()
	var/list/currentrun = list()

/datum/controller/subsystem/ai_lords/stat_entry(msg)
	msg = "L:[length(lords)]"
	return ..()

/datum/controller/subsystem/ai_lords/fire(resumed = 0)
	if(!resumed)
		src.currentrun = lords.Copy()
	var/list/currentrun = src.currentrun
	while(length(currentrun))
		var/datum/ai_lord/L = currentrun[length(currentrun)]
		--currentrun.len
		if(QDELETED(L))
			continue
		L.process_lord()
		if(MC_TICK_CHECK)
			return
