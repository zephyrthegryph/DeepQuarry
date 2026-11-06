/obj/uttbl
	init_from_table = TRUE
/obj/uttbl/sub/Initialize()
/obj/ut/Initialize(mapload)
	range(1)
	GLOB.thing
/obj/ut/LateInitialize()
/turf/on_materialize()
/obj/bmtbl/sub/Initialize()
/obj/utother/Initialize() // ALLOW(init): kept, so not even a table-pass header
// The table-init declarations (the old per-type flag lines above are ignored now)
GLOBAL_LIST_INIT(init_from_table_fixture, list(
	/obj/uttbl = TRUE
))
