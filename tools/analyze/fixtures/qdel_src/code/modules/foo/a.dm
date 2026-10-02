/obj/foo
	qdel(src)
	qdel (src)
	qdel( src )
	qdel(src, force = TRUE)
	qdel(src,force=TRUE)
	qdel(src) qdel(src)
	qdel(src.thing)
	qdel(src_other)
	qdel(srcs)
	qdel(M)
	qdel(src
	)
	foo.qdel(src)
	obj_qdel(src)
	_qdel(src)
	// qdel(src) in a comment
	var/s = "qdel(src) in a string"
	var/t = "a [qdel(src)] embedded call"
	qdel(src) // ALLOW(lifecycle): the grenade must vanish this instant
	// ALLOW(lifecycle): the grenade must vanish this instant
	qdel(src)
	qdel(src) // ALLOW(lifecycle)
	qdel(src) // ALLOW(other): a reason for some other lint entirely
	qdel(src) // ALLOW(qdel_src): the name of the lint is not the name of the annotation
	qdel(src) // ALLOW(other, lifecycle): a reason that names two lints at once
	x = 1 // ALLOW(lifecycle): not a comment-only line so it keeps nothing below
	qdel(src)
	/* ALLOW(lifecycle): block form of the annotation */ qdel(src)
	QDEL_NULL(src)
	qdel_list(src)
	return qdel(src)
/obj/foo/proc/bar()
	if(x) qdel(src)
	qdel(src); qdel(src)
