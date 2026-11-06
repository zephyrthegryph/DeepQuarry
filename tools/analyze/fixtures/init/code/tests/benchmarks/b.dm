/obj/bmtbl
	init_from_table = TRUE
/obj/bmtbl/sub/Initialize()
/obj/uttbl/other/Initialize() // INIT: flagged from a unit test file
/obj/bm/Initialize(mapload)
	range(1)
/turf/on_materialize()
// The table-init declarations (the old per-type flag lines above are ignored now)
GLOBAL_LIST_INIT(init_from_table_fixture, list(
	/obj/bmtbl = TRUE
))
