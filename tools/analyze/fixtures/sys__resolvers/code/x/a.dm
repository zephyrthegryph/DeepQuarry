// the resolver is declared in the block at the end
/obj/a/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_QDEL
/obj/a/LateInitialize()
	. = INITIALIZE_HINT_QDEL
	qdel(src)
/obj/b/Initialize()
	if(x)
		return INITIALIZE_HINT_QDEL
	expire(0)
	replace_with(src, /obj/c)
	replace_with(srcx, 1)
	qdel_self()
	qdel(src) // ALLOW(sys_init_self_delete): fine
	// ALLOW(sys_init_qdel): above
	return INITIALIZE_HINT_QDEL
/obj/res/Initialize()
	if(x)
		return INITIALIZE_HINT_QDEL
/obj/res/child/Initialize()
	if(x) return INITIALIZE_HINT_QDEL
	. = INITIALIZE_HINT_QDELX
	return INITIALIZE_HINT_QDEL // c
	// return INITIALIZE_HINT_QDEL
/obj/other/proc/foo()
	return INITIALIZE_HINT_QDEL
/obj/d/Initialize()

	qdel(src)
var/x
	qdel(src)
/obj/resx/Initialize()
	if(a)
		return INITIALIZE_HINT_QDEL
/obj/e/proc/Initialize()
	return INITIALIZE_HINT_QDEL
/obj/f/Initialize(a, b)
  return INITIALIZE_HINT_QDEL
CAPABILITIES(/obj/res)
	map_resolver(PROC_REF(r))
