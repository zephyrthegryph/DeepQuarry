/obj/map
/obj/map/Destroy()
	qdel(M)
	qdel(src)
	qdel(M) // ALLOW(lifecycle): maps are scanned like code and take the annotation
	qdel(N)
