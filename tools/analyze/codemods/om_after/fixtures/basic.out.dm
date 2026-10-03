/datum/thing/proc/schedule(mob/user, list/things)
	// a statement with no payload
	after(src, 5 SECONDS, PROC_REF(tick))
	// one and two payload arguments
	after(src, 2, PROC_REF(tick), with = list(user))
	after(user, 10, PROC_REF(tick), with = list(user, list(1, 2, 3)))
	// the owner may be null, and a global proc takes the payload
	after(null, 1 SECONDS, GLOBAL_PROC_REF(free_tick), with = list(src))
	// the timer id is returned unchanged
	var/id = after(src, 3, PROC_REF(tick))
	if(after(src, 4, PROC_REF(tick), with = list(id)))
		return id
	// nested in the payload of another call
	after(src, 5, PROC_REF(tick), with = list(after(src, 1, PROC_REF(tick), with = list("x, y"))))
	// a string and a comment that name it stay as they are
	var/note = "om_after(src, 1, PROC_REF(tick))"
	// om_after(src, 1, PROC_REF(tick)) is documented here
	for(var/thing in things)
		after(thing, 1, PROC_REF(tick), with = list(thing))
	return id

/datum/thing/proc/spread()
	// a call over several lines keeps its layout and its comments
	after(src,
		7 SECONDS, // when
		PROC_REF(tick), // what
		with = list(id, // payload one
		"a, b")) // payload two

/datum/thing/proc/typed()
	after(src, 1, TYPE_PROC_REF(/datum/thing, tick), with = list((1 + 2) * 3, list("k" = 1)))
