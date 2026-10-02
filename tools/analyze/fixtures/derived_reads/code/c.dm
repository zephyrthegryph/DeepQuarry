// Types with no derived() are skipped in the CI run (reads.dm covers them), a capability is never
// scanned, a subtype of a declaring type is exact through its ancestor.
/obj/legacy
	var/energy = 1

/obj/legacy/should_run()
	return energy

/obj/legacy/on_state_changed(bits)
	return

/datum/capability/pumped
	var/rate = 1

/datum/capability/pumped/derived()
	. += drawn_from(nameof(undeclared))

/datum/capability/pumped/draw()
	return rate

/datum/capabilityish/derived()
	. += drawn_from(nameof(nothing_here))

/obj/pointer/child/should_run()
	return energy + spare

/obj/pointer/child/draw()
	return pointing

/turf/exact
	var/heat = 0
	var/damage = 0

/turf/exact/derived()
	. += ui_from(nameof(heat))

/turf/exact/tgui_data()
	return heat + damage

/mob/living/exact
	var/mood = 0

/mob/living/exact/derived()
	. += runs_while(nameof(mood))

/mob/living/exact/should_run()
	return mood

/area/exact
	var/lit = 0

/area/exact/derived()
	. += runs_while(nameof(lit))

/area/exact/should_run()
	return lit

/atom/exact
	var/shown = 0

/atom/exact/derived()
	. += runs_while(nameof(shown))

/atom/exact/should_run()
	return shown

/datum/exact
	var/x = 0

/datum/exact/derived()
	. += runs_while(nameof(x))

/datum/exact/should_run()
	return x

/datum/exact/draw()
	return x

/datum/exact/on_state_changed(bits)
	return
