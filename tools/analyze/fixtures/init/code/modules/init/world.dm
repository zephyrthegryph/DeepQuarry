/obj/w/Initialize(mapload) // INIT: the fixture sets its own state here
	range(1)
	var/x = orange(2, src)
	var/y = view(3)
	var/z = urange(4)
	var/q = src.range(5)
	var/r = my.view(6)
	var/s = get_view(7)
	GetAbove(src)
	var/t = GetBelow (src)
	var/a = GLOB.thing
	var/b = GLOBAL.thing
	START_PROCESSING(SSobj, src)
	STARTPROCESSING(x)
	range (1)
	// range(1) in a comment
	x = 1 // range(2) in a trailing comment
	range(1) // ALLOW(init): the fixture keeps this read on purpose
	// ALLOW(init): the fixture keeps the next read from the comment above
	range(2)
	range(3) // ALLOW(init)
	var/u = "http://x" + range(1)
	var/v = (range(1))
	if(view(2)) GLOB.both
	var/w = [range(1)]

// a column-0 comment does not end the body
	range(9)
/obj/w/other_proc()
	range(10)
	GLOB.thing
/obj/w/Initialize(mapload) // INIT: the fixture sets its own state here
	range(11)
#define FOO range(1)
	range(12)
/obj/l/LateInitialize() // INIT: the fixture sets its own state here
	range(13)
	GLOB.thing
/obj/w/Initialize(mapload) // INIT: the fixture sets its own state here
	range(14)
/obj/l/LateInitialize() // INIT: the fixture sets its own state here
	range(15)
