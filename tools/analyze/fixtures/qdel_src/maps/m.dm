/obj/map
	qdel(src)
	qdel(M)
	qdel(src) // ALLOW(lifecycle): maps are scanned like code and take the annotation
	qdel(src, force = TRUE)
