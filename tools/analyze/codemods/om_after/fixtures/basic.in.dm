/datum/thing/proc/schedule(mob/user, list/things)
	// a statement with no payload
	om_after(src, 5 SECONDS, PROC_REF(tick))
	// one and two payload arguments
	om_after(src, 2, PROC_REF(tick), user)
	om_after(user, 10, PROC_REF(tick), user, list(1, 2, 3))
	// the owner may be null, and a global proc takes the payload
	om_after(null, 1 SECONDS, GLOBAL_PROC_REF(free_tick), src)
	// the timer id is returned unchanged
	var/id = om_after(src, 3, PROC_REF(tick))
	if(om_after(src, 4, PROC_REF(tick), id))
		return id
	// nested in the payload of another call
	om_after(src, 5, PROC_REF(tick), om_after(src, 1, PROC_REF(tick), "x, y"))
	// a string and a comment that name it stay as they are
	var/note = "om_after(src, 1, PROC_REF(tick))"
	// om_after(src, 1, PROC_REF(tick)) is documented here
	for(var/thing in things)
		om_after(thing, 1, PROC_REF(tick), thing)
	return id

/datum/thing/proc/spread()
	// a call over several lines keeps its layout and its comments
	om_after(src,
		7 SECONDS, // when
		PROC_REF(tick), // what
		id, // payload one
		"a, b") // payload two

/datum/thing/proc/typed()
	om_after(src, 1, TYPE_PROC_REF(/datum/thing, tick), (1 + 2) * 3, list("k" = 1))
