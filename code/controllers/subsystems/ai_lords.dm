// Drives the per-pack /datum/ai_lord coordinators. Faster than SSai (the 2s
// member strategic tick) so a pack reacts to threats and re-shares targets
// promptly, but far cheaper than the per-mob fast tick — there's one lord per
// pack, not one per mob.
//
// NOT SS_BACKGROUND: the lord is the pack's reaction driver — it spots the player
// and commands the WHOLE pack to engage in one tick. Backgrounding it let the
// busy per-mob AI subsystems starve it, so targeting fell back to each mob's slow
// 2s strategic tick (the "10s to lock eyes, only a few move at a time" lag). It's
// cheap (one scan + commands per pack), so it runs every tick like SSai.
SUBSYSTEM_DEF(ai_lords)
	name = "AI Lords"
	priority = FIRE_PRIORITY_AI
	wait = LORD_TICK_INTERVAL
	flags = SS_NO_INIT
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
