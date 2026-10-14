/obj/a/Initialize()
	GLOB.things += src
	GLOB.things |= src
	GLOB.things.Add(src)
	GLOB.things.Add(1, src)
	GLOB.things.Insert(2, src)
	GLOB.things.Add(src, 1)
	GLOB.things.Add(x(src))
	GLOB.things[key] = src
	GLOB.things[a[b]] = src
	GLOB.things[key] = srcfoo
	GLOB.things += srcfoo
	GLOB.things += src.thing
	GLOB.things -= src
	GLOB.things   +=   src
	GLOB.a += src; GLOB.b |= src
	GLOBAL_LIST_BOILERPLATE(all_things, /obj/a)
	GLOBAL_LIST_BOILERPLATE( spaced , /obj/a)
		GLOBAL_LIST_BOILERPLATE(indented, /obj/a)
	x = 1 GLOBAL_LIST_BOILERPLATE(mid, /obj/a)
	GLOBAL_LIST_BOILERPLATE(nocomma)
	// GLOB.things += src
	var/s = "GLOB.things += src"
	var/u = "http://x" GLOB.things += src
	GLOB.things += src // ALLOW(registry): an object pool
	// ALLOW(registry): clients are not datums
	GLOB.things += src
	// ALLOW(registry)
	GLOB.things += src
	GLOB.things += src // ALLOW(sys_lint): other lint
	// ALLOW(registry): above applies to the next line only
	var/gap = 1
	GLOB.things += src
	// ALLOW(registry): kept hit and a second on the same line
	GLOB.a += src; GLOB.b |= src
	x.GLOB.things += src
	GLOB.things.Add(src) GLOB.things.Add(src)
