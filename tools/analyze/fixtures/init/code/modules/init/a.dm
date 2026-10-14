/obj/a/Initialize(mapload)
	..()
	return INITIALIZE_HINT_NORMAL
/obj/b/Initialize(mapload) // INIT: sets its own colour
	..()
// INIT: sets its own state from the comment line above
/obj/c/Initialize(mapload)
	..()
	// INIT: not directly above
/obj/d/Initialize(mapload)
	..()
//INIT:no space after the slashes, still a reason
/obj/e/Initialize(mapload)
// INIT:
/obj/f/Initialize(mapload) // INIT:
/obj/g/Initialize(mapload) // ALLOW(init): the fixture keeps this override on purpose
// ALLOW(init): the fixture keeps this override from the comment line above
/obj/h/Initialize(mapload)
/obj/i/Initialize(mapload) // ALLOW(init)
x // INIT: a reason on a line that is not comment-only does not count
/obj/j/Initialize(mapload)
	  // INIT: an indented comment line above counts after lstrip
/obj/k/Initialize(mapload)
/obj/d/proc/Initialize(mapload)
/obj/l/Initialize (mapload)
/obj/m/Initialized(mapload)
/obj/n/initialize(mapload)
/obj/Initialize(mapload)
/Initialize(mapload)
/datum/o/Initialize
/obj/p/Initialize(mapload) // ALLOW(other): another lint's name keeps nothing here
/obj/a/LateInitialize()
/obj/b/LateInitialize() // INIT: reason
/obj/c/LateInitialize() // ALLOW(init): keep this late override with a reason
/obj/proc/LateInitialize(x)
// INIT: late reason from above
/obj/d/LateInitialize()
/obj/q/LateInitialize ()
/obj/r/LateInitializer()
