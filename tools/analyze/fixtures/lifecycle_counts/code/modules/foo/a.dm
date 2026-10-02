/obj/foo
/obj/foo/Destroy()
	qdel(M)
	qdel (M)
	qdel(src)
	qdel( src )
	qdel(src, force = TRUE)
	qdel(src,force=TRUE)
	qdel(src.thing)
	qdel(src_other)
	qdel(srcs)
	foo.qdel(M)
	obj_qdel(M)
	_qdel(M)
	// qdel(M) in a comment
	var/s = "qdel(M) in a string"
	var/t = "a [qdel(M)] embedded call"
	qdel(M) qdel(N)
	qdel(M) // ALLOW(lifecycle): the round-end sweep deletes every mob
	// ALLOW(lifecycle): the round-end sweep deletes every mob
	qdel(M)
	// ALLOW(lifecycle): the round-end sweep deletes every mob
	qdel(M) qdel(N)
	qdel(M) // ALLOW(lifecycle)
	qdel(M) // ALLOW(other): a reason for some other lint entirely
	qdel(M) // ALLOW(lifecycle, other): a reason for two lints at once
	x = 1 // ALLOW(lifecycle): not a comment-only line so it keeps nothing below
	qdel(M)
	/* ALLOW(lifecycle): block form of the annotation */ qdel(M)
	QDEL_NULL(M)
	qdel_list(M)
	qdel
	qdel(
		M)
/obj/foo/proc/bar()
	qdel(src)
	qdel(M)
