/// A prototype made once at world setup and shared, never deleted in a round: a reference to one cannot pin a deleted object (relations proposal wave 2).
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/pai_software)

/datum/pai_software
	// Name for the software. This is used as the button text when buying or opening/toggling the software
	var/name = "pAI software module"
	// RAM cost; pAIs start with 100 RAM, spending it on programs
	var/ram_cost = 0
	// ID for the software. This must be unique
	var/id = ""
	// Whether this software is a toggle or not
	// Toggled software should override toggle() and is_active()
	// Non-toggled software should override on_ui_interact() and Topic()
	var/toggle = 1
	// Whether pAIs should automatically receive this module at no cost
	var/default = 0

/datum/pai_software/proc/toggle(mob/living/silicon/pai/user)
	return

/datum/pai_software/proc/is_active(mob/living/silicon/pai/user)
	return 0

CAPABILITIES(/datum/pai_software)
	// Only a pAI works a program's buttons (silently: anyone else is not answered).
	extend(TAG_UI, needs(req_actor_kind(/mob/living/silicon/pai, because = /datum/msg/req_silent)))

/datum/pai_software/tgui_status(mob/user)
	if(!ispAI(user))
		return STATUS_CLOSE
	return ..()

/mob/living/silicon/pai/proc/hackloop()
	var/turf/T = get_turf(src)
	for(var/mob/living/silicon/ai/AI in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(T.loc)
			to_chat(AI, span_bolddanger("Network Alert: Brute-force encryption crack in progress in [T.loc]."))
		else
			to_chat(AI, span_bolddanger("Network Alert: Brute-force encryption crack in progress. Unable to pinpoint location."))
	var/obj/machinery/door/D = cable.machine()
	if(!istype(D))
		set_hack_aborted(1)
		set_hackprogress(0)
		rel_clear(cable, nameof(cable.machine))
		rel_clear(src, nameof(hackdoor))
		return
	hack_tick()

/// One second of brute-forcing the door (its every() runs while hackdoor is set).
/mob/living/silicon/pai/proc/hack_tick(datum/act/A)
	if(cable && cable.machine() == hackdoor && get_dist(src, hackdoor) <= 1)
		set_hackprogress(min(hackprogress+rand(1, 20), 1000))
	else
		set_hack_aborted(1)
		set_hackprogress(0)
		rel_clear(src, nameof(hackdoor))
	if(hackprogress >= 1000)
		set_hackprogress(0)
		hackdoor.open()
		rel_clear(cable, nameof(cable.machine))
		rel_clear(src, nameof(hackdoor))
