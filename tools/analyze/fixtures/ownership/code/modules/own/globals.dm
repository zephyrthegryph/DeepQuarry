// GLOBAL_* macros declare vars of GLOB: a rel_* accessor on GLOB names them, an unknown one is unknown_var.
GLOBAL_DATUM(fx_blackbox, /obj/holder)
GLOBAL_LIST_EMPTY(fx_pool)
GLOBAL_LIST_EMPTY_TYPED(fx_typed_pool, /obj/holder)
GLOBAL_VAR(fx_plain)

/obj/holder/proc/global_accessors()
	rel_set(GLOB, nameof(fx_blackbox), src)
	rel_add(GLOB, nameof(fx_pool), src)
	rel_add(GLOB, nameof(fx_typed_pool), src)
	rel_set(GLOB, nameof(fx_missing_global), src)
