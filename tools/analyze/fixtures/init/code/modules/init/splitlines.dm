/obj/ff/Initialize()
	var/a = 1	range(1)
	var/b = "x  y"
	range(2) // ALLOW(init): the fixture keeps this one across a form feed
	var/c = 1	range(3)
	var/d = 1	GLOB.x
	// ALLOW(init): the fixture keeps the next one from above
	range(4)
	range(5)
	var/e = 1	// ALLOW(init): above a read split off by a group separator	range(6)
	range(7)
	range(8)
/obj/ff2/Initialize()
