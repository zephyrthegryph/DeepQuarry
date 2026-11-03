/obj/dottbl
	init_from_table = TRUE
/obj/dot/Initialize(mapload)
	range(1)
/turf/on_materialize()
// The table-init declarations (the old per-type flag lines above are ignored now)
GLOBAL_LIST_INIT(init_from_table_fixture, list(
	/obj/dottbl = TRUE
))
