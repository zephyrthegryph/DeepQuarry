#define QDEL_NULL(x) if(x) { qdel(x); x = null }
#define QDEL_LIST(L) for(var/I in L) qdel(I)
/obj/macro/Destroy()
	qdel(M)
